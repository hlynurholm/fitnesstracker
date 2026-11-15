import AVFoundation
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI

// A run as a picture to share: one of eight layouts over a photo, or with nothing behind it as a see-through PNG to
// use as a sticker. Everything here is drawn with plain shapes and text, because the picture is made by
// `ImageRenderer`, which cannot draw maps, glass or blur.

/// The eight colours offered wherever a layout lets a colour be picked.
enum StoryColor: String, CaseIterable, Identifiable {
    case dark, light, blue, green, red, yellow, orange, purple
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .dark: Color(red: 0.08, green: 0.08, blue: 0.10)
        case .light: .white
        case .blue: Color(red: 0.23, green: 0.56, blue: 1.0)
        case .green: Color(red: 0.25, green: 0.84, blue: 0.53)
        case .red: Color(red: 1.0, green: 0.33, blue: 0.30)
        case .yellow: Color(red: 1.0, green: 0.83, blue: 0.25)
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.20)
        case .purple: Color(red: 0.62, green: 0.50, blue: 1.0)
        }
    }
    /// From low to high: blue, orange, red. The same in every theme of the app, since the picture leaves the app.
    static func ramp(_ t: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(0.23, 0.72, 1.0), (1.0, 0.70, 0.24), (1.0, 0.33, 0.30)]
        let x = min(max(t, 0), 1) * 2, i = min(Int(x), 1), f = x - Double(i)
        return Color(red: stops[i].0 + (stops[i + 1].0 - stops[i].0) * f, green: stops[i].1 + (stops[i + 1].1 - stops[i].1) * f, blue: stops[i].2 + (stops[i + 1].2 - stops[i].2) * f)
    }
    /// Black or white, whichever reads on this colour.
    var ink: Color { self == .light || self == .yellow || self == .green || self == .orange ? .black : .white }
}

enum StoryLayout: String, CaseIterable, Identifiable {
    case route, ticket, poster, splits, strip, line, outline, corner
    var id: String { rawValue }
    var title: String {
        switch self {
        case .route: "Route"
        case .ticket: "Ticket"
        case .poster: "Poster"
        case .splits: "Splits"
        case .strip: "Strip"
        case .line: "One line"
        case .outline: "Outline"
        case .corner: "Corner"
        }
    }
}

/// What a route or the split bars are coloured by.
enum StoryPaint: String, CaseIterable, Identifiable {
    case pace, heart, elevation, solid
    var id: String { rawValue }
    var title: String { self == .pace ? "Pace" : self == .heart ? "Heart rate" : self == .elevation ? "Elevation" : "One colour" }
}

/// The choices made on the share screen.
struct StoryOptions {
    var layout = StoryLayout.route
    var color = StoryColor.purple
    var paint = StoryPaint.pace
    var name = ""
    /// The ticket as frosted glass instead of a card of colour.
    var frosted = false
}

/// The numbers and shapes of a run that the layouts draw from.
struct StoryRun {
    let route: RunRoute
    let km: String
    let pace: String
    let time: String
    let heart: String?
    let climb: String?
    let weekday: String
    let date: String
    let splits: [(label: String, pace: Double)]

    init(_ a: GarminActivity) {
        route = RunRoute(a.track ?? [])
        km = a.distance_m.map { String(format: "%.2f", $0 / 1000) } ?? "–"
        pace = a.avg_pace_s_per_km.map { Fmt.time($0) } ?? "–"
        time = a.duration_s.map { Fmt.time($0) } ?? "–"
        heart = a.avg_hr.map { "\(Int($0))" }
        climb = a.elevation_gain_m.map { "\(Int($0.rounded())) m" }
        let label = Day.label(a.day, year: true).split(separator: " ")
        weekday = ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"][String(label.first ?? "")] ?? "Run"
        date = label.dropFirst().joined(separator: " ")
        let rows = ((a.splits ?? []).isEmpty ? (a.laps ?? []) : a.splits!)
        splits = rows.enumerated().compactMap { i, s in s.pace_s_per_km.map { ("\(i + 1)", $0) } }
    }
}

/// The sticker itself, drawn to fill a 9 by 16 frame. `u` is a hundredth of its width, so it looks the same at any size.
struct StorySticker: View {
    let run: StoryRun
    let options: StoryOptions
    /// The photo behind the sticker, blurred, for the frosted ticket to show through. nil when there is no photo.
    var blurred: UIImage? = nil

