import SwiftUI

struct ModelOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    var settings: AppSettings

    @State private var selectedModel: WhisperModel = .baseEn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if modelManager.isDownloading {
                downloadingSection
            } else if let error = modelManager.downloadError {
                errorSection(error)
            } else {
                selectionSection
            }
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download Speech Model")
                .font(.subheadline.bold())

            Picker("Model", selection: $selectedModel) {
                ForEach(WhisperModel.allCases) { model in
                    Text("\(model.displayName) (\(model.sizeDescription))")
                        .tag(model)
                }
            }
            .labelsHidden()

            Text(selectedModel.modelDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Download") {
                Task {
                    do {
                        try await modelManager.download(model: selectedModel)
                        settings.whisperModel = selectedModel.rawValue
                        appState.modelReady = true
                    } catch {
                        // Error is already set on modelManager.downloadError
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading \(selectedModel.displayName)...")
                .font(.subheadline.bold())

            ProgressView(value: modelManager.downloadProgress)

            Text("\(Int(modelManager.downloadProgress * 100))%")
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
                Task {
                    do {
                        try await modelManager.download(model: selectedModel)
                        settings.whisperModel = selectedModel.rawValue
                        appState.modelReady = true
                    } catch {
                        // Error is already set on modelManager.downloadError
                    }
                }
            }
            .controlSize(.small)
        }
    }
}
