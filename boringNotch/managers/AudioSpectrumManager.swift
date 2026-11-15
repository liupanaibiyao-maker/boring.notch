//
//  AudioSpectrumManager.swift
//  boringNotch
//
//  Real-time system audio spectrum for the music visualizer slots.
//
//  The only supported way to analyse audio that other apps are playing is a
//  Core Audio process tap (macOS 14.2+). Creating the tap triggers the system
//  "audio recording" permission prompt once; when the user denies it, the tap
//  is created but its IOProc never runs, so we detect the silence after a
//  short grace period and fall back to a clearly labelled simulation.
//

import Accelerate
import Combine
import CoreAudio
import Defaults
import Foundation

// MARK: - Tap errors

enum SystemAudioTapError: LocalizedError {
    case unsupported
    case tapCreation(OSStatus)
    case format(OSStatus)
    case aggregateCreation(OSStatus)
    case ioProc(OSStatus)
    case start(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "System audio taps require macOS 14.2 or newer."
        case let .tapCreation(status):
            return "Could not create the audio tap (OSStatus \(status))."
        case let .format(status):
            return "Could not read the tap format (OSStatus \(status))."
        case let .aggregateCreation(status):
            return "Could not create the aggregate device (OSStatus \(status))."
        case let .ioProc(status):
            return "Could not install the audio callback (OSStatus \(status))."
        case let .start(status):
            return "Could not start the audio device (OSStatus \(status))."
        }
    }
}

// MARK: - Core Audio process tap

@available(macOS 14.2, *)
private final class SystemAudioTap {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var didStart = false

    private(set) var sampleRate: Double = 48_000

    /// Called on an audio thread. Keep the work light: copy the samples and
    /// hand them to the analysis queue.
    var onFrames: (([Float], Double) -> Void)?

    func start() throws {
        stop()

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        // Never mute other apps: if anything goes wrong the user keeps audio.
        description.muteBehavior = .unmuted

        var tap: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            throw SystemAudioTapError.tapCreation(tapStatus)
        }
        tapID = tap

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard formatStatus == noErr, asbd.mSampleRate > 0 else {
            stop()
            throw SystemAudioTapError.format(formatStatus)
        }
        sampleRate = asbd.mSampleRate

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "boringNotch Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var aggregate: AudioObjectID = kAudioObjectUnknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != kAudioObjectUnknown else {
            stop()
            throw SystemAudioTapError.aggregateCreation(aggregateStatus)
        }
        aggregateID = aggregate

        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) {
            [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData))
            guard let buffer = buffers.first,
                  let data = buffer.mData,
                  buffer.mDataByteSize > 0
            else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let samples = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self), count: count)
            self.onFrames?(Array(samples), self.sampleRate)
        }
        guard procStatus == noErr, let procID else {
            stop()
            throw SystemAudioTapError.ioProc(procStatus)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else {
            stop()
            throw SystemAudioTapError.start(startStatus)
        }
        didStart = true
    }

    func stop() {
        if didStart, let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        didStart = false

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }
}

// MARK: - Manager

/// Publishes a normalized, smoothed spectrum for the visualizer slots.
///
/// - `bands`: 24 log-spaced bands, 0...1, low frequencies first.
/// - `level`: overall loudness, 0...1.
/// - `bass`: the first four bands averaged, 0...1.
/// - `beat`: 1 right on a detected beat, decaying towards 0 between beats.
/// - `isSimulated`: true when no real audio is available (permission denied,
///   unsupported OS, or capture failure). The UI must label this honestly.
final class AudioSpectrumManager: ObservableObject {
    static let shared = AudioSpectrumManager()
    static let bandCount = 24

    @Published private(set) var bands: [Float] = Array(repeating: 0, count: bandCount)
    @Published private(set) var level: Float = 0
    @Published private(set) var bass: Float = 0
    @Published private(set) var beat: Float = 0
    @Published private(set) var isSimulated = true
    @Published private(set) var lastErrorDescription: String?
    /// True while the real tap is running (false when simulated or stopped).
    @Published private(set) var isCapturing = false

    /// Effective publish rate of the spectrum, in Hz. Kept out of @Published so
    /// it does not add a second objectWillChange per frame.
    private(set) var publishRateHz: Double = 0

