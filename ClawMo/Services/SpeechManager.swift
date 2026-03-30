import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechManager {
    @MainActor var isRecording = false
    @MainActor var transcript = ""
    @MainActor var permissionDenied = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var timeoutTask: Task<Void, Never>?
    private var userStopped = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    }

    @MainActor
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

    @MainActor
    func stop() {
        userStopped = true
        timeoutTask?.cancel()
        timeoutTask = nil
        isRecording = false
        // Audio cleanup on background to avoid blocking main thread
        let engine = audioEngine
        let request = recognitionRequest
        let task = recognitionTask
        recognitionRequest = nil
        recognitionTask = nil
        Task.detached {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            task?.cancel()
        }
    }

    @MainActor
    private func startRecording() {
        transcript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        // Start audio engine on background thread to avoid blocking UI
        let engine = audioEngine
        engine.prepare()
        Task.detached { [weak self] in
            try? engine.start()
            await MainActor.run { [weak self] in
                self?.isRecording = true
            }
        }

        // Auto-stop after 60 seconds
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            await MainActor.run { [weak self] in
                guard let self, self.isRecording else { return }
                self.stop()
            }
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
