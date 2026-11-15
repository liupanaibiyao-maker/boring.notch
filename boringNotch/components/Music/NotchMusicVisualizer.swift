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
    case dog
    case slime
    case drop
    case coffee
    case engine
    case mochi
    case newton
    case stars
    case dot
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .glow: return "Album glow"
        case .spectrum: return "Spectrum"
        case .lyric: return "Lyric trace"
        case .arc: return "Progress arc"
        case .cat: return "Jumping cat"
        case .dog: return "Running dog"
        case .slime: return "Slime"
        case .drop: return "Drop"
        case .coffee: return "Coffee"
        case .engine: return "Engine"
        case .mochi: return "Mochi"
        case .newton: return "Newton's cradle"
        case .stars: return "Beat stars"
        case .dot: return "Status dot"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .off: return "Both corners stay pure black."
        case .glow: return "Soft light in the album's own colour, breathing with the beat."
        case .spectrum: return "Mirrored bars driven by the real audio spectrum."
        case .lyric: return "A faint ghost of the current lyric line."
        case .arc: return "A hairline arc that follows playback progress."
        case .cat: return "A neon line cat that hops on every beat."
        case .dog: return "A small dog jogging along."
        case .slime: return "A squishing slime blob."
        case .drop: return "A bouncing droplet."
        case .coffee: return "Steam rising from a coffee cup."
        case .engine: return "A tiny engine firing on the beat."
        case .mochi: return "A mochi squashing to the rhythm."
        case .newton: return "A Newton's cradle swinging."
        case .stars: return "Faint stars that light up and connect on beats."
        case .dot: return "Almost always black; one faint dot per playback event."
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
        case .dog: return "dog.fill"
        case .slime: return "drop.fill"
        case .drop: return "drop"
        case .coffee: return "cup.and.saucer.fill"
        case .engine: return "flame.fill"
        case .mochi: return "circle.grid.2x2.fill"
        case .newton: return "circle.hexagongrid.fill"
        case .stars: return "sparkles"
        case .dot: return "circle.fill"
        }
    }

    /// Styles that do not need the audio tap at all.
    var needsAudio: Bool {
        switch self {
        case .glow, .spectrum, .cat, .dog, .slime, .drop, .coffee,
             .engine, .mochi, .newton, .stars, .dot: return true
        case .off, .lyric, .arc: return false
        }
    }

    /// Runner styles rendered from RunCat Neo sprite sheets (Apache-2.0).
    var isRunner: Bool {
        switch self {
        case .cat, .dog, .slime, .drop, .coffee, .engine, .mochi, .newton:
            return true
        default:
            return false
        }
    }

    /// Asset prefix of the sprite sheet frames.
    var runnerAssetPrefix: String {
        switch self {
        case .cat: return "cat"
        case .dog: return "dog"
        case .slime: return "slime"
        case .drop: return "drop"
        case .coffee: return "coffee"
        case .engine: return "engine"
        case .mochi: return "mochi"
        case .newton: return "newton-cradle"
        default: return ""
        }
    }
}

enum VisualizerColorSource: String, CaseIterable, Identifiable, Defaults.Serializable {
    case albumArt
    case custom
    case white

    var id: String { rawValue }

