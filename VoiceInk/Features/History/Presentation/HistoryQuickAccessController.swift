import AppKit
import OSLog
import SwiftData
import SwiftUI

enum HistoryQuickAccessLaunchSource: String {
    case menuBar
    case shortcut
}

@MainActor
final class HistoryQuickAccessController: NSObject {
    static let shared = HistoryQuickAccessController()
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "HistoryQuickAccess"
    )

    private var panel: PersistentQuickPanel?
    private var viewModel: HistoryQuickAccessViewModel?
    private var targetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var diagnosticsSessionID = "none"

    private override init() {
        super.init()

        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor in
                self?.rememberExternalApplication(application)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
        }
    }

    func show(
        modelContext: ModelContext,
        engine: VoiceInkEngine,
        source: HistoryQuickAccessLaunchSource
    ) {
        if let panel {
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) show source=\(source.rawValue, privacy: .public) action=refocus"
            )
            panel.makeKeyAndOrderFront(nil)
            viewModel?.reload()
            return
        }

        diagnosticsSessionID = String(UUID().uuidString.prefix(8))
        targetApplication = resolvedTargetApplication()
        let targetIdentifier = applicationIdentifier(targetApplication)
        Self.logger.info(
            "session=\(self.diagnosticsSessionID, privacy: .public) show source=\(source.rawValue, privacy: .public) action=create target=\(targetIdentifier, privacy: .public)"
        )

        let viewModel = HistoryQuickAccessViewModel(modelContext: modelContext)
        let rootView = HistoryQuickAccessView(
                viewModel: viewModel,
                diagnosticsSessionID: diagnosticsSessionID,
                onPaste: { [weak self] transcription in
                    self?.paste(transcription)
                }
            )
            .modelContainer(modelContext.container)
            .environmentObject(engine)
            .environmentObject(engine.enhancementService!)

        let hostingController = NSHostingController(rootView: rootView)
        let panel = PersistentQuickPanel(
            size: NSSize(width: 680, height: 470),
            positionDefaultsKey: "VoiceInkHistoryQuickAccessOrigin",
            diagnosticsCategory: "HistoryQuickAccess"
        )
        panel.onEscape = { [weak self] in
            self?.handleEscape()
        }
        panel.onKeyDown = { [weak self] event in
            self?.handlePanelKeyDown(event) ?? false
        }
        panel.onDismissRequest = { [weak self] in
            self?.dismiss(reason: "resign-key")
        }

        panel.contentViewController = hostingController

        self.panel = panel
        self.viewModel = viewModel
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss(reason: String = "request") {
        Self.logger.info(
            "session=\(self.diagnosticsSessionID, privacy: .public) dismiss reason=\(reason, privacy: .public)"
        )
        if let panel {
            panel.persistPosition()
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        viewModel = nil
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let selectedID = shortID(viewModel?.selectedID)
        let view = viewModel?.isShowingDetail == true ? "detail" : "list"

        switch event.keyCode {
        case 125 where viewModel?.isShowingDetail == false:
            viewModel?.moveSelection(by: 1)
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) key action=select-next from=\(selectedID, privacy: .public) to=\(self.shortID(self.viewModel?.selectedID), privacy: .public)"
            )
            return true
        case 126 where viewModel?.isShowingDetail == false:
            viewModel?.moveSelection(by: -1)
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) key action=select-previous from=\(selectedID, privacy: .public) to=\(self.shortID(self.viewModel?.selectedID), privacy: .public)"
            )
            return true
        case 36, 76 where modifiers.contains(.command):
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) key action=open-details view=\(view, privacy: .public) selected=\(selectedID, privacy: .public) modifiers=\(modifiers.rawValue, privacy: .public)"
            )
            guard viewModel?.selectedTranscription != nil else { return true }
            viewModel?.isShowingInfo = false
            viewModel?.isShowingDetail = true
            return true
        case 36, 76:
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) key action=paste view=\(view, privacy: .public) selected=\(selectedID, privacy: .public) modifiers=\(modifiers.rawValue, privacy: .public)"
            )
            pasteSelectedTranscription()
            return true
        default:
            return false
        }
    }

    private func pasteSelectedTranscription() {
        guard let transcription = viewModel?.transcriptionForPaste() else {
            Self.logger.error(
                "session=\(self.diagnosticsSessionID, privacy: .public) paste aborted reason=no-selection"
            )
            return
        }
        performPaste(transcription)
    }

    private func paste(_ requestedTranscription: Transcription) {
        Self.logger.info(
            "session=\(self.diagnosticsSessionID, privacy: .public) ui action=paste-request selected=\(self.shortID(requestedTranscription.id), privacy: .public)"
        )
        guard
            let transcription = viewModel?.transcriptionForPaste(
                preferredID: requestedTranscription.id
            )
        else {
            Self.logger.error(
                "session=\(self.diagnosticsSessionID, privacy: .public) paste aborted reason=selection-not-found requested=\(self.shortID(requestedTranscription.id), privacy: .public)"
            )
            return
        }

        performPaste(transcription)
    }

    private func performPaste(_ transcription: Transcription) {
        let text = transcription.preferredHistoryText
        let targetApplication = resolvedTargetApplication() ?? targetApplication
        let targetIdentifier = applicationIdentifier(targetApplication)
        let textVariant = transcription.hasEnhancedHistoryText ? "enhanced" : "original"
        let sessionID = diagnosticsSessionID
        Self.logger.info(
            "session=\(sessionID, privacy: .public) paste begin selected=\(self.shortID(transcription.id), privacy: .public) variant=\(textVariant, privacy: .public) characters=\(text.count, privacy: .public) target=\(targetIdentifier, privacy: .public)"
        )
        self.targetApplication = nil
        dismiss(reason: "paste")

        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.logger.info(
                "session=\(sessionID, privacy: .public) paste dispatch target=\(targetIdentifier, privacy: .public)"
            )
            CursorPaster.pasteAtCursor(text)
        }
    }

    private func resolvedTargetApplication() -> NSRunningApplication? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            isExternalApplication(frontmostApplication)
        {
            rememberExternalApplication(frontmostApplication)
            return frontmostApplication
        }

        if let lastExternalApplication, !lastExternalApplication.isTerminated {
            return lastExternalApplication
        }

        return nil
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application, isExternalApplication(application), !application.isTerminated else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func applicationIdentifier(_ application: NSRunningApplication?) -> String {
        application?.bundleIdentifier ?? application?.localizedName ?? "none"
    }

    private func shortID(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "none"
    }

    private func handleEscape() {
        if viewModel?.isShowingInfo == true {
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) escape action=close-info"
            )
            viewModel?.isShowingInfo = false
        } else if viewModel?.isShowingDetail == true {
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) escape action=close-details"
            )
            viewModel?.isShowingDetail = false
        } else if viewModel?.searchText.isEmpty == false {
            Self.logger.info(
                "session=\(self.diagnosticsSessionID, privacy: .public) escape action=clear-search"
            )
            viewModel?.clearSearch()
        } else {
            dismiss(reason: "escape")
        }
    }
}

extension Transcription {
    var preferredHistoryText: String {
        guard let enhancedText, !enhancedText.isEmpty else { return text }
        return enhancedText
    }

    var hasEnhancedHistoryText: Bool {
        enhancedText?.isEmpty == false
    }
}
