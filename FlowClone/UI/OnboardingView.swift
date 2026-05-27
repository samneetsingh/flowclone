import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.micPermissionGranted {
                microphoneSection
            }
            if !appState.accessibilityGranted {
                accessibilitySection
            }
        }
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Microphone")
                    .font(.subheadline.bold())
            }
            Text("Required for voice recording.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Grant Access") {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        appState.micPermissionGranted = granted
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Accessibility")
                    .font(.subheadline.bold())
            }
            Text("Required for global hotkey and text injection.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Open System Settings") {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            }
            .controlSize(.small)
        }
    }
}
