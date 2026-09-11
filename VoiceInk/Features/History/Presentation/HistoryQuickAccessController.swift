import AppKit
import SwiftData
import SwiftUI

@MainActor
final class HistoryQuickAccessController: NSObject {
    static let shared = HistoryQuickAccessController()

    private var panel: PersistentQuickPanel?
    private var keyEventMonitor: Any?
    private var viewModel: HistoryQuickAccessViewModel?
    private var targetApplication: NSRunningApplication?

    private override init() {
        super.init()
    }

    func show(modelContext: ModelContext, engine: VoiceInkEngine) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            viewModel?.reload()
            return
        }

        targetApplication = NSWorkspace.shared.frontmostApplication

        let viewModel = HistoryQuickAccessViewModel(modelContext: modelContext)
        let rootView = HistoryQuickAccessView(
                viewModel: viewModel,
                onSelect: { [weak self] transcription in
                    self?.paste(transcription)
                }
            )
            .modelContainer(modelContext.container)
            .environmentObject(engine)
            .environmentObject(engine.enhancementService!)

        let hostingController = NSHostingController(rootView: rootView)
        let panel = PersistentQuickPanel(
            size: NSSize(width: 680, height: 470),
            positionDefaultsKey: "VoiceInkHistoryQuickAccessOrigin"
        )
        panel.onEscape = { [weak self] in
            self?.handleEscape()
        }
        panel.onDismissRequest = { [weak self] in
            self?.dismiss()
        }

        panel.contentViewController = hostingController

        self.panel = panel
        self.viewModel = viewModel
        installKeyEventMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        removeKeyEventMonitor()
        if let panel {
            panel.persistPosition()
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        viewModel = nil
    }

    private func installKeyEventMonitor() {
        removeKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }

            switch event.keyCode {
            case 53:
                self.handleEscape()
                return nil
            case 125:
                self.viewModel?.moveSelection(by: 1)
                return nil
            case 126:
                self.viewModel?.moveSelection(by: -1)
                return nil
            case 36, 76 where event.modifierFlags.contains(.command):
                if self.viewModel?.selectedTranscription != nil {
                    self.viewModel?.isShowingInfo = false
                    self.viewModel?.isShowingDetail = true
                }
                return nil
            case 36, 76:
                if let transcription = self.viewModel?.selectedTranscription {
                    self.paste(transcription)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func paste(_ transcription: Transcription) {
        let text = transcription.preferredHistoryText
        let targetApplication = targetApplication
        self.targetApplication = nil
        dismiss()

        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            CursorPaster.pasteAtCursor(text)
        }
    }

    private func handleEscape() {
        if viewModel?.isShowingInfo == true {
            viewModel?.isShowingInfo = false
        } else if viewModel?.isShowingDetail == true {
            viewModel?.isShowingDetail = false
        } else if viewModel?.searchText.isEmpty == false {
            viewModel?.clearSearch()
        } else {
            dismiss()
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
