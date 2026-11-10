import MapKit
import SwiftUI

/// The GPS route of a run, with how hard each part was run relative to the rest of it.
struct RunRoute {
    /// effort: 0 slowest part, 1 fastest. The rest is what the watch read there (pace is the smoothed one).
    struct Point { let coordinate: CLLocationCoordinate2D; let effort: Double; let km: Double; let seconds: Double?; let pace: Double?; let hr: Double?; let alt: Double? }
    let points: [Point]
    var isEmpty: Bool { points.count < 2 }

    init(_ track: [GarminActivity.Point]) {
        let gps = track.filter { $0.lat != nil && $0.lon != nil }
        let paces = Self.smooth(Self.smooth(gps.map(\.pace), reach: 6), reach: 6) // twice, so the colours change gradually
        // Spread the colours between the 10th and 90th percentile, so one walk break does not flatten the rest.
        let sorted = paces.compactMap { $0 }.sorted()
        let fast = sorted.isEmpty ? 0 : sorted[sorted.count / 10], slow = sorted.isEmpty ? 1 : sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        points = zip(gps, paces).map { p, pace in
            let effort = pace.map { slow > fast ? min(max((slow - $0) / (slow - fast), 0), 1) : 0.5 } ?? 0.5
            return Point(coordinate: .init(latitude: p.lat!, longitude: p.lon!), effort: effort, km: p.d ?? 0, seconds: p.t, pace: pace, hr: p.hr, alt: p.alt)
        }
    }

    /// Seconds into the run at a point, and the point reached by a given time.
    func seconds(at index: Int) -> Double { points[index].seconds ?? Double(index) }
    func index(atSeconds t: Double) -> Int { points.indices.first { seconds(at: $0) >= t } ?? points.count - 1 }

    /// Where each whole kilometre was reached.
    var kilometres: [(km: Int, coordinate: CLLocationCoordinate2D)] {
        guard let total = points.last?.km, total >= 1 else { return [] }
        return (1...Int(total)).compactMap { k in points.first { $0.km >= Double(k) }.map { (k, $0.coordinate) } }
    }

    /// Moving average over the samples within `reach` on each side, skipping gaps.
    static func smooth(_ values: [Double?], reach: Int = 2) -> [Double?] {
        values.indices.map { i in
            let window = values[max(0, i - reach)...min(values.count - 1, i + reach)].compactMap { $0 }
            return window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
        }
    }

    /// The route cut into short pieces, each with one colour, for drawing.
    var pieces: [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        guard !isEmpty else { return [] }
        let size = max(2, points.count / 60)
        return stride(from: 0, to: points.count - 1, by: size).map { start in
            let part = points[start...min(start + size, points.count - 1)] // one point shared with the next piece
            return (part.map(\.coordinate), Theme.Palette.effort(part.map(\.effort).reduce(0, +) / Double(part.count)))
        }
    }

    /// A map region that holds the whole route with some air around it.
    var region: MKCoordinateRegion {
        let lats = points.map(\.coordinate.latitude), lons = points.map(\.coordinate.longitude)
        let (minLat, maxLat, minLon, maxLon) = (lats.min() ?? 0, lats.max() ?? 0, lons.min() ?? 0, lons.max() ?? 0)
        return MKCoordinateRegion(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: .init(latitudeDelta: max(maxLat - minLat, 0.002) * 1.35, longitudeDelta: max(maxLon - minLon, 0.002) * 1.35))
    }
}

/// The route as a bare shape, coloured by pace, with a ring at the start and a dot at the finish. For widgets.
struct RouteSketch: View {
    let route: RunRoute
    var lineWidth: CGFloat = 3.5