    private var tapStorage: AnyObject?
    private var activeClients = 0
    private var isRunning = false
    private var graceWorkItem: DispatchWorkItem?
    private var simulationTimer: Timer?
    private var lastPublish = Date.distantPast
    private var lastBeat = Date.distantPast
    private var rollingBass: Float = 0
    private var smoothed: [Float] = Array(repeating: 0, count: bandCount)
    private var sampleRate: Double = 48_000
    private var receivedFrames = false

    private let analysisQueue = DispatchQueue(
        label: "boringnotch.spectrum.analysis", qos: .userInitiated)
    private var fftSetup: FFTSetup?
    private let fftSize = 1024
    private var fftLog2: vDSP_Length = 10
    private var analysisBusy = false
    private var bandEdges: [Double] = []
    private var routeListenerBlock: AudioObjectPropertyListenerBlock?
    private var routeRebuildWork: DispatchWorkItem?

    private init() {
        fftLog2 = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(fftLog2, FFTRadix(kFFTRadix2))
        rebuildBandEdges()
    }

    deinit {
        simulationTimer?.invalidate()
        graceWorkItem?.cancel()
        removeRouteListener()
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: Lifecycle

    /// Slots call this on appear/disappear so the tap only lives while the
    /// player is on screen and music is playing.
    func setActive(_ active: Bool) {
        if active {
            activeClients += 1
            if activeClients == 1 { start() }
        } else {
            activeClients = max(0, activeClients - 1)
            if activeClients == 0 { stop() }
        }
    }

    func retry() {
        stop()
        start()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        receivedFrames = false
        lastErrorDescription = nil

        guard #available(macOS 14.2, *) else {
            isSimulated = true
            lastErrorDescription = SystemAudioTapError.unsupported.localizedDescription
            startSimulation()
            return
        }

        let tap = SystemAudioTap()
        tap.onFrames = { [weak self] samples, rate in
            self?.analyse(samples: samples, sampleRate: rate)
        }
        do {
            try tap.start()
            tapStorage = tap
            isSimulated = false
            isCapturing = true
            sampleRate = tap.sampleRate
            rebuildBandEdges()
            installRouteListener()
            scheduleGraceCheck()
        } catch {
            tapStorage = nil
            isSimulated = true
            isCapturing = false
            lastErrorDescription = error.localizedDescription
            startSimulation()
        }
    }

