import Foundation
import AVFoundation
import Argmax

class WhisperKitTranscriptionService: TranscriptionService {
    private let modelsDirectory: URL
    private weak var whisperState: WhisperState?

    init(whisperState: WhisperState? = nil) {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.whisperState = whisperState
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let whisperKitModel = model as? WhisperKitModel else {
            throw NSError(domain: "WhisperKitTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model type provided."])
        }

        let localWhisperKitPro: WhisperKitPro

        // Try to use existing loaded instance first
        if let existingWhisperKitPro = await whisperState?.whisperKitPro,
           let loadedModel = await whisperState?.loadedWhisperKitModel,
           loadedModel.name == whisperKitModel.name {
            localWhisperKitPro = existingWhisperKitPro
        } else {
            // Create new instance if none exists or different model
            if let modelPath = await whisperState?.downloadedWhisperKitModelPaths[whisperKitModel.name] {
                // Initialize VAD model for WhisperKit
                let vad = try await VoiceActivityDetector.modelVAD()
                let config = WhisperKitProConfig(modelFolder: modelPath, voiceActivityDetector: vad)
                localWhisperKitPro = try await WhisperKitPro(config)
            } else {
                throw NSError(
                    domain: "WhisperKitTranscriptionService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Model '\(whisperKitModel.name)' not found locally. Please download it first."]
                )
            }
        }

        // Configure transcription options with VAD-based chunking
        let decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            wordTimestamps: false,
            chunkingStrategy: .vad
        )

        let transcriptionSegments = try await localWhisperKitPro.transcribe(audioPath: audioURL.path, decodeOptions: decodingOptions)

        let mergedResult = WhisperKitProUtils.mergeTranscriptionResults(transcriptionSegments)
        var transcript = mergedResult.text

        if UserDefaults.standard.object(forKey: "IsTextFormattingEnabled") as? Bool ?? true {
            transcript = WhisperTextFormatter.format(transcript)
        }

        return transcript
    }
} 
