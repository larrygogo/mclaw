import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

private enum SpeechAudioQueue {
    static let shared = DispatchQueue(label: "clawmo.speech.audio")
}

@MainActor @Observable
final class SpeechManager {
    var isRecording = false
    var transcript = ""
    var permissionDenied = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private nonisolated(unsafe) let audioEngine = AVAudioEngine()
    private var timeoutTask: Task<Void, Never>?
    private var userStopped = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    }

    func start() {
        userStopped = false
        permissionDenied = false
        SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, !self.userStopped else { return }
                if status != .authorized {
                    self.permissionDenied = true
                    return
                }
                self.startRecording()
            }
        }
    }

    func stop() {
        guard isRecording || recognitionTask != nil else { return }
        userStopped = true
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        let engine = audioEngine
        SpeechAudioQueue.shared.async {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func startRecording() {
        transcript = ""
        // Clean up any previous session
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let engine = audioEngine
        SpeechAudioQueue.shared.async { [weak self] in
            // Always remove existing tap first to prevent crash
            engine.inputNode.removeTap(onBus: 0)

            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            do {
                try engine.start()
                Task { @MainActor [weak self] in
                    guard let self, !self.userStopped else { return }
                    self.isRecording = true
                }
            } catch {
                NSLog("[speech] audioEngine.start() failed: %@", "\(error)")
            }
        }

        // Auto-stop after 60 seconds
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, self.isRecording else { return }
            self.stop()
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = error != nil || (result?.isFinal == true)
            Task { @MainActor [weak self] in
                guard let self, !self.userStopped else { return }
                if let text {
                    self.transcript = text
                }
                if isFinal {
                    self.stop()
                }
            }
        }
    }
}
