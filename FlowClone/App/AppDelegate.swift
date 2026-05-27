import AppKit
import SwiftUI
import AVFoundation
import Combine

extension Notification.Name {
    static let openSettings = Notification.Name("com.flowclone.openSettings")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()
    private let settings = AppSettings.load()
    private var hotkeyManager: HotkeyManager?
    private let audioRecorder = AudioRecorder()
    private let binaryManager = BinaryManager()
    private let modelManager = ModelManager()
    private let whisperRunner = WhisperRunner()
    private let llmClient = LLMClient()
    private var currentRecordingURL: URL?
    private var capturedAppName: String = "Unknown"
    private var accessibilityTimer: Timer?
    private var settingsWindow: NSWindow?
    private var settingsObserver: AnyCancellable?
    private var notificationObserver: Any?
    private var autoStopObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appState.binaryReady = binaryManager.binaryExists()
        appState.modelReady = !modelManager.downloadedModels().isEmpty

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(settings: settings)
                .environmentObject(appState)
                .environmentObject(binaryManager)
                .environmentObject(modelManager)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "FlowClone")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettingsWindow()
        }

        settingsObserver = settings.$hotkey.dropFirst().sink { [weak self] newHotkey in
            self?.restartHotkeyListener()
        }

        autoStopObserver = NotificationCenter.default.addObserver(
            forName: .recordingDidAutoStop, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopRecordingAndProcess()
        }

        checkPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func checkPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            appState.micPermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.appState.micPermissionGranted = granted
                }
            }
        default:
            appState.micPermissionGranted = false
        }
    }

    private func checkAccessibilityPermission() {
        let granted = AXIsProcessTrusted()
        appState.accessibilityGranted = granted
        if granted {
            startHotkeyListener()
        } else {
            startAccessibilityPolling()
        }
    }

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted() {
                self.appState.accessibilityGranted = true
                timer.invalidate()
                self.accessibilityTimer = nil
                self.startHotkeyListener()
            }
        }
    }

    private func startHotkeyListener() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.startListening(for: settings.hotkey, onPress: { [weak self] in
            self?.startRecording()
        }, onRelease: { [weak self] in
            self?.stopRecordingAndProcess()
        })
    }

    private func restartHotkeyListener() {
        hotkeyManager?.stopListening()
        guard AXIsProcessTrusted() else {
            appState.accessibilityGranted = false
            startAccessibilityPolling()
            return
        }
        hotkeyManager?.startListening(for: settings.hotkey, onPress: { [weak self] in
            self?.startRecording()
        }, onRelease: { [weak self] in
            self?.stopRecordingAndProcess()
        })
    }

    private func startRecording() {
        guard appState.state == .idle, appState.binaryReady, appState.modelReady else { return }
        capturedAppName = AppContextDetector.frontmostAppName()
        do {
            currentRecordingURL = try audioRecorder.start()
            appState.state = .recording
            print("Recording started: \(currentRecordingURL!.lastPathComponent)")
        } catch {
            appState.lastError = "Failed to start recording: \(error.localizedDescription)"
            print("Recording failed: \(error)")
        }
    }

    private func stopRecordingAndProcess() {
        guard appState.state == .recording else { return }
        let url = audioRecorder.stop()
        appState.state = .processing
        currentRecordingURL = url
        print("Recording stopped: \(url.lastPathComponent) (duration: \(String(format: "%.1f", audioRecorder.elapsedTime))s)")
        transcribe(audioURL: url)
    }

    private func transcribe(audioURL: URL) {
        guard let model = WhisperModel(rawValue: settings.whisperModel),
              let modelPath = modelManager.modelPath(for: model) else {
            appState.lastError = "No whisper model available"
            appState.state = .idle
            return
        }

        guard let binaryPath = binaryManager.binaryPath() else {
            appState.lastError = "whisper-cpp binary not available"
            appState.state = .idle
            return
        }

        let appName = capturedAppName

        Task {
            do {
                let transcript = try await whisperRunner.transcribe(audioURL: audioURL, modelPath: modelPath.path, binaryPath: binaryPath.path)
                await MainActor.run {
                    appState.lastRawTranscript = transcript
                    print("Transcript: \(transcript)")
                }

                let cleaned = await cleanupWithLLM(transcript: transcript, appName: appName)
                await MainActor.run {
                    appState.lastCleanedText = cleaned
                    appState.state = .idle
                    print("Cleaned: \(cleaned)")
                }
            } catch {
                await MainActor.run {
                    appState.lastError = error.localizedDescription
                    appState.state = .idle
                }
            }
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    private func cleanupWithLLM(transcript: String, appName: String) async -> String {
        guard let apiKey = try? KeychainHelper.read(), apiKey != nil else {
            print("LLM skipped: no API key configured")
            return transcript
        }

        do {
            let cleaned = try await llmClient.cleanup(
                transcript: transcript,
                appName: appName,
                persona: settings.activePersona,
                baseURL: settings.llmBaseURL,
                model: settings.llmModel,
                apiKey: apiKey!
            )
            return cleaned
        } catch {
            print("LLM cleanup failed: \(error.localizedDescription)")
            await MainActor.run {
                appState.lastError = "LLM cleanup failed: \(error.localizedDescription)"
            }
            return transcript
        }
    }

    private func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        popover.performClose(nil)

        let settingsView = SettingsView(settings: settings)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "FlowClone Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }
}
