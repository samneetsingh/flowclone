import Foundation

class BinaryManager: NSObject, ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?

    private static let binaryName = "whisper-cpp"
    private static let downloadURLString = "https://github.com/samneetsingh/flowclone/releases/download/whisper-cpp-v1/whisper-cpp"

    private var downloadContinuation: CheckedContinuation<Void, Error>?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    static let binaryDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FlowClone", isDirectory: true)
    }()

    static var binaryURL: URL {
        binaryDirectory.appendingPathComponent(binaryName)
    }

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.binaryDirectory, withIntermediateDirectories: true)
    }

    func binaryExists() -> Bool {
        FileManager.default.fileExists(atPath: Self.binaryURL.path)
    }

    func binaryPath() -> URL? {
        binaryExists() ? Self.binaryURL : nil
    }

    func downloadIfNeeded() async throws {
        guard !binaryExists() else { return }
        guard !isDownloading else { return }

        guard let downloadURL = URL(string: Self.downloadURLString) else {
            throw URLError(.badURL)
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            downloadError = nil
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.downloadContinuation = continuation
                let task = session.downloadTask(with: downloadURL)
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

    private func makeExecutable() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: Self.binaryURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", Self.binaryURL.path]
        try? process.run()
        process.waitUntilExit()
    }
}

extension BinaryManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: Self.binaryURL.path) {
                try FileManager.default.removeItem(at: Self.binaryURL)
            }
            try FileManager.default.moveItem(at: location, to: Self.binaryURL)
            try makeExecutable()
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
