import Foundation

extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .local:
                return availableModels.contains { $0.name == model.name }
            case .nativeApple:
                if #available(macOS 26, *) {
                    return true
                } else {
                    return false
                }
            case .whisperKit:
                guard let whisperKitModel = model as? WhisperKitModel else { return false }
                return downloadedWhisperKitModelPaths[whisperKitModel.name] != nil
            case .groq:
                let key = UserDefaults.standard.string(forKey: "GROQAPIKey")
                return key != nil && !key!.isEmpty
            case .elevenLabs:
                let key = UserDefaults.standard.string(forKey: "ElevenLabsAPIKey")
                return key != nil && !key!.isEmpty
            case .deepgram:
                let key = UserDefaults.standard.string(forKey: "DeepgramAPIKey")
                return key != nil && !key!.isEmpty
            case .mistral:
                let key = UserDefaults.standard.string(forKey: "MistralAPIKey")
                return key != nil && !key!.isEmpty
            case .custom:
                // Custom models are always usable since they contain their own API keys
                return true
            }
        }
    }
} 