    private func stop() {
        isRunning = false
        isCapturing = false
        removeRouteListener()
        graceWorkItem?.cancel()
        graceWorkItem = nil
        simulationTimer?.invalidate()
        simulationTimer = nil
        if #available(macOS 14.2, *), let tap = tapStorage as? SystemAudioTap {
            tap.stop()
        }
        tapStorage = nil
        resetOutput()
        publishRateHz = 0
    }

    // MARK: Output device changes

    /// Switching to AirPods, a display or another output changes the tap's
    /// format; the existing IOProc then goes silent. Rebuild the tap when the
    /// default output device changes.
    private func installRouteListener() {
        guard routeListenerBlock == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            // Give the new device a moment to finish configuring before
            // rebuilding the aggregate tap on top of it.
            self.routeRebuildWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRunning else { return }
                self.retry()
            }
            self.routeRebuildWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        if status == noErr {
            routeListenerBlock = block
        }
    }

    private func removeRouteListener() {
        guard let block = routeListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        routeListenerBlock = nil
        routeRebuildWork?.cancel()
        routeRebuildWork = nil
    }

    /// A denied tap still reports "created" but never delivers a buffer, so
    /// wait a beat and switch to the labelled simulation instead.
    private func scheduleGraceCheck() {
        graceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, !self.receivedFrames else { return }
            self.isSimulated = true
            self.isCapturing = false
            self.lastErrorDescription =
                "No audio frames received. Allow boringNotch in System Settings → "
                + "Privacy & Security → Audio Recording, then retry."
            self.startSimulation()
        }
        graceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    private func resetOutput() {
        smoothed = Array(repeating: 0, count: Self.bandCount)
        bands = smoothed
        level = 0
        bass = 0
        beat = 0
        rollingBass = 0
    }

    // MARK: Analysis

    private func analyse(samples: [Float], sampleRate rate: Double) {
        guard samples.count >= 256 else { return }
        if rate != sampleRate {
            sampleRate = rate
            rebuildBandEdges()
        }
        analysisQueue.async { [weak self] in
            guard let self, !self.analysisBusy else { return }
            self.analysisBusy = true
            defer { self.analysisBusy = false }
            guard let result = self.computeSpectrum(samples: samples) else { return }
            DispatchQueue.main.async {
                self.receivedFrames = true
                if self.isSimulated {
                    self.isSimulated = false
                    self.isCapturing = true
                    self.simulationTimer?.invalidate()
                    self.simulationTimer = nil
                }
                self.publish(result)
            }
        }
    }

    private struct SpectrumResult {
        let bands: [Float]
        let level: Float
    }

    private func computeSpectrum(samples: [Float]) -> SpectrumResult? {
        guard let setup = fftSetup else { return nil }
        let n = fftSize
        let half = n / 2

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var frame = [Float](repeating: 0, count: n)
        let usable = min(samples.count, n)
        frame.replaceSubrange(0 ..< usable, with: samples[0 ..< usable])

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(n))

        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(
                    realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samplesPointer in
                    samplesPointer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: half
                    ) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, fftLog2, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let scale = 2 / Float(n)
        var bandValues = [Float](repeating: 0, count: Self.bandCount)
        let binWidth = sampleRate / Double(n)
        for index in 0 ..< Self.bandCount {
            let low = bandEdges[index]
            let high = bandEdges[index + 1]
            let firstBin = max(1, min(half - 1, Int(low / binWidth)))
            let lastBin = max(firstBin, min(half - 1, Int(high / binWidth)))
            var peak: Float = 0
            for bin in firstBin ... lastBin {
                peak = max(peak, magnitudes[bin])
            }
            let amplitude = peak * scale
            let decibels = 20 * log10(max(amplitude, 1e-7))
            let normalized = (decibels + 58) / 58
            bandValues[index] = min(max(normalized, 0), 1)
        }
        return SpectrumResult(bands: bandValues, level: min(max(rms * 6, 0), 1))
    }

    private func rebuildBandEdges() {
        let low: Double = 40
        let high = min(16_000, sampleRate / 2 - 1)
        bandEdges = (0 ... Self.bandCount).map { index in
            let fraction = Double(index) / Double(Self.bandCount)
            return low * pow(high / low, fraction)
        }
    }

    // MARK: Publishing

    private func publish(_ result: SpectrumResult) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublish)
        guard elapsed >= 1.0 / 30.0 else { return }
        lastPublish = now
        let instantRate = 1.0 / max(elapsed, 0.0001)
        publishRateHz =
            publishRateHz == 0 ? instantRate : publishRateHz * 0.9 + instantRate * 0.1

        for index in 0 ..< Self.bandCount {
            let target = result.bands[index]
            let current = smoothed[index]
            let factor: Float = target > current ? 0.6 : 0.22
            smoothed[index] = current + (target - current) * factor
        }
        bands = smoothed
        level = level + (result.level - level) * 0.35

        let bassTarget = (smoothed[0] + smoothed[1] + smoothed[2] + smoothed[3]) / 4
        bass = bassTarget
        rollingBass = rollingBass * 0.94 + bassTarget * 0.06

        if bassTarget > max(0.16, rollingBass * 1.35),
           now.timeIntervalSince(lastBeat) > 0.18 {
            beat = 1
            lastBeat = now
        } else {
            beat = max(0, beat - 0.09)
        }
    }

    // MARK: Simulation fallback

    private func startSimulation() {
        guard simulationTimer == nil else { return }
        resetOutput()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tickSimulation()
        }
        RunLoop.main.add(timer, forMode: .common)
        simulationTimer = timer
    }

    private func tickSimulation() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublish)
        guard elapsed >= 1.0 / 20.0 else { return }
        lastPublish = now

        let t = now.timeIntervalSinceReferenceDate
        var values = [Float](repeating: 0, count: Self.bandCount)
        for index in 0 ..< Self.bandCount {
            let seed = Double(index) * 1.7
            let slow = 0.5 + 0.5 * sin(t * (0.7 + seed * 0.11) + seed)
            let fast = 0.5 + 0.5 * sin(t * (3.1 + seed * 0.53) + seed * 2.3)
            values[index] = Float(min(1, 0.08 + slow * 0.35 + fast * 0.22))
        }
        bands = values
        level = values.reduce(0, +) / Float(values.count)
        bass = (values[0] + values[1] + values[2] + values[3]) / 4

        let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(
            dividingBy: 60.0 / 96.0)
        let pulse = Float(pow(1 - phase / (60.0 / 96.0), 4))
        beat = max(beat * 0.86, pulse)
    }
}

