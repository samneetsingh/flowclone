import SwiftUI

struct BinaryOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var binaryManager: BinaryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if binaryManager.isDownloading {
                downloadingSection
            } else if let error = binaryManager.downloadError {
                errorSection(error)
            } else {
                startingSection
            }
        }
        .onAppear {
            startDownload()
        }
    }

    private var startingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setting up whisper engine...")
                .font(.subheadline.bold())

            ProgressView()
                .controlSize(.small)
        }
    }

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading whisper engine...")
                .font(.subheadline.bold())

            ProgressView(value: binaryManager.downloadProgress)

            Text("\(Int(binaryManager.downloadProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download Failed")
                .font(.subheadline.bold())
                .foregroundColor(.red)

            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Button("Retry") {
                startDownload()
            }
            .controlSize(.small)
        }
    }

    private func startDownload() {
        Task {
            do {
                try await binaryManager.downloadIfNeeded()
                await MainActor.run {
                    appState.binaryReady = true
                }
            } catch {
                // Error is already set on binaryManager.downloadError
            }
        }
    }
}
