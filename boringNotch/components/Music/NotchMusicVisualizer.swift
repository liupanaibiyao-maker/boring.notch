//
//  NotchMusicVisualizer.swift
//  boringNotch
//
//  The two music-reactive slots that sit in the empty bottom corners of the
//  expanded music player. Everything is drawn in SwiftUI Canvas from the live
//  audio spectrum published by AudioSpectrumManager.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Styles

enum MusicVisualizerStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case off
    case glow
    case spectrum
    case lyric
    case arc
    case cat
    case stars
    case dot
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .glow: return "Album glow"
        case .spectrum: return "Spectrum"
        case .lyric: return "Lyric trace"
        case .arc: return "Progress arc"
        case .cat: return "Jumping cat"
        case .stars: return "Beat stars"
        case .dot: return "Status dot"
        case .custom: return "Custom graphic"
        }
    }

    var summary: String {
        switch self {
        case .off: return "Both corners stay pure black."
        case .glow: return "Soft light in the album's own colour, breathing with the beat."
        case .spectrum: return "Mirrored bars driven by the real audio spectrum."
        case .lyric: return "A faint ghost of the current lyric line."
        case .arc: return "A hairline arc that follows playback progress."
        case .cat: return "A neon line cat that hops on every beat."
        case .stars: return "Faint stars that light up and connect on beats."
        case .dot: return "Almost always black; one faint dot per playback event."
        case .custom: return "Your own image, pulsing with the music."
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "slash.circle"
        case .glow: return "circle.hexagongrid.fill"
        case .spectrum: return "chart.bar.fill"
        case .lyric: return "text.quote"
        case .arc: return "circle.dashed"
        case .cat: return "cat.fill"
        case .stars: return "sparkles"
        case .dot: return "circle.fill"
        case .custom: return "photo"
        }
    }

    /// Styles that do not need the audio tap at all.
    var needsAudio: Bool {
        switch self {
        case .glow, .spectrum, .cat, .stars, .custom, .dot: return true
        case .off, .lyric, .arc: return false
        }
    }
}

enum VisualizerColorSource: String, CaseIterable, Identifiable, Defaults.Serializable {
    case albumArt
    case custom
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albumArt: return "Album art"
        case .custom: return "Custom"
        case .white: return "White"
        }
    }
}

enum VisualizerSide {
    case left
    case right
}

// MARK: - Custom image storage

