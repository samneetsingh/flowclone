import AVFoundation

extension Notification.Name {
    static let recordingDidAutoStop = Notification.Name("com.flowclone.recordingDidAutoStop")
}

class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var autoStopTimer: Timer?
    private var converter: AVAudioConverter?
    private var convertedBuffer: AVAudioPCMBuffer?

    private static let targetSampleRate: Double = 16000
    private static let maxDuration: TimeInterval = 30

    private static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
    }

    var elapsedTime: TimeInterval {
        guard let startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    func start() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let file = try AVAudioFile(forWriting: url, settings: Self.fileSettings)

        let inputNode = engine.inputNode
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        )!

        do {
            try installTapDirect(on: inputNode, format: targetFormat, file: file)
        } catch {
            try installTapWithConverter(on: inputNode, targetFormat: targetFormat, file: file)
        }

        try engine.start()

        audioFile = file
        recordingURL = url
        startTime = Date()

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            self?.autoStopTimer = nil
            NotificationCenter.default.post(name: .recordingDidAutoStop, object: nil)
        }

        return url
    }

    func stop() -> URL {
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        audioFile = nil
        converter = nil
        convertedBuffer = nil
        startTime = nil

        return recordingURL!
    }

    private func installTapDirect(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        file: AVAudioFile
    ) throws {
        var tapError: Error?
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                tapError = error
            }
        }
        if let tapError { throw tapError }
    }

    private func installTapWithConverter(
        on inputNode: AVAudioInputNode,
        targetFormat: AVAudioFormat,
        file: AVAudioFile
    ) throws {
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let audioConverter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }
        self.converter = audioConverter

        let convertedFrameCapacity = AVAudioFrameCount(
            (Double(4096) / nativeFormat.sampleRate) * Self.targetSampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: convertedFrameCapacity) else {
            throw AudioRecorderError.bufferCreationFailed
        }
        self.convertedBuffer = outputBuffer

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let outBuf = self.convertedBuffer else { return }
            outBuf.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .haveData {
                try? file.write(from: outBuf)
            }
        }
    }
}

enum AudioRecorderError: Error {
    case converterCreationFailed
    case bufferCreationFailed
}
