import SwiftUI
import AppKit

struct ModelCardRowView: View {
    @EnvironmentObject var licenseViewModel: LicenseViewModel
    let model: any TranscriptionModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    
    // Actions
    var deleteAction: () -> Void
    var setDefaultAction: () -> Void
    var downloadAction: () -> Void
    var editAction: ((CustomCloudModel) -> Void)?
    var showInFinderAction: (() -> Void)?
    
    var body: some View {
        Group {
            switch model.provider {
            case .local:
                if let localModel = model as? LocalModel {
                    LocalModelCardView(
                        model: localModel,
                        isDownloaded: isDownloaded,
                        isCurrent: isCurrent,
                        downloadProgress: downloadProgress,
                        modelURL: modelURL,
                        deleteAction: deleteAction,
                        setDefaultAction: setDefaultAction,
                        downloadAction: downloadAction
                    )
                }
            case .nativeApple:
                if let nativeAppleModel = model as? NativeAppleModel {
                    NativeAppleModelCardView(
                        model: nativeAppleModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction
                    )
                }
            case .whisperKit:
                if licenseViewModel.licenseState == .licensed {
                    if let whisperKitModel = model as? WhisperKitModel {
                        WhisperKitModelCardView(
                            model: whisperKitModel,
                            isDownloaded: isDownloaded,
                            isCurrent: isCurrent,
                            downloadProgress: downloadProgress,
                            deleteAction: deleteAction,
                            setDefaultAction: setDefaultAction,
                            downloadAction: downloadAction,
                            showInFinderAction: showInFinderAction ?? {}
                        )
                    }
                }
            case .groq, .elevenLabs, .deepgram, .mistral:
                if let cloudModel = model as? CloudModel {
                    CloudModelCardView(
                        model: cloudModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction
                    )
                }
            case .custom:
                if let customModel = model as? CustomCloudModel {
                    CustomModelCardView(
                        model: customModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction,
                        deleteAction: deleteAction,
                        editAction: editAction ?? { _ in }
                    )
                }
            }
        }
    }
}