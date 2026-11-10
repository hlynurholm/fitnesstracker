import ActivityKit
import AVFoundation
import Observation
import UIKit

/// Owns the one workout Live Activity: starts it, pushes new content, ends it.
@MainActor
enum LiveWorkout {
    typealias State = WorkoutActivityAttributes.ContentState
    private static var activity: Activity<WorkoutActivityAttributes>?

    /// Called at launch: an activity left over from a previous run of the app has nothing driving it any more.
    /// A lift in progress gets its activity back as soon as Today loads.
    static func endLeftovers() {
        for old in Activity<WorkoutActivityAttributes>.activities where old.id != activity?.id {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Starts the activity, or updates it when one for the same session is already on screen.
    static func show(name: String, isRun: Bool, startedAt: Date, state: State) {
        if let activity, activity.attributes.name == name, activity.attributes.startedAt == startedAt {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
            return
        }
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(name: name, isRun: isRun, startedAt: startedAt)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }

    static func end() {
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Runs a timed run session: warm-up, work and recovery reps, cool-down. Speaks a cue at every change and keeps the
/// Live Activity on the current phase. With no phases it is a plain run timer with a heart rate target.
@MainActor @Observable
final class IntervalRunner {
    static let shared = IntervalRunner()

    struct Phase: Hashable {
        let kind: WorkoutActivityAttributes.Phase
        let title: String
        let detail: String
        let seconds: Int
        let target: String?
        let cue: String
    }

    private(set) var name = ""
    private(set) var date = ""
    private(set) var phases: [Phase] = []
    private(set) var index = 0
    private(set) var startedAt: Date?
    private(set) var phaseEnds: Date?
    private var steadyTarget: String?
    private var ticker: Task<Void, Never>?
    private let voice = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let silence = AVAudioPlayerNode()

    var isActive: Bool { startedAt != nil }
    var current: Phase? { phases.indices.contains(index) ? phases[index] : nil }
    var next: Phase? { phases.indices.contains(index + 1) ? phases[index + 1] : nil }

    /// Phases for an interval template. The warm-up and cool-down lengths are not structured in program.js
    /// (the text says "10 min easy jog"), so they are constants here.
    static func phases(for template: Template, zones: [Program.Zone]) -> [Phase] {
        guard let iv = template.intervals else { return [] }
        let easy = zones.first.map { "under \($0.to) bpm" }
        let hard = zones.first { $0.name == "Threshold" }.map { "\($0.from)–\($0.to) bpm by the end" }
        var out = [Phase(kind: .warmup, title: "Warm-up", detail: "Easy jog", seconds: 600, target: easy, cue: "Warm up. Ten minutes easy.")]
        for rep in 1...max(iv.reps, 1) {
            let label = "Rep \(rep) of \(iv.reps)"
            out.append(Phase(kind: .work, title: "Run", detail: [label, template.pace].compactMap { $0 }.joined(separator: " · "), seconds: iv.workSec, target: hard, cue: "Run. \(label)."))
            if rep < iv.reps {
                out.append(Phase(kind: .recover, title: "Recover", detail: "\(label) done", seconds: iv.restSec, target: easy, cue: "Recover."))
            }
        }
        out.append(Phase(kind: .cooldown, title: "Cool-down", detail: "Easy jog or walk", seconds: 300, target: easy, cue: "Last rep done. Cool down."))
        #if DEBUG
        // TRAINING_INTERVAL_SCALE=60 turns minutes into seconds, to watch a whole session in the simulator.
        if let scale = ProcessInfo.processInfo.environment["TRAINING_INTERVAL_SCALE"].flatMap(Int.init), scale > 1 {
            return out.map { Phase(kind: $0.kind, title: $0.title, detail: $0.detail, seconds: max(3, $0.seconds / scale), target: $0.target, cue: $0.cue) }
        }
        #endif
        return out
    }

    func start(name: String, date: String, phases: [Phase], steadyTarget: String?) {
        stop()
        self.name = name; self.date = date; self.phases = phases; self.steadyTarget = steadyTarget
        startedAt = Date()
        index = 0
        if phases.isEmpty { publish(); return }
        keepAlive(true)
        enter(0)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let end = self.phaseEnds else { return }
                if Date() >= end { self.advance() }
            }
        }
    }

    /// Jump to the next phase now (for a shorter warm-up, for example).
    func advance() {
        if index + 1 < phases.count { enter(index + 1) } else { speak("Session complete."); stop() }
    }

    func stop() {
        ticker?.cancel(); ticker = nil
        keepAlive(false)
        startedAt = nil; phaseEnds = nil; phases = []
        LiveWorkout.end()
    }

    private func enter(_ i: Int) {
        index = i
        phaseEnds = Date().addingTimeInterval(TimeInterval(phases[i].seconds))
        UINotificationFeedbackGenerator().notificationOccurred(phases[i].kind == .work ? .warning : .success)
        speak(phases[i].cue)
        publish()
    }

    private func publish() {
        guard let startedAt else { return }
        let state: LiveWorkout.State
        if let p = current, let end = phaseEnds {
            let reps = phases.filter { $0.kind == .work }.count
            let done = phases.prefix(index + 1).filter { $0.kind == .work }.count
            state = .init(phase: p.kind, title: p.title, detail: p.detail, progress: next.map { "Next: \($0.title) \(Fmt.time(Double($0.seconds)))" } ?? "\(done) of \(reps) reps", target: p.target, restSince: nil, countdown: Date()...max(end, Date()))
        } else {
            state = .init(phase: .steady, title: name, detail: "Go by heart rate, not pace", progress: Day.label(date), target: steadyTarget, restSince: nil, countdown: nil)
        }
        LiveWorkout.show(name: name, isRun: true, startedAt: startedAt, state: state)
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        voice.speak(u)
    }

    // ponytail: a looping silent buffer keeps the app running in the background so cues and Live Activity updates fire
    // on time with the phone locked. It is a private-app shortcut (App Store review rejects silent audio). The upgrade
    // path is Live Activity push updates sent by the Worker through APNs.
    private func keepAlive(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        guard on else {
            silence.stop(); engine.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        buffer.frameLength = buffer.frameCapacity
        if silence.engine == nil {
            engine.attach(silence)
            engine.connect(silence, to: engine.mainMixerNode, format: format)
        }
        try? engine.start()
        silence.scheduleBuffer(buffer, at: nil, options: .loops)
        silence.play()
    }
}