enum CustomVisualizerStore {
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let folder = base
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Visualizers", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func importImage(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let name = "custom-\(UUID().uuidString.prefix(8)).\(ext)"
        let destination = directory.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        return name
    }

    static func image(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        let url = directory.appendingPathComponent(name)
        return NSImage(contentsOf: url)
    }

    static func remove(named name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

// MARK: - Frame

struct MusicVisualizerFrame {
    var time: Double
    var level: Float
    var bands: [Float]
    var beat: Float
    var progress: Double
    var lyric: String
    var eventPulse: Double
    var isPlaying: Bool
}

// MARK: - Painter

enum MusicVisualizerPainter {
    static func draw(
        style: MusicVisualizerStyle,
        context: inout GraphicsContext,
        size: CGSize,
        frame: MusicVisualizerFrame,
        color: Color,
        sensitivity: Double,
        side: VisualizerSide
    ) {
        guard size.width > 1, size.height > 1 else { return }
        switch style {
        case .off:
            break
        case .glow:
            drawGlow(context: &context, size: size, frame: frame, color: color,
                     sensitivity: sensitivity, side: side)
        case .spectrum:
            drawSpectrum(context: &context, size: size, frame: frame, color: color,
                         sensitivity: sensitivity, side: side)
        case .lyric:
            drawLyric(context: &context, size: size, frame: frame, color: color, side: side)
        case .arc:
            drawArc(context: &context, size: size, frame: frame, color: color, side: side)
        case .cat:
            drawCat(context: &context, size: size, frame: frame, color: color, side: side)
        case .stars:
            drawStars(context: &context, size: size, frame: frame, color: color, side: side)
        case .dot:
            drawDot(context: &context, size: size, frame: frame, color: color)
        case .custom:
            break
        }
    }

    // MARK: Glow

    private static func drawGlow(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, sensitivity: Double, side: VisualizerSide
    ) {
        let level = CGFloat(min(1, frame.level * Float(sensitivity)))
        let beat = CGFloat(frame.beat)
        let base = min(size.width, size.height)
        let radius = base * (0.55 + 0.35 * level + 0.08 * beat)
        let centerX = size.width * (side == .left ? 0.42 : 0.58)
        let center = CGPoint(x: centerX, y: size.height * 0.58)
        let alpha = 0.16 + 0.22 * level + 0.08 * beat

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: base * 0.16))
            let gradient = Gradient(colors: [
                color.opacity(Double(min(alpha, 0.5))),
                color.opacity(Double(min(alpha, 0.5)) * 0.35),
                color.opacity(0),
            ])
            let rect = CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2)
            layer.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    gradient, center: center, startRadius: 0, endRadius: radius))
        }
    }

    // MARK: Spectrum

    private static func drawSpectrum(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, sensitivity: Double, side: VisualizerSide
    ) {
        let barCount = 11
        let gap = size.width * 0.018
        let barWidth = (size.width - gap * CGFloat(barCount + 1)) / CGFloat(barCount)
        let usableBands = max(1, frame.bands.count)

        for index in 0 ..< barCount {
            let fraction = Double(index) / Double(barCount - 1)
            let bandFraction = side == .left ? (1 - fraction) : fraction
            let bandIndex = min(
                usableBands - 1,
                max(0, Int((bandFraction * Double(usableBands - 1)).rounded())))
            let raw = CGFloat(frame.bands[bandIndex]) * CGFloat(sensitivity)
            let beatBoost = CGFloat(frame.beat) * 0.22
            let value = min(1, max(0.04, raw + beatBoost))
            let height = size.height * (0.1 + 0.82 * value)
            let x = gap + CGFloat(index) * (barWidth + gap)
            let rect = CGRect(
                x: x, y: size.height - height, width: barWidth, height: height)
            let radius = min(barWidth / 2, 2.5)
            let path = Path(roundedRect: rect, cornerRadius: radius)
            let gradient = Gradient(colors: [
                color.opacity(0.95),
                color.opacity(0.18),
            ])
            context.fill(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }

    // MARK: Lyric

    private static func drawLyric(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        let line = frame.lyric.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let characters = Array(line)
        let slice = side == .left
            ? String(characters.prefix(9))
            : String(characters.suffix(9))
        guard !slice.isEmpty else { return }

        let text = Text(slice)
            .font(.system(size: max(9, min(size.height * 0.22, 13)), weight: .medium))
            .foregroundColor(color.opacity(0.55))
        let resolved = context.resolve(text)
        let point = CGPoint(
            x: size.width * (side == .left ? 0.34 : 0.66),
            y: size.height * 0.5)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            layer.draw(resolved, at: point, anchor: .center)
        }
    }

    // MARK: Progress arc

    private static func drawArc(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        let radius = min(size.width, size.height) * 0.9
        let center = CGPoint(x: side == .left ? 0 : size.width, y: size.height)
        var path = Path()
        if side == .left {
            path.addArc(
                center: center, radius: radius,
                startAngle: .degrees(-88), endAngle: .degrees(-2), clockwise: false)
        } else {
            path.addArc(
                center: center, radius: radius,
                startAngle: .degrees(182), endAngle: .degrees(268), clockwise: false)
        }
        let progress = max(0, min(1, frame.progress))
        let trimmed = path.trimmedPath(from: 0, to: CGFloat(progress))
        context.stroke(
            trimmed, with: .color(color.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        context.stroke(
            path, with: .color(color.opacity(0.07)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
    }

    // MARK: Cat

    private static func drawCat(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        let beat = CGFloat(frame.beat)
        let scale = min(size.width, size.height) / 60
        let jump = -beat * 6 * scale
        let center = CGPoint(
            x: size.width * (side == .left ? 0.46 : 0.54),
            y: size.height * 0.58 + jump)

        var cat = Path()
        // Body
        cat.addEllipse(in: CGRect(
            x: center.x - 13 * scale, y: center.y - 2 * scale,
            width: 26 * scale, height: 18 * scale))
        // Head
        cat.addEllipse(in: CGRect(
            x: center.x - 10 * scale, y: center.y - 17 * scale,
            width: 20 * scale, height: 16 * scale))
        // Ears
        cat.move(to: CGPoint(x: center.x - 9 * scale, y: center.y - 13 * scale))
        cat.addLine(to: CGPoint(x: center.x - 11 * scale, y: center.y - 23 * scale))
        cat.addLine(to: CGPoint(x: center.x - 3 * scale, y: center.y - 17 * scale))
        cat.closeSubpath()
        cat.move(to: CGPoint(x: center.x + 9 * scale, y: center.y - 13 * scale))
        cat.addLine(to: CGPoint(x: center.x + 11 * scale, y: center.y - 23 * scale))
        cat.addLine(to: CGPoint(x: center.x + 3 * scale, y: center.y - 17 * scale))
        cat.closeSubpath()

        // Tail
        let tailSwing = CGFloat(sin(frame.time * 4)) * 4 * scale
        cat.move(to: CGPoint(x: center.x + 12 * scale, y: center.y + 8 * scale))
        cat.addQuadCurve(
            to: CGPoint(x: center.x + 20 * scale + tailSwing, y: center.y - 2 * scale),
            control: CGPoint(x: center.x + 22 * scale, y: center.y + 10 * scale))

        context.stroke(
            cat, with: .color(color.opacity(0.8)),
            style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round, lineJoin: .round))

        // Eyes (blink roughly every 4 seconds)
        let blink = sin(frame.time * 0.8) > 0.97
        if !blink {
            var eyes = Path()
            eyes.addEllipse(in: CGRect(
                x: center.x - 6 * scale, y: center.y - 11 * scale,
                width: 2.2 * scale, height: 2.2 * scale))
            eyes.addEllipse(in: CGRect(
                x: center.x + 3.8 * scale, y: center.y - 11 * scale,
                width: 2.2 * scale, height: 2.2 * scale))
            context.fill(eyes, with: .color(color.opacity(0.95)))
        }
    }

    // MARK: Stars

    private static func drawStars(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        let count = 16
        var points: [CGPoint] = []
        var twinkle: [Double] = []
        for index in 0 ..< count {
            let seed = Double(index) + (side == .left ? 0 : 31)
            let x = 0.08 + rand(seed * 1.7) * 0.84
            let y = 0.12 + rand(seed * 2.9) * 0.76
            points.append(CGPoint(x: size.width * x, y: size.height * y))
            twinkle.append(0.25 + 0.35 * (0.5 + 0.5 * sin(frame.time * 0.9 + seed)))
        }

        for (index, point) in points.enumerated() {
            let alpha = twinkle[index] + Double(frame.beat) * 0.3
            let radius = 0.9 + Double(frame.beat) * 0.6
            let rect = CGRect(
                x: point.x - radius, y: point.y - radius,
                width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(color.opacity(min(0.85, alpha))))
        }

        if frame.beat > 0.35 {
            var lines = Path()
            for index in 0 ..< points.count - 1 where index % 3 == 0 {
                lines.move(to: points[index])
                lines.addLine(to: points[index + 1])
            }
            context.stroke(
                lines, with: .color(color.opacity(Double(frame.beat) * 0.25)),
                style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }

        // An occasional shooting star, once every ~9 seconds.
        let cycle = frame.time.truncatingRemainder(dividingBy: 9)
        if cycle < 0.9 {
            let progress = cycle / 0.9
            let start = CGPoint(
                x: size.width * (side == .left ? 0.05 : 0.95),
                y: size.height * 0.2)
            let end = CGPoint(
                x: size.width * (side == .left ? 0.95 : 0.05),
                y: size.height * 0.75)
            let head = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress)
            let tail = CGPoint(
                x: head.x - (end.x - start.x) * 0.12,
                y: head.y - (end.y - start.y) * 0.12)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            let fade = sin(progress * .pi)
            context.stroke(
                path, with: .color(color.opacity(0.5 * fade)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
    }

    // MARK: Dot

    private static func drawDot(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color
    ) {
        guard frame.eventPulse > 0.01 else { return }
        let radius = 2.2 + 3.2 * CGFloat(frame.eventPulse)
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.4))
            layer.fill(
                Path(ellipseIn: rect),
                with: .color(color.opacity(Double(frame.eventPulse) * 0.7)))
        }
    }

    static func rand(_ value: Double) -> Double {
        let x = sin(value * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }
}

// MARK: - Slot view

struct MusicVisualizerSlot: View {
    let side: VisualizerSide
    let isVisible: Bool

    @ObservedObject private var music = MusicManager.shared
    // Deliberately not @ObservedObject: the spectrum publishes at up to 30 Hz
    // and would invalidate this body a second time on top of TimelineView.
    // The canvas reads a snapshot each tick instead.
    private let spectrum = AudioSpectrumManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.musicVisualizerEnabled) private var enabled
    @Default(.musicVisualizerStyleLeft) private var leftStyle
    @Default(.musicVisualizerStyleRight) private var rightStyle
    @Default(.musicVisualizerSplit) private var split
    @Default(.musicVisualizerColorSource) private var colorSource
    @Default(.musicVisualizerCustomColor) private var customColorHex
    @Default(.musicVisualizerSensitivity) private var sensitivity
    @Default(.musicVisualizerCustomImage) private var customImageName

    @State private var eventPulse: Double = 0
    @State private var lastEvent = Date.distantPast
    @State private var registered = false
    @State private var lastTrackKey = ""

    private static let emptyBands = [Float](
        repeating: 0, count: AudioSpectrumManager.bandCount)

    private var style: MusicVisualizerStyle {
        guard enabled else { return .off }
        guard split else { return leftStyle }
        return side == .left ? leftStyle : rightStyle
    }

    private var tint: Color {
        switch colorSource {
        case .albumArt:
            return Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.55)
        case .custom:
            return Color(hex: customColorHex) ?? .white
        case .white:
            return .white
        }
    }

    private var animating: Bool {
        isVisible && style != .off && !reduceMotion
    }

    var body: some View {
        content
            .allowsHitTesting(false)
            .onAppear { syncAudio(active: true) }
            .onDisappear { syncAudio(active: false) }
            .onChange(of: isVisible) { syncAudio(active: true) }
            .onChange(of: music.isPlaying) {
                syncAudio(active: true)
                registerEvent()
            }
            .onChange(of: music.songTitle) { registerEvent() }
            .onChange(of: style) { syncAudio(active: true) }
    }

    @ViewBuilder
    private var content: some View {
        if style == .custom, let image = CustomVisualizerStore.image(named: customImageName) {
            customGraphic(image: image)
        } else {
            TimelineView(.animation(
                minimumInterval: interval, paused: !animating
            )) { timeline in
                let frame = makeFrame(at: timeline.date)
                Canvas { context, size in
                    MusicVisualizerPainter.draw(
                        style: style, context: &context, size: size, frame: frame,
                        color: tint, sensitivity: sensitivity, side: side)
                }
            }
        }
    }

    private var interval: Double {
        switch style {
        case .lyric, .arc, .dot: return 1.0 / 8.0
        case .glow: return 1.0 / 20.0
        default: return 1.0 / 30.0
        }
    }

    @ViewBuilder
    private func customGraphic(image: NSImage) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let beat = animating ? Double(spectrum.beat) : 0
            let scale = 0.9 + beat * 0.12
            let glow = 0.25 + Double(spectrum.level) * 0.5 + beat * 0.25
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(tint.opacity(0.35 + glow * 0.55))
                .scaleEffect(scale)
                .shadow(color: tint.opacity(glow * 0.6), radius: 6 + glow * 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(sin(t * 0.5) * 1.5))
        }
    }

    private func makeFrame(at date: Date) -> MusicVisualizerFrame {
        let elapsed = music.estimatedPlaybackPosition(at: date)
        let progress: Double = music.songDuration > 0
            ? min(max(elapsed / music.songDuration, 0), 1)
            : 0
        let lyric: String = {
            if !music.syncedLyrics.isEmpty {
                return music.lyricLine(at: elapsed)
            }
            return music.currentLyrics
        }()
        let pulse: Double = {
            let age = date.timeIntervalSince(lastEvent)
            guard age >= 0, age < 3 else { return 0 }
            return exp(-age / 1.1)
        }()
        return MusicVisualizerFrame(
            time: date.timeIntervalSinceReferenceDate,
            level: animating ? spectrum.level : 0,
            bands: animating ? spectrum.bands : Self.emptyBands,
            beat: animating ? spectrum.beat : 0,
            progress: progress,
            lyric: lyric,
            eventPulse: pulse,
            isPlaying: music.isPlaying
        )
    }

    private func registerEvent() {
        lastEvent = Date()
        eventPulse = 1
    }

    private func syncAudio(active: Bool) {
        let shouldRun = active && isVisible && style.needsAudio && music.isPlaying
        if shouldRun, !registered {
            registered = true
            spectrum.setActive(true)
        } else if !shouldRun, registered {
            registered = false
            spectrum.setActive(false)
        }
    }
}

