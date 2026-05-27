import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case smallEn = "small.en"
    case mediumEn = "medium.en"
    case large = "large-v3-turbo"

    var id: String { rawValue }
    var filename: String { "ggml-\(rawValue).bin" }

    var displayName: String {
        switch self {
        case .tinyEn: return "tiny.en"
        case .baseEn: return "base.en"
        case .smallEn: return "small.en"
        case .mediumEn: return "medium.en"
        case .large: return "large-v3-turbo"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tinyEn: return "~75 MB"
        case .baseEn: return "~142 MB"
        case .smallEn: return "~466 MB"
        case .mediumEn: return "~1.5 GB"
        case .large: return "~1.5 GB"
        }
    }

    var modelDescription: String {
        switch self {
        case .tinyEn: return "Fastest, least accurate. Fine for simple dictation."
        case .baseEn: return "Good balance of speed and accuracy. Recommended."
        case .smallEn: return "Noticeably better accuracy, slightly slower."
        case .mediumEn: return "High accuracy, may lag on older hardware."
        case .large: return "Best accuracy, slow. Only recommended for M-series."
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}

class ModelManager: NSObject, ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?

    private var downloadContinuation: CheckedContinuation<Void, Error>?
    private var currentDownloadModel: WhisperModel?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FlowClone/models", isDirectory: true)
    }()

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
    }

    func downloadedModels() -> [WhisperModel] {
        WhisperModel.allCases.filter { model in
            FileManager.default.fileExists(atPath: Self.modelsDirectory.appendingPathComponent(model.filename).path)
        }
    }

    func modelPath(for model: WhisperModel) -> URL? {
        let path = Self.modelsDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    func download(model: WhisperModel) async throws {
        guard !isDownloading else { return }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            downloadError = nil
        }
        currentDownloadModel = model

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.downloadContinuation = continuation
                let task = session.downloadTask(with: model.downloadURL)
                task.resume()
            }
            await MainActor.run {
                isDownloading = false
                downloadProgress = 1.0
            }
        } catch {
            await MainActor.run {
                isDownloading = false
                downloadError = error.localizedDescription
            }
            throw error
        }
    }

    func deleteModel(_ model: WhisperModel) throws {
        let path = Self.modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = currentDownloadModel else {
            downloadContinuation?.resume(throwing: URLError(.cancelled))
            downloadContinuation = nil
            return
        }

        let destination = Self.modelsDirectory.appendingPathComponent(model.filename)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            downloadContinuation?.resume()
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }
}
