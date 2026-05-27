import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var binaryManager: BinaryManager
    var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FlowClone")
                .font(.headline)

            if !appState.micPermissionGranted || !appState.accessibilityGranted {
                OnboardingView()
            } else if !appState.binaryReady {
                BinaryOnboardingView(binaryManager: binaryManager)
            } else if !appState.modelReady {
                ModelOnboardingView(modelManager: modelManager, settings: settings)
            } else {
                statusSection
            }

            Divider()

            HStack {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateLabel)
                    .font(.subheadline)
            }
            PermissionRow(label: "Microphone", granted: appState.micPermissionGranted)
            PermissionRow(label: "Accessibility", granted: appState.accessibilityGranted)
        }
    }

    private var stateColor: Color {
        switch appState.state {
        case .idle: return .green
        case .recording: return .red
        case .processing: return .orange
        }
    }

    private var stateLabel: String {
        switch appState.state {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .processing: return "Processing..."
        }
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(label)
                .font(.subheadline)
        }
    }
}
