import Foundation
import AVFoundation
import Argmax

class WhisperKitTranscriptionService: TranscriptionService {
    private weak var whisperState: WhisperState?

    init(whisperState: WhisperState? = nil) {
        self.whisperState = whisperState
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let whisperKitModel = model as? WhisperKitModel else {
            throw NSError(domain: "WhisperKitTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model type provided."])
        }

        // Get model path from downloaded models
        guard let modelPath = await whisperState?.downloadedWhisperKitModelPaths[whisperKitModel.name] else {
            throw NSError(
                domain: "WhisperKitTranscriptionService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Model '\(whisperKitModel.name)' not found locally. Please download it first."]
            )
        }
        
        // Initialize VAD model for WhisperKit
        let vad = try await VoiceActivityDetector.modelVAD()
        let config = WhisperKitProConfig(modelFolder: modelPath, voiceActivityDetector: vad)
        let whisperKitPro = try await WhisperKitPro(config)

        // Configure transcription options with VAD-based chunking
        let decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            wordTimestamps: false,
            chunkingStrategy: .vad
        )

        let transcriptionSegments = try await whisperKitPro.transcribe(audioPath: audioURL.path, decodeOptions: decodingOptions)

        let mergedResult = WhisperKitProUtils.mergeTranscriptionResults(transcriptionSegments)
        var transcript = mergedResult.text

        if UserDefaults.standard.object(forKey: "IsTextFormattingEnabled") as? Bool ?? true {
            transcript = WhisperTextFormatter.format(transcript)
        }

        return transcript
    }
} 
