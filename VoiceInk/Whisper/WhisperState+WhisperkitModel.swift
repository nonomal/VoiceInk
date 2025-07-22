import Foundation
import Argmax
import Combine
import OSLog

extension WhisperState {
    // MARK: - WhisperKit Model Loading
    
    func loadWhisperKitModel(_ model: WhisperKitModel) async throws {
        guard whisperKitPro == nil else { return }
        
        guard let modelPath = downloadedWhisperKitModelPaths[model.name] else {
            throw NSError(
                domain: "WhisperKitTranscriptionService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Model '\(model.name)' not found locally. Please download it first."]
            )
        }
        
        logger.info("🔄 Loading WhisperKit model: \(model.name)")
        
        do {
            // Initialize VAD model for WhisperKit
            let vad = try await VoiceActivityDetector.modelVAD()
            let config = WhisperKitProConfig(modelFolder: modelPath, voiceActivityDetector: vad)
            
            whisperKitPro = try await WhisperKitPro(config)
            loadedWhisperKitModel = model
            
            logger.info("✅ WhisperKit model loaded successfully: \(model.name)")
        } catch {
            logger.error("❌ Failed to load WhisperKit model: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - WhisperKit Model Download
    
    func downloadWhisperKitModel(model: WhisperKitModel) async {
        // Fetch Hugging Face token securely
        let modelToken: String? = await withCheckedContinuation { continuation in
            KeyFetcher.shared.fetchHuggingFaceKey { token in
                continuation.resume(returning: token)
            }
        }
        
        guard let modelToken = modelToken else {
            logger.error("❌ Failed to fetch Hugging Face token for model download")
            await MainActor.run {
                self.downloadProgress[model.name] = nil
            }
            return
        }
        
        logger.notice("✅ Hugging Face token fetched successfully for model download")

        let config = WhisperKitProConfig(
            model: model.name,
            downloadBase: modelsDirectory,
            modelRepo: model.modelRepo,
            modelToken: modelToken
        )

        let modelStore = ModelStore(whisperKitConfig: config)
        let modelName = model.name
        
        await MainActor.run {
            self.downloadProgress[modelName] = 0.0
        }

        modelStore.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                if let progress = progress {
                    let percentage = progress.fractionCompleted
                     self?.downloadProgress[modelName] = min(percentage, 0.99)
                }
            }
            .store(in: &cancellables)

        do {
            let modelURL = try await modelStore.downloadModel()
            
            await MainActor.run {
                self.downloadProgress[modelName] = 1.0
                self.downloadedWhisperKitModelPaths[model.name] = modelURL.path
            }
            
            // Initialize with downloaded model
            let config = WhisperKitProConfig(
                modelFolder: modelURL.path(percentEncoded: false)
            )
            whisperKitPro = try await WhisperKitPro(config)
            
        } catch {
            logger.error("Failed to download WhisperKit model: \(error.localizedDescription)")
            await MainActor.run {
                self.downloadProgress[modelName] = nil
            }
        }
    }
} 