// MARK: - Hex colour

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        let color = NSColor(self)
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - Settings

struct MusicVisualizerSettings: View {
    @Default(.musicVisualizerEnabled) private var enabled
    @Default(.musicVisualizerStyleLeft) private var leftStyle
    @Default(.musicVisualizerStyleRight) private var rightStyle
    @Default(.musicVisualizerSplit) private var split
    @Default(.musicVisualizerColorSource) private var colorSource
    @Default(.musicVisualizerCustomColor) private var customColorHex
    @Default(.musicVisualizerCustomImage) private var customImageName
    @Default(.musicVisualizerSensitivity) private var sensitivity

    @ObservedObject private var spectrum = AudioSpectrumManager.shared
    @State private var isImporting = false
    @State private var importError: String?

    private var usesCustomGraphic: Bool {
        leftStyle == .custom || (split && rightStyle == .custom)
    }

    private var usesAudio: Bool {
        leftStyle.needsAudio || (split && rightStyle.needsAudio)
    }

    var body: some View {
        Group {
            Toggle("Show visualizer in player corners", isOn: $enabled)

            if enabled {
                Picker("Left corner", selection: $leftStyle) {
                    ForEach(MusicVisualizerStyle.allCases) { style in
                        Label(style.title, systemImage: style.symbolName).tag(style)
                    }
                }

                Toggle("Use a different style on the right", isOn: $split)

                if split {
                    Picker("Right corner", selection: $rightStyle) {
                        ForEach(MusicVisualizerStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbolName).tag(style)
                        }
                    }
                }

                if usesCustomGraphic {
                    customGraphicControls
                }

                Picker("Colour", selection: $colorSource) {
                    ForEach(VisualizerColorSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }

                if colorSource == .custom {
                    ColorPicker(
                        "Custom colour",
                        selection: Binding(
                            get: { Color(hex: customColorHex) ?? .white },
                            set: { customColorHex = $0.hexString }
                        )
                    )
                }

                HStack {
                    Text("Sensitivity")
                    Slider(value: $sensitivity, in: 0.4 ... 2.0)
                    Text(String(format: "%.1f×", sensitivity))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if usesAudio {
                    audioStatusRow
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                do {
                    let name = try CustomVisualizerStore.importImage(from: url)
                    if !customImageName.isEmpty {
                        CustomVisualizerStore.remove(named: customImageName)
                    }
                    customImageName = name
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            case let .failure(error):
                importError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var customGraphicControls: some View {
        HStack {
            if let image = CustomVisualizerStore.image(named: customImageName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .padding(4)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            Button(customImageName.isEmpty ? "Choose image…" : "Replace image…") {
                isImporting = true
            }
            Spacer()
            if !customImageName.isEmpty {
                Button("Remove") {
                    CustomVisualizerStore.remove(named: customImageName)
                    customImageName = ""
                }
            }
        }
        Text("PNG or SVG works best as a single-colour silhouette. The image pulses with the beat and glows in the colour above.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let importError {
            Text(importError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var audioStatusRow: some View {
        HStack {
            Image(systemName: spectrum.isSimulated ? "waveform.slash" : "waveform")
                .foregroundStyle(spectrum.isSimulated ? .orange : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(spectrum.isSimulated ? "Simulated rhythm" : "Live system audio")
                Text(spectrum.isSimulated
                     ? "Allow boringNotch under Privacy & Security → Audio Recording to react to the real music."
                     : "The spectrum follows what is actually playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { spectrum.retry() }
            Button("Privacy Settings") { openAudioPrivacySettings() }
        }
    }

    private func openAudioPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioRecording",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

