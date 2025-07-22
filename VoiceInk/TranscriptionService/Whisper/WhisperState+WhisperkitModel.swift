import Foundation
import Argmax
import Combine
import OSLog

extension WhisperState {
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
                self.downloadProgress[modelName] = 0.99
                self.downloadedWhisperKitModelPaths[model.name] = modelURL.path
            }
            
            let vad = try await VoiceActivityDetector.modelVAD()
            let initConfig = WhisperKitProConfig(modelFolder: modelURL.path, voiceActivityDetector: vad)
            let _ = try await WhisperKitPro(initConfig)
            
            await MainActor.run {
                self.downloadProgress[modelName] = 1.0
            }
            
            logger.info("✅ WhisperKit model downloaded and initialized successfully: \(model.name)")
            
        } catch {
            logger.error("Failed to download or initialize WhisperKit model: \(error.localizedDescription)")
            await MainActor.run {
                self.downloadProgress[modelName] = nil
            }
        }
    }
} 