    var body: some View {
        Canvas { context, size in
            guard !route.isEmpty else { return }
            // Flat projection: fine over the few kilometres of a run.
            let lat0 = route.points[0].coordinate.latitude
            let flat = route.points.map { CGPoint(x: $0.coordinate.longitude * cos(lat0 * .pi / 180), y: -$0.coordinate.latitude) }
            let (minX, maxX, minY, maxY) = (flat.map(\.x).min()!, flat.map(\.x).max()!, flat.map(\.y).min()!, flat.map(\.y).max()!)
            let inset = lineWidth * 2
            let scale = min((size.width - inset * 2) / max(maxX - minX, 1e-9), (size.height - inset * 2) / max(maxY - minY, 1e-9))
            let offset = CGPoint(x: (size.width - (maxX - minX) * scale) / 2, y: (size.height - (maxY - minY) * scale) / 2)
            let place = { (p: CGPoint) in CGPoint(x: (p.x - minX) * scale + offset.x, y: (p.y - minY) * scale + offset.y) }
            for i in 1..<flat.count {
                var segment = Path()
                segment.move(to: place(flat[i - 1])); segment.addLine(to: place(flat[i]))
                context.stroke(segment, with: .color(Theme.Palette.effort((route.points[i - 1].effort + route.points[i].effort) / 2)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            let start = place(flat[0]), end = place(flat[flat.count - 1])
            context.fill(Path(ellipseIn: CGRect(x: end.x - lineWidth * 1.4, y: end.y - lineWidth * 1.4, width: lineWidth * 2.8, height: lineWidth * 2.8)), with: .color(Theme.Palette.text))
            context.fill(Path(ellipseIn: CGRect(x: start.x - lineWidth * 1.6, y: start.y - lineWidth * 1.6, width: lineWidth * 3.2, height: lineWidth * 3.2)), with: .color(Theme.Palette.surface))
            context.stroke(Path(ellipseIn: CGRect(x: start.x - lineWidth * 1.6, y: start.y - lineWidth * 1.6, width: lineWidth * 3.2, height: lineWidth * 3.2)), with: .color(Theme.Palette.ok), lineWidth: lineWidth * 0.8)
        }
        .accessibilityLabel("Route of the run")
    }
}

/// One run: the route on a map coloured by pace, the headline numbers, pace, heart rate and elevation over the
/// distance, the kilometre splits and the time in each heart rate zone.
struct RunScreen: View {
    let id: Int
    @State private var activity: GarminActivity?
    @State private var error: String?

    var body: some View {
        Screen {
            if let a = activity {
                let track = a.track ?? []
                let route = RunRoute(track)
                if !route.isEmpty { RouteMap(route: route, activity: a) }
                headline(a)
                tiles(a)
                profiles(a, track)
                splits(a)
                zones(a)
                if route.isEmpty, !track.isEmpty {
                    Text("No GPS positions in this recording, so there is no route to draw.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
                }
            } else if let error {
                ErrorCard(message: error) { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle(activity.map { Day.label($0.day) } ?? "Run")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { activity = try await API.shared.get("/api/activities/\(id)", cache: true); error = nil } catch { self.error = error.localizedDescription }
    }

    // MARK: Sections

    private func headline(_ a: GarminActivity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(a.name ?? "Run").font(Theme.Typography.title)
            Text([Day.label(a.day, year: true), Fmt.timestamp(a.start_time).map { $0.formatted(date: .omitted, time: .shortened) }].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
        }
        .padding(.horizontal, Theme.Space.xs)
    }

    private func tiles(_ a: GarminActivity) -> some View {
        let items: [(String, String?, String?)] = [
            ("Distance", a.distance_m.map { String(format: "%.2f km", $0 / 1000) }, nil),
            ("Time", a.duration_s.map { Fmt.time($0) }, nil),
            ("Pace", a.avg_pace_s_per_km.map { Fmt.pace($0) }, a.best_1k_s.map { "best km \(Fmt.time($0))" }),
            ("Heart rate", a.avg_hr.map { "\(Int($0)) bpm" }, a.max_hr.map { "max \(Int($0))" }),
            ("Climb", a.elevation_gain_m.map { "\(Int($0.rounded())) m" }, nil),
            ("Calories", a.calories.map { "\(Fmt.whole($0)) kcal" }, nil),
            ("Cadence", a.avg_cadence.map { "\(Int(($0 < 120 ? $0 * 2 : $0).rounded())) spm" }, nil), // watches report one foot
            ("Best 5 km", a.best_5k_s.map { Fmt.time($0) }, nil),
        ]
        return TileGrid {
            ForEach(items.filter { $0.1 != nil }, id: \.0) { Tile(label: $0.0, value: $0.1!, detail: $0.2) }
        }
    }

    @ViewBuilder
    private func profiles(_ a: GarminActivity, _ track: [GarminActivity.Point]) -> some View {
        let km = track.map { $0.d ?? 0 }
        // Pace: smoothed, and capped so a stop does not squash the rest of the line.
        let smoothed = RunRoute.smooth(track.map(\.pace))
        let cap = (a.avg_pace_s_per_km ?? smoothed.compactMap { $0 }.sorted().dropFirst(smoothed.count / 2).first ?? 600) * 1.6
        let pace = zip(km, smoothed).compactMap { d, p in p.map { ProfileChart.Sample(x: d, y: min($0, cap)) } }
        if pace.count > 5 {
            chartCard("Pace", note: "min per km, faster is higher") {
                ProfileChart(samples: pace, color: Theme.Palette.run, lowerIsBetter: true, average: a.avg_pace_s_per_km) { Fmt.time($0) }
            }
        }
        let hr = zip(km, track).compactMap { d, p in p.hr.map { ProfileChart.Sample(x: d, y: $0) } }
        if hr.count > 5 {
            // Coloured by zone when the activity says where the zones start.
            let bands = Array(zip(a.hr_zones?.edges ?? [], Self.zoneColors)).map { (from: $0.0, color: $0.1) }
            chartCard("Heart rate", note: a.avg_hr.map { "average \(Int($0)) bpm" }) {
                ProfileChart(samples: hr, color: Theme.Palette.heart, average: a.avg_hr, bands: bands) { "\(Int($0.rounded()))" }
                if !bands.isEmpty {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                            HStack(spacing: 3) {
                                Circle().fill(band.color).frame(width: 6, height: 6)
                                Text("Z\(i + 1) \(Int(band.from))+").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        let alt = zip(km, track).compactMap { d, p in p.alt.map { ProfileChart.Sample(x: d, y: $0) } }
        if alt.count > 5, (alt.map(\.y).max() ?? 0) - (alt.map(\.y).min() ?? 0) >= 3 {
            chartCard("Elevation", note: a.elevation_gain_m.map { "\(Int($0.rounded())) m climbed" }) {
                ProfileChart(samples: alt, color: Theme.Palette.ok, height: 110) { "\(Int($0.rounded())) m" }
            }
        }
    }

    /// Heart rate zones 1 to 5, the same in the chart and in the bar.
    private static let zoneColors = [Theme.Palette.rest, Theme.Palette.calm, Theme.Palette.ok, Theme.Palette.energy, Theme.Palette.heart]

    private func chartCard(_ title: String, note: String?, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle(title, note: note)
            chart()
        }
        .card()
    }

    @ViewBuilder
    private func splits(_ a: GarminActivity) -> some View {
        let rows = ((a.splits ?? []).isEmpty ? (a.laps ?? []) : a.splits!).filter { $0.pace_s_per_km != nil }
        if !rows.isEmpty {
            let paces = rows.compactMap(\.pace_s_per_km), fast = paces.min() ?? 1, slow = paces.max() ?? 1
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle((a.splits ?? []).isEmpty ? "Laps" : "Splits", note: "pace per km")
                ForEach(Array(rows.enumerated()), id: \.offset) { i, s in
                    let pace = s.pace_s_per_km ?? slow
                    let effort = slow > fast ? (slow - pace) / (slow - fast) : 0.5
                    HStack(spacing: Theme.Space.s) {
                        Text((s.km ?? s.index)?.text ?? "\(i + 1)").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted).frame(width: 22, alignment: .leading)
                        GeometryReader { geo in
                            // The fastest split fills the row; the others are as long as their speed relative to it.
                            Capsule().fill(Theme.Palette.effort(effort)).frame(width: max(12, geo.size.width * fast / pace))
                        }
                        .frame(height: 12)
                        Text(Fmt.time(pace)).font(Theme.Typography.callout.monospacedDigit()).frame(width: 46, alignment: .trailing)
                        Text(s.avg_hr.map { "\(Int($0))" } ?? "").font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Palette.heart).frame(width: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func zones(_ a: GarminActivity) -> some View {
        if let seconds = a.hr_zones?.seconds, seconds.reduce(0, +) > 0 {
            let parts = Array(zip(seconds, Self.zoneColors))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Time in heart rate zones", note: a.hr_zones?.max_hr_used.map { "max \(Int($0))" })
                SegmentBar(parts: parts.map { ($0.0, $0.1) }, height: 12)
                HStack(spacing: Theme.Space.m) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 3) { Circle().fill(p.1).frame(width: 6, height: 6); Text("Z\(i + 1)").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted) }
                            Text(Fmt.time(p.0)).font(Theme.Typography.caption.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .card()
        }
    }
}

/// The route on a map with the run's numbers on it: a marker at every kilometre, the totals along the top, and a
/// point that moves along the route (drag the strip, or tap the route) to read pace, heart rate and height there.
private struct RouteMap: View {
    let route: RunRoute
    let activity: GarminActivity
    @State private var picked: Int?
    @State private var playing = false
    @State private var stripWidth: CGFloat = 0
    /// How many times faster than real life the playback runs.
    static let playbackSpeed = 200.0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            MapReader { proxy in
                Map(initialPosition: .region(route.region), interactionModes: [.pan, .zoom]) {
                    // A light casing under the coloured line keeps the route readable on any map.
                    MapPolyline(coordinates: route.points.map(\.coordinate))
                        .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    ForEach(Array(route.pieces.enumerated()), id: \.offset) { _, piece in
                        MapPolyline(coordinates: piece.coordinates).stroke(piece.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(route.kilometres, id: \.km) { mark in
                        Annotation("", coordinate: mark.coordinate, anchor: .center) {
                            Text("\(mark.km)").font(Theme.Typography.label.monospacedDigit()).foregroundStyle(Theme.Palette.text)
                                .frame(width: 20, height: 20).background(Theme.Palette.surface, in: Circle())
                                .overlay(Circle().stroke(Theme.Palette.text.opacity(0.25), lineWidth: 1))
                                .accessibilityLabel("Kilometre \(mark.km)")
                        }
                    }
                    Annotation("Start", coordinate: route.points[0].coordinate, anchor: .center) {
                        Circle().fill(Theme.Palette.surface).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.Palette.ok, lineWidth: 4))
                    }
                    Annotation("Finish", coordinate: route.points[route.points.count - 1].coordinate, anchor: .center) {
                        Image(systemName: "flag.checkered").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Theme.Palette.text.opacity(0.85), in: Circle())
                    }
                    if let p = picked.map({ route.points[$0] }) {
                        Annotation("", coordinate: p.coordinate, anchor: .center) {
                            Circle().fill(Theme.Palette.effort(p.effort)).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .onTapGesture { playing = false; picked = nearest(to: $0, proxy) } // a tap off the route clears the point
                .safeAreaInset(edge: .top, spacing: 0) { readout }
                .safeAreaInset(edge: .bottom, spacing: 0) { strip }
            }
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            HStack(spacing: Theme.Space.s) {
                Text("slower").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.25).map { Theme.Palette.effort($0) }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 5).clipShape(Capsule())
                Text("faster").font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
            }
            .padding(.horizontal, Theme.Space.xs)
            Text("Press play to watch the run at \(Int(Self.playbackSpeed))× speed. Drag along the strip or tap the route to read any point.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
        }
        .task(id: playing) { await play() }
    }

    /// Moves the point along the route by the watch's own clock, from where it stands (or from the start once it
    /// has reached the end).
    private func play() async {
        guard playing else { return }
        let end = route.seconds(at: route.points.count - 1)
        let from = picked.flatMap { $0 < route.points.count - 1 ? route.seconds(at: $0) : nil } ?? route.seconds(at: 0)
        let began = Date()
        var clock = from
        while !Task.isCancelled, clock < end {
            try? await Task.sleep(for: .milliseconds(33))
            clock = from + Date().timeIntervalSince(began) * Self.playbackSpeed
            if !Task.isCancelled { picked = route.index(atSeconds: clock) }
        }
        if !Task.isCancelled { playing = false }
    }

    /// The route point under a tap, if the tap landed close enough to the line.
    private func nearest(to location: CGPoint, _ proxy: MapProxy) -> Int? {
        let hits = route.points.indices.compactMap { i in
            proxy.convert(route.points[i].coordinate, to: .local).map { (index: i, distance: hypot($0.x - location.x, $0.y - location.y)) }
        }
        return hits.min { $0.distance < $1.distance }.flatMap { $0.distance < 36 ? $0.index : nil }
    }

    /// The totals of the run, or the readings at the picked point.
    private var readout: some View {
        let p = picked.map { route.points[$0] }
        let a = activity
        let whole = { (v: Double?) in v.map { "\(Int($0.rounded()))" } }
        let items: [(String, String?)] = p.map { p in
            [("Distance", String(format: "%.2f km", p.km)), ("Time", p.seconds.map { Fmt.time($0) }), ("Pace", p.pace.map { Fmt.time($0) }),
             ("Heart", whole(p.hr)), ("Height", whole(p.alt).map { $0 + " m" })]
        } ?? [("Distance", a.distance_m.map { String(format: "%.2f km", $0 / 1000) }), ("Time", a.duration_s.map { Fmt.time($0) }),
              ("Avg pace", a.avg_pace_s_per_km.map { Fmt.time($0) }), ("Avg heart", whole(a.avg_hr)), ("Climb", whole(a.elevation_gain_m).map { $0 + " m" })]
        return HStack(spacing: Theme.Space.xs) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(Theme.Typography.label).foregroundStyle(Theme.Palette.muted)
                    Text(value ?? "–").font(Theme.Typography.callout.weight(.semibold).monospacedDigit())
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
    }

    /// The run from start to finish as bars: as tall as the ground was high, coloured by pace. Drag across it to move the point.
    private var strip: some View {
        HStack(spacing: Theme.Space.m) {
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Theme.Palette.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause playback" : "Play the run at \(Int(Self.playbackSpeed)) times speed")
            Canvas { context, size in
                let count = min(route.points.count, 80)
                let alts = route.points.compactMap(\.alt), low = alts.min() ?? 0, high = alts.max() ?? 0
                let width = size.width / CGFloat(count)
                for b in 0..<count {
                    let part = route.points[(b * route.points.count / count)..<max((b + 1) * route.points.count / count, b * route.points.count / count + 1)]
                    let partAlts = part.compactMap(\.alt)
                    let level = high - low >= 3 && !partAlts.isEmpty ? (partAlts.reduce(0, +) / Double(partAlts.count) - low) / (high - low) : 0.5
                    let height = size.height * (0.3 + 0.7 * level)
                    let bar = CGRect(x: CGFloat(b) * width + 0.75, y: size.height - height, width: max(width - 1.5, 1), height: height)
                    let passed = picked.map { part.startIndex <= $0 } ?? true
                    context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(Theme.Palette.effort(part.map(\.effort).reduce(0, +) / Double(part.count)).opacity(passed ? 1 : 0.3)))
                }
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                playing = false
                picked = Int((min(max(drag.location.x / max(stripWidth, 1), 0), 1) * Double(route.points.count - 1)).rounded())
            })
            .accessibilityLabel("Scrub along the run")
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(.regularMaterial)
    }
}
