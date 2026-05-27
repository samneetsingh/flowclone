import Foundation

struct WhisperRunner {
    enum TranscriptionError: LocalizedError {
        case binaryNotFound
        case processFailure(stderr: String, exitCode: Int32)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "whisper-cpp binary not found. It will be downloaded on next launch."
            case .processFailure(let stderr, let exitCode):
                return "Transcription failed (exit \(exitCode)): \(stderr)"
            case .emptyOutput:
                return "Recording too short — no speech detected."
            }
        }
    }

    func transcribe(audioURL: URL, modelPath: String, binaryPath: String) async throws -> String {
        let binaryURL = URL(fileURLWithPath: binaryPath)
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw TranscriptionError.binaryNotFound
        }

        let result = try await Task.detached {
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = ["-m", modelPath, "-f", audioURL.path, "-l", "en", "-nt", "-np"]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode != 0 {
                let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                throw TranscriptionError.processFailure(stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines), exitCode: exitCode)
            }

            let transcript = String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return transcript
        }.value

        if result.isEmpty {
            throw TranscriptionError.emptyOutput
        }

        return result
    }
}