    private func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.condensed) }
    private func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold).width(.condensed) }

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 100
            ZStack {
                switch options.layout {
                case .route: routeLayout(u)
                case .ticket:
                    // Frosted: the blurred photo, cut to the card's shape, sits under a see-through card.
                    if options.frosted, let blurred {
                        Image(uiImage: blurred).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                            .mask { ticket(u, solid: true) }
                    }
                    ticket(u)
                case .poster: poster(u)
                case .splits: splitsLayout(u)
                case .strip: strip(u)
                case .line: oneLine(u)
                case .outline: outline(u)
                case .corner: corner(u)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .foregroundStyle(.white)
            // A soft shadow keeps white text readable on a bright photo.
            .shadow(color: .black.opacity(0.35), radius: u * 1.2, y: u * 0.4)
        }
    }

    // MARK: Pieces

    private func stat(_ name: String, _ value: String, _ u: CGFloat, ink: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: u * 0.3) {
            Text(name.uppercased()).font(label(u * 4.4)).kerning(u * 0.25).foregroundStyle(ink.opacity(0.75))
            Text(value).font(display(u * 8.5)).foregroundStyle(ink)
        }
    }

    private func stats(_ u: CGFloat, _ items: [(String, String?)]) -> some View {
        HStack(alignment: .top, spacing: u * 6) { ForEach(items.filter { $0.1 != nil }, id: \.0) { stat($0.0, $0.1!, u) } }
    }

    // MARK: Layouts

    /// 1. The route, coloured as chosen, over the distance and three numbers.
    private func routeLayout(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            StoryRoute(route: run.route, paint: options.paint, color: options.color.color, width: u * 1.5).frame(height: u * 62).padding(.bottom, u * 8)
            HStack(alignment: .firstTextBaseline, spacing: u * 2) {
                Text(run.km).font(display(u * 30))
                Text("KM").font(display(u * 10)).opacity(0.75)
            }
            stats(u, [("Pace", run.pace), ("Time", run.time), ("Heart", run.heart)]).padding(.top, u * 5)
        }
        .padding(.horizontal, u * 8).padding(.bottom, u * 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 2. A card of one colour listing every number.
    private func ticket(_ u: CGFloat, solid: Bool = false) -> some View {
        let frosted = options.frosted && !solid
        let ink: Color = frosted ? .white : options.color.ink
        let shape = RoundedRectangle(cornerRadius: u * 5, style: .continuous)
        let rows: [(String, String?)] = [("Distance", "\(run.km) km"), ("Pace", "\(run.pace) /km"), ("Time", run.time), ("Climb", run.climb), ("Heart", run.heart.map { "\($0) bpm" })]
        return VStack(alignment: .leading, spacing: u * 2) {
            Text("\(run.weekday) run".uppercased()).font(display(u * 9.5)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(run.date.uppercased()).font(label(u * 3.6)).kerning(u * 0.2).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
            ForEach(rows.filter { $0.1 != nil }, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: u * 2) {
                    Text(row.0.uppercased()).font(label(u * 3.6)).kerning(u * 0.2).lineLimit(1).fixedSize()
                    Line().stroke(style: StrokeStyle(lineWidth: u * 0.4, dash: [u * 0.4, u * 1.1])).frame(height: u * 0.4).opacity(0.55)
                    // A number never breaks over two lines.
                    Text(row.1!).font(display(u * 6.2)).lineLimit(1).fixedSize()
                }
                .foregroundStyle(ink)
            }
        }
        .padding(u * 5)
        .background {
            if frosted {
                shape.fill(.white.opacity(0.16)).overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: max(u * 0.3, 0.5)))
            } else {
                shape.fill(LinearGradient(colors: [options.color.color, options.color.color.mix(with: options.color == .dark ? .white : .black, by: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .shadow(color: .clear, radius: 0)
        .padding(.horizontal, u * 17)
    }

    /// 3. One huge number under a name of the user's own.
    private func poster(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !options.name.isEmpty { Text(options.name.uppercased()).font(display(u * 9)).foregroundStyle(options.color.color).lineLimit(2).padding(.top, u * 16) }
            Spacer(minLength: 0)
            Text(run.km).font(display(u * 52)).kerning(-u).minimumScaleFactor(0.5).lineLimit(1)
            Text("KILOMETRES IN \(run.time)").font(display(u * 9))
            Text(["\(run.pace) /km", run.heart.map { "\($0) bpm" }, run.climb.map { "\($0) up" }].compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(label(u * 4.6)).kerning(u * 0.25).opacity(0.8).padding(.top, u * 3)
        }
        .padding(.horizontal, u * 7).padding(.bottom, u * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 4. Each kilometre as a bar: coloured by how fast it was, or all in one colour.
    private func splitsLayout(_ u: CGFloat) -> some View {
        let rows = Array(run.splits.prefix(12))
        let fast = rows.map(\.pace).min() ?? 1, slow = rows.map(\.pace).max() ?? 1
        return VStack(alignment: .leading, spacing: u * 2.4) {
            Text("KM SPLITS").font(display(u * 12)).padding(.bottom, u * 2)
            ForEach(rows, id: \.label) { row in
                HStack(spacing: u * 2.5) {
                    Text(row.label).font(display(u * 5.4)).frame(width: u * 6, alignment: .leading)
                    // The fastest kilometre is the longest bar.
                    let share = fast / row.pace
                    let tone = slow > fast ? (slow - row.pace) / (slow - fast) : 0.5
                    Capsule().fill(options.paint == .solid ? options.color.color : StoryColor.ramp(tone)).frame(width: u * 58 * share, height: u * 4)
                    Text(Fmt.time(row.pace)).font(display(u * 5.4))
                }
            }
            stats(u, [("Distance", "\(run.km) km"), ("Average", run.pace)]).padding(.top, u * 6)
        }
        .padding(.horizontal, u * 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 5. A dark bar along the bottom with the route and three numbers.
    private func strip(_ u: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: u * 4) {
                StoryRoute(route: run.route, paint: .solid, color: options.color.color, width: u * 1.1, marks: false).frame(width: u * 20, height: u * 14)
                HStack(alignment: .top, spacing: u * 4) {
                    stat("Km", run.km, u * 0.9); stat("Pace", run.pace, u * 0.9); stat("Time", run.time, u * 0.9)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, u * 5).padding(.vertical, u * 4)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: u * 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: u * 8, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: max(u * 0.3, 0.5)))
            .shadow(color: .clear, radius: 0)
            .padding(.horizontal, u * 6).padding(.bottom, u * 12)
        }
    }

    /// 6. A single line of small text.
    private func oneLine(_ u: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text("\(run.km) KM · \(run.pace) /KM · \(run.time)").font(label(u * 5)).kerning(u * 0.3).padding(.bottom, u * 12)
        }
    }

    /// 7. The route as a thin line with the distance under it.
    private func outline(_ u: CGFloat) -> some View {
        VStack(spacing: u * 4) {
            StoryRoute(route: run.route, paint: .solid, color: .white, width: u * 0.7, marks: false).frame(width: u * 60, height: u * 50)
            Text("\(run.km) KM").font(label(u * 5)).kerning(u * 0.3)
        }
    }

    /// 8. The distance and date in the bottom left corner.
    private func corner(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("RUN · \(run.date.uppercased())").font(label(u * 4.6)).kerning(u * 0.25)
            HStack(alignment: .firstTextBaseline, spacing: u * 1.5) {
                Text(run.km).font(display(u * 20))
                Text("KM").font(display(u * 8)).opacity(0.75)
            }
        }
        .padding(.horizontal, u * 8).padding(.bottom, u * 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p }
}

/// The GPS route with every recorded point, fitted into its frame, coloured by pace, heart rate, elevation or one colour.
struct StoryRoute: View {
    let route: RunRoute
    let paint: StoryPaint
    let color: Color
    let width: CGFloat
    /// A ring at the start and a dot at the finish.
    var marks = true

    var body: some View {
        Canvas { context, size in
            guard !route.isEmpty else { return }
            let lat0 = route.points[0].coordinate.latitude
            let flat = route.points.map { CGPoint(x: $0.coordinate.longitude * cos(lat0 * .pi / 180), y: -$0.coordinate.latitude) }
            let (minX, maxX, minY, maxY) = (flat.map(\.x).min()!, flat.map(\.x).max()!, flat.map(\.y).min()!, flat.map(\.y).max()!)
            let inset = width * 2.5
            let scale = min((size.width - inset * 2) / max(maxX - minX, 1e-9), (size.height - inset * 2) / max(maxY - minY, 1e-9))
            let offset = CGPoint(x: (size.width - (maxX - minX) * scale) / 2, y: (size.height - (maxY - minY) * scale) / 2)
            let place = { (p: CGPoint) in CGPoint(x: (p.x - minX) * scale + offset.x, y: (p.y - minY) * scale + offset.y) }
            // Where each point sits between the low and the high of what the route is coloured by.
            let raw: [Double?] = route.points.map { paint == .heart ? $0.hr : paint == .elevation ? $0.alt : nil }
            let smooth = RunRoute.smooth(raw, reach: 5)
            let known = smooth.compactMap { $0 }.sorted()
            let low = known.isEmpty ? 0 : known[known.count / 10], high = known.isEmpty ? 1 : known[min(known.count - 1, known.count * 9 / 10)]
            let tone = { (i: Int) -> Double in
                if paint == .pace || known.isEmpty { return route.points[i].effort }
                guard let v = smooth[i], high > low else { return 0.5 }
                return min(max((v - low) / (high - low), 0), 1)
            }
            if paint == .solid {
                var path = Path()
                path.addLines(flat.map(place))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            } else {
                for i in 1..<flat.count {
                    var segment = Path()
                    segment.move(to: place(flat[i - 1])); segment.addLine(to: place(flat[i]))
                    context.stroke(segment, with: .color(StoryColor.ramp((tone(i - 1) + tone(i)) / 2)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            if marks {
                let start = place(flat[0]), end = place(flat[flat.count - 1])
                let ring = CGRect(x: start.x - width * 1.5, y: start.y - width * 1.5, width: width * 3, height: width * 3)
                context.fill(Path(ellipseIn: ring), with: .color(.black))
                context.stroke(Path(ellipseIn: ring), with: .color(StoryColor.green.color), lineWidth: width * 0.8)
                context.fill(Path(ellipseIn: CGRect(x: end.x - width * 1.3, y: end.y - width * 1.3, width: width * 2.6, height: width * 2.6)), with: .color(.white))
            }
        }
    }
}

/// The share screen: the picture, the eight layouts, each layout's own choices, and where the picture goes.
struct StoryScreen: View {
    let activity: GarminActivity
    @State private var options = StoryOptions()
    @State private var photo: UIImage?
    @State private var blurred: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var camera = false
    @State private var shared: URL?
    @State private var message: String?

    var body: some View {
        let run = StoryRun(activity)
        Screen {
            // The picture as it will be saved. The checkerboard stands for see-through.
            picture(run, checker: true)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .frame(maxWidth: 300).frame(maxWidth: .infinity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(StoryLayout.allCases) { layout in
                        Button { options.layout = layout } label: {
                            Text(layout.title).font(Theme.Typography.label).foregroundStyle(options.layout == layout ? Theme.Palette.onAccent : Theme.Palette.text)
                                .padding(.horizontal, Theme.Space.m).frame(height: 36)
                                .background(options.layout == layout ? Theme.Palette.accent : Theme.Palette.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            choices(run)

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Photo behind it", note: photo == nil ? "none: saves see-through" : nil)
                HStack(spacing: Theme.Space.s) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take photo") { camera = true }.buttonStyle(.tinted) }
                    PhotosPicker(selection: $picked, matching: .images) { Text("Choose photo") }.buttonStyle(.tinted)
                    if photo != nil { Button("Remove") { photo = nil; picked = nil }.buttonStyle(.tinted) }
                }
                Button(photo == nil ? "Save or share as PNG sticker" : "Save or share") { share(run) }.buttonStyle(.primary)
                if let message { Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }
            .card()
        }
        .inlineTitle("Share run")
        .onChange(of: photo) { _, image in blurred = image.flatMap(Self.blur) }
        .onChange(of: picked) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image } }
        }
        .fullScreenCover(isPresented: $camera) { StoryCamera(run: run, options: options) { photo = $0 } }
        .sheet(item: $shared) { ShareSheet(items: [$0]) }
    }

    /// The photo (or nothing) with the sticker over it, 9 by 16.
    private func picture(_ run: StoryRun, checker: Bool) -> some View {
        StorySticker(run: run, options: options, blurred: blurred)
            .background {
                if let photo { Image(uiImage: photo).resizable().scaledToFill() } else if checker { Checkerboard() }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .clipped()
    }

    @ViewBuilder
    private func choices(_ run: StoryRun) -> some View {
        let layout = options.layout
        if [.route, .ticket, .poster, .splits, .strip].contains(layout) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if layout == .poster {
                    LabeledField(label: "Name (the race, the place, the kind of run)") { TextField("Evening loop", text: $options.name) }
                }
                if layout == .route {
                    Picker("Route colour", selection: $options.paint) { ForEach(StoryPaint.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }
                if layout == .splits {
                    Picker("Bar colour", selection: Binding(get: { options.paint == .solid ? StoryPaint.solid : .pace }, set: { options.paint = $0 })) {
                        Text("By speed").tag(StoryPaint.pace); Text("One colour").tag(StoryPaint.solid)
                    }
                    .pickerStyle(.segmented)
                }
                if layout == .ticket {
                    Picker("Card", selection: $options.frosted) { Text("Colour").tag(false); Text("Frosted glass").tag(true) }.pickerStyle(.segmented)
                    if options.frosted, photo == nil { Text("Without a photo the card is saved lightly tinted and see-through. The blur shows once there is a photo behind it.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
                }
                if !(layout == .route || layout == .splits) || options.paint == .solid, !(layout == .ticket && options.frosted) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(StoryColor.allCases) { c in
                            Button { options.color = c } label: {
                                Circle().fill(c.color).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Theme.Palette.separator, lineWidth: 1))
                                    .overlay(Circle().strokeBorder(Theme.Palette.text, lineWidth: options.color == c ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain).frame(maxWidth: .infinity)
                            .accessibilityLabel(c.rawValue.capitalizedFirst).accessibilityAddTraits(options.color == c ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
            .card()
        }
    }

    /// The photo, blurred, at a small size (the blur hides the loss).
    private static func blur(_ image: UIImage) -> UIImage? {
        let side: CGFloat = 540 / max(image.size.width, 1)
        let size = CGSize(width: 540, height: image.size.height * side)
        let small = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let input = CIImage(image: small) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 14
        guard let output = filter.outputImage?.cropped(to: input.extent), let cg = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Draws the picture at 1080 by 1920 and hands it to the share sheet as a PNG file, which keeps it see-through.
    private func share(_ run: StoryRun) {
        let renderer = ImageRenderer(content: picture(run, checker: false).frame(width: 360, height: 640))
        renderer.scale = 3
        renderer.isOpaque = false
        guard let data = renderer.uiImage?.pngData() else { message = "The picture could not be made."; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("run-\(activity.day)-\(options.layout.rawValue).png")
        do { try data.write(to: url); shared = url; message = nil } catch { message = error.localizedDescription }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Grey squares, the usual sign for "nothing here".
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 14
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.11)))
            for row in 0...Int(size.height / side) {
                for column in 0...Int(size.width / side) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Color(white: 0.16)))
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The app's own camera for a story: the viewfinder is the 9 by 16 picture itself, with the sticker on top, so what
/// is on screen is what gets saved.
private struct StoryCamera: View {
    let run: StoryRun
    let options: StoryOptions
    let taken: (UIImage) -> Void
    @State private var camera = CameraModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Space.l) {
                CameraPreview(session: camera.session)
                    .overlay { StorySticker(run: run, options: options) }
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay { if let problem = camera.problem { Text(problem).font(Theme.Typography.callout).foregroundStyle(.white).multilineTextAlignment(.center).padding() } }
                HStack {
                    Button("Cancel") { dismiss() }.font(Theme.Typography.label).foregroundStyle(.white).frame(width: 90, alignment: .leading)
                    Spacer()
                    Button { camera.capture { image in taken(image); dismiss() } } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 4).padding(-7))
                    }
                    .accessibilityLabel("Take photo")
                    Spacer()
                    Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).foregroundStyle(.white) }
                        .frame(width: 90, alignment: .trailing).accessibilityLabel("Switch camera")
                }
                .padding(.horizontal, Theme.Space.xl)
            }
            .padding(.vertical, Theme.Space.m)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

/// The capture session behind `StoryCamera`.
@Observable
private final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private(set) var problem: String?
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private var position = AVCaptureDevice.Position.back
    @ObservationIgnored private var done: ((UIImage) -> Void)?
    @ObservationIgnored private let queue = DispatchQueue(label: "story.camera")

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { problem = "Allow the camera for Training in the Settings app to take a photo here."; return }
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo
            use(position)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() { queue.async { [self] in session.stopRunning() } }

    func flip() {
        position = position == .back ? .front : .back
        queue.async { [self] in session.beginConfiguration(); use(position); session.commitConfiguration() }
    }

    private func use(_ position: AVCaptureDevice.Position) {
        session.inputs.forEach(session.removeInput)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
    }

    func capture(_ done: @escaping (UIImage) -> Void) {
        self.done = done
        queue.async { [self] in
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 } // upright, phone held tall
                if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = position == .front }
            }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let cropped = Self.tall(image)
        DispatchQueue.main.async { self.done?(cropped) }
    }

    /// The middle 9 by 16 of a photo, which is what the viewfinder showed.
    private static func tall(_ image: UIImage) -> UIImage {
        let size = image.size
        let width = min(size.width, size.height * 9 / 16), height = width * 16 / 9
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { _ in image.draw(at: CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2)) }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> Layer {
        let view = Layer()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: Layer, context: Context) {}

    final class Layer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
