import Foundation

enum RecordingState {
    case idle
    case recording
    case processing
}

class AppState: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var micPermissionGranted: Bool = false
    @Published var accessibilityGranted: Bool = false
    @Published var binaryReady: Bool = false
    @Published var modelReady: Bool = false
    @Published var lastError: String?
    @Published var lastRawTranscript: String?
    @Published var lastCleanedText: String?
}