    var title: LocalizedStringKey {
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


// MARK: - Runner frame cache (ported from RunCat Neo, Apache-2.0)

/// Frame ordering copied from RunCat Neo's `FrameOrder`. Each runner has a
/// distinct motion: most run forwards, mochi swings back and forth, Newton's
/// cradle pendulums, and slime pauses at its squashed extreme.
enum RunnerFrameOrder {
    case ascending(Int)
    case swing
    case pendulum
    case partyHorn

    var order: [Int] {
        switch self {
        case let .ascending(n): return Array(0 ..< n)
        case .swing: return [0, 1, 2, 3, 4, 3, 2, 1]
        case .pendulum: return [0, 1, 2, 1, 0, 3, 4, 3]
        case .partyHorn: return [0, 1, 2, 3, 4, 4, 3, 2, 1]
        }
    }

    func frame(at index: Int) -> Int {
        let order = order
        guard !order.isEmpty else { return 0 }
        return order[index % order.count]
    }
}

/// Loads the runner sprite frames and caches per-(color, frame) tinted
/// copies so the Canvas blits a pre-rendered image instead of re-tinting
/// every frame.
enum RunnerFrameCache {
    private static var frameImages: [MusicVisualizerStyle: [NSImage]] = [:]
    private static var tinted: [String: NSImage] = [:]

    static func frames(for style: MusicVisualizerStyle) -> [NSImage] {
        if let cachedFrames = frameImages[style] {
            return cachedFrames
        }
        let prefix = style.runnerAssetPrefix
        guard !prefix.isEmpty else { return [] }
        var names: [String] = []
        var index = 0
        while NSImage(named: "\(prefix)-frame-\(index)") != nil {
            names.append("\(prefix)-frame-\(index)")
            index += 1
            if index > 64 { break }
        }
        let loadedFrames = names.compactMap { NSImage(named: $0) }
        frameImages[style] = loadedFrames
        return loadedFrames
    }

    /// The frame order that gives each runner its characteristic motion.
    static func order(for style: MusicVisualizerStyle) -> RunnerFrameOrder {
        let count = frames(for: style).count
        switch style {
        case .mochi: return .swing
        case .newton: return .pendulum
        case .slime: return .partyHorn
        default: return .ascending(count)
        }
    }

    /// Pre-tinted copy of `image` in `color` (the source is a black template).
    static func tinted(_ image: NSImage, with color: Color) -> NSImage {
        // Frame images and colour must both be part of the key: every sprite
        // in a sheet shares the same dimensions, so a size-only key collapsed
        // all frames into the first one and froze the animation.
        let key = color.hexString + "-" + String(UInt(bitPattern: unsafeBitCast(ObjectIdentifier(image), to: Int.self)))
        if let cached = tinted[key] {
            return cached
        }
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor(color).set()
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        if tinted.count > 192 { tinted.removeAll() }
        tinted[key] = out
        return out
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
        case .dog:
            drawDog(context: &context, size: size, frame: frame, color: color, side: side)
        case .slime:
            drawSlime(context: &context, size: size, frame: frame, color: color, side: side)
        case .drop:
            drawDrop(context: &context, size: size, frame: frame, color: color, side: side)
        case .coffee:
            drawCoffee(context: &context, size: size, frame: frame, color: color, side: side)
        case .engine:
            drawEngine(context: &context, size: size, frame: frame, color: color, side: side)
        case .mochi:
            drawMochi(context: &context, size: size, frame: frame, color: color, side: side)
        case .newton:
            drawNewton(context: &context, size: size, frame: frame, color: color, side: side)
        case .stars:
            drawStars(context: &context, size: size, frame: frame, color: color, side: side)
        case .dot:
            drawDot(context: &context, size: size, frame: frame, color: color)
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
        let chars = Array(line)
        // Left slot shows the first characters, right slot the rest.
        let sliceChars = side == .left ? chars.prefix(6) : chars.suffix(6)
        let shown = Array(sliceChars)
        guard !shown.isEmpty else { return }

        let baseFont = max(12, min(size.height * 0.26, 17))

        // A gentle "bloom" wave rolls through the characters; each char grows
        // and glows like a petal opening as the wave passes.
        let wavePhase = frame.time.truncatingRemainder(dividingBy: 2.4) / 2.4
        // Pre-measure every character so the row can be centered inside the
        // slot instead of starting from an edge and overflowing it.
        let charWidths: [CGFloat] = shown.map { character in
            let text = Text(String(character))
                .font(.system(size: baseFont * 1.45, weight: .semibold, design: .rounded))
            return context.resolve(text)
                .measure(in: CGSize(width: size.width, height: size.height)).width
        }
        let spacing: CGFloat = baseFont * 0.18
        let totalWidth = charWidths.reduce(0, +) + spacing * CGFloat(max(0, shown.count - 1))
        let startX = side == .left
            ? min(size.width * 0.06, max(0, (size.width - totalWidth) / 2))
            : max(size.width * 0.94 - totalWidth, size.width * 0.06)
        for (index, character) in shown.enumerated() {
            let progress = Double(index) / Double(max(1, shown.count - 1))
            let distance = abs(progress - wavePhase)
            let falloff = min(distance, 1 - distance)
            let bloom = max(0, 1 - falloff * 3.2)
            let beatBoost = bloom * Double(frame.beat)
            let scale = 1 + 0.45 * bloom + 0.5 * beatBoost
            let alpha = min(1, 0.45 + 0.5 * bloom + 0.3 * Double(frame.beat))

            let text = Text(String(character))
                .font(.system(size: baseFont * scale, weight: .semibold, design: .rounded))
                .foregroundColor(color.opacity(min(1, alpha)))
            let resolved = context.resolve(text)
            let x = startX + charWidths.prefix(index).reduce(0, +) + CGFloat(index) * spacing
            let y = size.height * 0.5

            if bloom > 0.15 {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3 + 4 * bloom))
                    layer.draw(resolved, at: CGPoint(x: x, y: y), anchor: .leading)
                }
            }
            context.draw(resolved, at: CGPoint(x: x, y: y), anchor: .leading)
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

        // Track
        context.stroke(
            path, with: .color(color.opacity(0.08)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round))

        // Progress fill, with a soft breathing glow synced to the beat.
        let pulse = 0.5 + 0.5 * sin(frame.time * 2.2)
        let glowWidth = 2.2 + CGFloat(frame.beat) * 2.2 + pulse * 0.5
        let trimmed = path.trimmedPath(from: 0, to: CGFloat(progress))
        if progress > 0.002 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3.5 + CGFloat(frame.beat) * 3))
                layer.stroke(
                    trimmed, with: .color(color.opacity(0.55)),
                    style: StrokeStyle(lineWidth: glowWidth + 2, lineCap: .round))
            }
            context.stroke(
                trimmed, with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: glowWidth, lineCap: .round))

            // Trailing dot: sits at the progress tip and pulses.
            let tip = trimmed.currentPoint ?? center
            let dotRadius = 2.6 + CGFloat(frame.beat) * 1.6 + pulse * 0.7
            let dotRect = CGRect(
                x: tip.x - dotRadius, y: tip.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                          with: .color(color.opacity(0.4)))
            }
            context.fill(Path(ellipseIn: dotRect), with: .color(color.opacity(0.95)))
        }

        // A comet that continually travels along the full arc so the effect
        // is visibly in motion even while the song's progress barely moves.
        let cometPeriod = 5.0
        let cometPhase = frame.time.truncatingRemainder(dividingBy: cometPeriod) / cometPeriod
        let cometEnd = 0.06
        let cometTrim = path.trimmedPath(from: max(0, cometPhase - cometEnd), to: cometPhase)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5))
            layer.stroke(
                cometTrim, with: .color(color.opacity(0.5)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        let cometHead = cometTrim.currentPoint ?? center
        let cometRadius = 1.6 + pulse * 0.6
        context.fill(
            Path(ellipseIn: CGRect(
                x: cometHead.x - cometRadius, y: cometHead.y - cometRadius,
                width: cometRadius * 2, height: cometRadius * 2)),
            with: .color(color.opacity(0.75)))
    }

    // MARK: Cat

    // MARK: Runners (RunCat Neo frame sequences)

    static func runnerSequenceIndex(
        style: MusicVisualizerStyle, side: VisualizerSide,
        time: Double, fps: Double, order: RunnerFrameOrder
    ) -> Int {
        // Drive the loop from the system's monotonic clock rather than the
        // timeline's `date`: Canvas may redraw with an unchanged date (layout
        // invalidations), which would freeze the sprite. CACurrentMediaTime
        // always advances, so the run cycle keeps stepping.
        let phase = CACurrentMediaTime() * fps
        let count = Double(order.order.count)
        return order.frame(at: Int(phase.truncatingRemainder(dividingBy: count)))
    }

    private static func drawRunner(
        style: MusicVisualizerStyle,
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        let frames = RunnerFrameCache.frames(for: style)
        guard let first = frames.first, frames.count > 0 else { return }
        let order = RunnerFrameCache.order(for: style)

        let running = frame.isPlaying
        // The reference loop completes in ~0.6s, which is a 5-frame sprite
        // stepping at ~8 fps. Pick the rate from the cycle length so every
        // runner (5 or 10 frames) keeps the same on-screen tempo, and let
        // the beat swell the tempo by up to ~1.8x without ever rewinding.
        let cycleSeconds = running ? 0.6 : 1.2
        let tempo = running ? (1.0 + Double(frame.beat) * 0.8) : 1.0
        let fps = Double(order.order.count) / (cycleSeconds / tempo)
        let frameNumber = runnerSequenceIndex(style: style, side: side, time: frame.time, fps: fps, order: order)
        guard frameNumber < frames.count else { return }
        let frameImage = frames[frameNumber]
        let imageSize = first.size
        guard imageSize.width > 1, imageSize.height > 1 else { return }

        // Fit the runner into the slot.
        let maxHeight = size.height * 0.6
        let maxWidth = size.width * 0.62
        let fit = min(maxHeight / imageSize.height, maxWidth / imageSize.width, 1.6)
        let w = imageSize.width * fit
        let h = imageSize.height * fit

        // The runner stays centred in the slot, exactly like RunCat Neo:
        // the sprite's own pose changes carry the motion, no extra bob.
        let x = (size.width - w) / 2
        let y = size.height * 0.44 - h / 2
        let rect = CGRect(x: x, y: y, width: w, height: h)

        // Ground shadow
        let shadowWidth = w * 0.85
        let shadow = CGRect(
            x: x + (w - shadowWidth) / 2,
            y: size.height * 0.44 + h * 0.5,
            width: shadowWidth, height: h * 0.09)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.5))
            layer.fill(Path(ellipseIn: shadow), with: .color(color.opacity(0.15)))
        }

        // Tinted silhouette: draw the black template, then paint it with the
        // tint colour on top (sourceAtop keeps the silhouette shape).
        let tinted = RunnerFrameCache.tinted(frameImage, with: color)
        let resolved = context.resolve(Image(nsImage: tinted))
        context.draw(resolved, in: rect)

        // Beat glow behind the runner
        if frame.beat > 0.15 {
            let beat = CGFloat(frame.beat)
            let glowRadius = w * (0.7 + beat * 0.4)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: glowRadius * 0.5))
                layer.fill(
                    Path(ellipseIn: rect.insetBy(dx: -glowRadius * 0.2, dy: -glowRadius * 0.2)),
                    with: .color(color.opacity(beat * 0.25)))
            }
        }
    }

    private static func drawCat(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .cat, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawDog(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .dog, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawSlime(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .slime, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawDrop(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .drop, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawCoffee(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .coffee, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawEngine(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .engine, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawMochi(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .mochi, context: &context, size: size, frame: frame, color: color, side: side)
    }

    private static func drawNewton(
        context: inout GraphicsContext, size: CGSize, frame: MusicVisualizerFrame,
        color: Color, side: VisualizerSide
    ) {
        drawRunner(style: .newton, context: &context, size: size, frame: frame, color: color, side: side)
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
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
        // A steady, always-visible status dot that breathes with the beat.
        let breathing = frame.isPlaying ? (0.5 + 0.5 * sin(frame.time * 1.8)) : 0
        let baseRadius = 5.0 + CGFloat(breathing) * 2.0 + CGFloat(frame.beat) * 2.5

        // A permanent outer ring so the status point is clearly visible at a
        // glance, with a soft breathing glow around it.
        let ringRadius = baseRadius + 5
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2))
            layer.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - ringRadius, y: center.y - ringRadius,
                    width: ringRadius * 2, height: ringRadius * 2)),
                with: .color(color.opacity(0.35 + Double(breathing) * 0.25)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // Expanding pulse rings while an event pulse is active.
        if frame.eventPulse > 0.01 {
            let ringProgress = 1 - frame.eventPulse // grows from 0 to 1
            let pulseRingRadius = baseRadius + 12 * CGFloat(ringProgress)
            let ringAlpha = frame.eventPulse * 0.5
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - pulseRingRadius, y: center.y - pulseRingRadius,
                    width: pulseRingRadius * 2, height: pulseRingRadius * 2)),
                with: .color(color.opacity(ringAlpha)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            let glowRadius = baseRadius + 2.5 * CGFloat(frame.eventPulse)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - glowRadius, y: center.y - glowRadius,
                        width: glowRadius * 2, height: glowRadius * 2)),
                    with: .color(color.opacity(0.35 * frame.eventPulse)))
            }
        }

        // Soft halo
        let halo = baseRadius * 2.0
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - halo, y: center.y - halo,
                    width: halo * 2, height: halo * 2)),
                with: .color(color.opacity(0.3 + Double(breathing) * 0.2)))
        }

        // Core
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - baseRadius, y: center.y - baseRadius,
                width: baseRadius * 2, height: baseRadius * 2)),
            with: .color(color.opacity(frame.isPlaying ? 0.95 : 0.55)))
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

    @State private var eventPulse: Double = 0
    @State private var lastEvent = Date.distantPast
    @State private var registered = false
    @State private var lastTrackKey = ""
    @State private var notes: [NoteBurst] = []

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
            .contentShape(Rectangle())
            .onTapGesture {
                guard style != .off, isVisible else { return }
                spawnNotes()
            }
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
        ZStack {
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

            ForEach(notes) { note in
                GeometryReader { geo in
                    NoteView(color: tint, rotation: note.rotation, symbol: note.symbol)
                        .position(x: note.origin.x * geo.size.width,
                                  y: note.origin.y * geo.size.height)
                }
                    .offset(y: note.animate ? -note.rise : 0)
                    .opacity(note.animate ? 0 : 0.9)
                    .scaleEffect(note.animate ? 1.25 : 0.7)
                    .animation(.easeOut(duration: 1.1), value: note.animate)
                    .allowsHitTesting(false)
            }
        }
    }

    private var interval: Double {
        switch style {
        case .lyric, .arc, .dot, .glow: return 1.0 / 20.0
        default: return 1.0 / 30.0
        }
    }

    // MARK: - Click note burst

    private struct NoteBurst: Identifiable {
        let id = UUID()
        var origin: CGPoint = .zero
        var rotation: Double = 0
        var rise: CGFloat = 0
        var symbol: String = "music.note"
        var animate = false
    }

    private func spawnNotes() {
        let symbols = ["music.note", "music.quarternote.3", "music.note.list", "sparkle"]
        let count = Int.random(in: 3...5)
        var spawned: [NoteBurst] = []
        for _ in 0..<count {
            var burst = NoteBurst()
            burst.origin = CGPoint(
                x: .random(in: 0.25...0.75),
                y: .random(in: 0.55...0.85))
            burst.rotation = .random(in: -35...35)
            burst.rise = .random(in: 26...54)
            burst.symbol = symbols.randomElement() ?? "music.note"
            spawned.append(burst)
        }
        notes.append(contentsOf: spawned)
        let ids = Set(spawned.map { $0.id })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            notes = notes.map { n in
                var copy = n
                if ids.contains(n.id) { copy.animate = true }
                return copy
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            notes.removeAll { ids.contains($0.id) }
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
    @Default(.musicVisualizerSensitivity) private var sensitivity

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
    }

    @ViewBuilder
    private var audioStatusRow: some View {
        VisualizerAudioStatusRow()
    }
}

/// Observes the live spectrum only inside this small row, so an open settings
/// window does not invalidate the whole form at the spectrum's publish rate.
private struct VisualizerAudioStatusRow: View {
    @ObservedObject private var spectrum = AudioSpectrumManager.shared

    var body: some View {
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

// MARK: - Note burst view

struct NoteView: View {
    let color: Color
    let rotation: Double
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.7), radius: 3)
            .rotationEffect(.degrees(rotation))
            .allowsHitTesting(false)
    }
}
