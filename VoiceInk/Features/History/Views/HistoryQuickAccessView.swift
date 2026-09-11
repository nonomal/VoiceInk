import AppKit
import SwiftData
import SwiftUI

@MainActor
final class HistoryQuickAccessViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var transcriptions: [Transcription] = []
    @Published var selectedID: UUID?
    @Published private(set) var keyboardSelectionID: UUID?
    @Published var isShowingDetail = false
    @Published var isShowingInfo = false
    @Published private(set) var isSearching = false

    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?
    private let recentResultLimit = 30

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        reload()
    }

    var filteredTranscriptions: [Transcription] { transcriptions }

    var selectedTranscription: Transcription? {
        filteredTranscriptions.first { $0.id == selectedID }
    }

    func reload() {
        searchTask?.cancel()
        load(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearSearch() {
        searchText = ""
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.load(query: query)
        }
    }

    private func load(query: String) {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if query.isEmpty {
            descriptor.fetchLimit = recentResultLimit
        }

        do {
            var results = try modelContext.fetch(descriptor)

            if !query.isEmpty {
                results = results.filter {
                    $0.text.localizedStandardContains(query)
                        || ($0.enhancedText?.localizedStandardContains(query) ?? false)
                }
            }

            transcriptions = results
            selectFirstResult()
        } catch {
            transcriptions = []
            selectedID = nil
        }
        isSearching = false
    }

    func moveSelection(by offset: Int) {
        let results = filteredTranscriptions
        guard !results.isEmpty else { return }
        guard let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = results.first?.id
            keyboardSelectionID = self.selectedID
            return
        }

        let nextIndex = min(max(index + offset, 0), results.count - 1)
        self.selectedID = results[nextIndex].id
        keyboardSelectionID = self.selectedID
    }

    private func selectFirstResult() {
        selectedID = filteredTranscriptions.first?.id
        keyboardSelectionID = nil
    }
}

struct HistoryQuickAccessView: View {
    @ObservedObject var viewModel: HistoryQuickAccessViewModel
    let onSelect: (Transcription) -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingDetail {
                detailView
            } else {
                historyView
            }
        }
        .frame(width: 680, height: 470)
        .background {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            AppTheme.Surface.window.opacity(0.50)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.Border.control.opacity(0.55), lineWidth: 1)
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.isShowingDetail) { _, isShowingDetail in
            isSearchFocused = !isShowingDetail
            if !isShowingDetail {
                viewModel.isShowingInfo = false
            }
        }
    }

    private var historyView: some View {
        ZStack {
            if viewModel.filteredTranscriptions.isEmpty {
                emptyState
            } else {
                resultsList
            }

            VStack(spacing: 0) {
                QuickAccessScrollEdge(edge: .top) {
                    searchHeader
                }

                Spacer(minLength: 0)

                QuickAccessScrollEdge(edge: .bottom) {
                    keyboardHints
                }
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 14) {
            TextField("Search transcriptions...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .frame(maxWidth: 340)

            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            QuickAccessWindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            escapeKeyCap
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.filteredTranscriptions) { transcription in
                        HistoryQuickAccessRow(
                            transcription: transcription,
                            isSelected: viewModel.selectedID == transcription.id,
                            onSelect: {
                                viewModel.selectedID = transcription.id
                            },
                            onPaste: {
                                onSelect(transcription)
                            }
                        )
                        .id(transcription.id)
                    }
                }
                .padding(8)
                .padding(.top, 58)
                .padding(.bottom, 58)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity)
            .onChange(of: viewModel.keyboardSelectionID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let transcription = viewModel.selectedTranscription {
            ZStack {
                ScrollView {
                    detailContent(transcription)
                }
                .scrollIndicators(.never)

                VStack(spacing: 0) {
                    QuickAccessScrollEdge(edge: .top) {
                        detailHeader
                    }

                    Spacer(minLength: 0)

                    QuickAccessScrollEdge(edge: .bottom) {
                        HistoryDetailActionBar(
                            transcription: transcription,
                            audioURL: audioURL(for: transcription),
                            isInfoPresented: viewModel.isShowingInfo,
                            onToggleInfo: {
                                viewModel.isShowingInfo.toggle()
                            },
                            onPaste: {
                                onSelect(transcription)
                            }
                        )
                    }
                }
            }
            .sidePanel(
                isPresented: Binding(
                    get: { viewModel.isShowingInfo },
                    set: { viewModel.isShowingInfo = $0 }
                ),
                dismissOnExitCommand: false
            ) {
                VStack(spacing: 0) {
                    AppPanelHeader(title: "Info") {
                        viewModel.isShowingInfo = false
                    }

                    TranscriptionInfoPanel(transcription: transcription, showsAIRequest: false)
                        .id(transcription.id)
                }
            }
        }
    }

    private func detailContent(_ transcription: Transcription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if transcription.hasEnhancedHistoryText {
                detailTextSection("Enhanced", text: transcription.preferredHistoryText, isPrimary: true)
                detailTextSection("Original", text: transcription.text, isPrimary: false)
            } else {
                detailTextSection("Transcription", text: transcription.text, isPrimary: true)
            }

        }
        .padding(14)
        .padding(.top, 54)
        .padding(.bottom, 58)
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    viewModel.isShowingDetail = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Back to history")

            Text("Transcription Details")
                .font(.system(size: 14, weight: .semibold))

            Spacer()
            QuickAccessWindowDragArea()
                .frame(width: 120)
                .frame(maxHeight: .infinity)

            escapeKeyCap
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var escapeKeyCap: some View {
        Text("esc")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Text.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Escape")
            .accessibilityHint("Press Escape to go back or close history")
    }

    private func audioURL(for transcription: Transcription) -> URL? {
        guard let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    private func detailTextSection(_ title: LocalizedStringKey, text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(isPrimary ? AppTheme.Text.primary : AppTheme.Text.secondary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPrimary ? AppTheme.Surface.control : AppTheme.Surface.subtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.Border.subtle, lineWidth: 1)
                    }
            )
            .overlay(alignment: .topTrailing) {
                CopyIconButton(
                    textToCopy: text,
                    accessibilityLabel: "Copy text"
                )
                .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowTextKind(for: text) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPrimary ? AppTheme.Text.primary : AppTheme.Text.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(
                            isPrimary ? AppTheme.Surface.controlActive : AppTheme.Surface.subtle,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .padding(10)
                }
            }
    }

    private func shouldShowTextKind(for text: String) -> Bool {
        let font = NSFont.systemFont(ofSize: 13)
        let availableTextWidth: CGFloat = 630
        let renderedBounds = (text as NSString).boundingRect(
            with: NSSize(width: availableTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = font.ascender - font.descender + font.leading
        let renderedLineCount = Int(ceil(renderedBounds.height / lineHeight))
        return renderedLineCount > 3
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: viewModel.searchText.isEmpty ? "text.bubble" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.Text.muted)
            Text(viewModel.searchText.isEmpty ? "No transcriptions yet" : "No matching transcriptions")
                .font(.system(size: 14, weight: .medium))
            Text(viewModel.searchText.isEmpty ? "Your recent transcriptions will appear here." : "Try another search term.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyboardHints: some View {
        HStack(spacing: 10) {
            commandPill("Details", systemImage: nil, shortcut: "⌘↵") {
                if viewModel.selectedTranscription != nil {
                    withAnimation(.easeOut(duration: 0.16)) {
                        viewModel.isShowingDetail = true
                    }
                }
            }

            Spacer()

            commandPill("Paste Text", systemImage: nil, shortcut: "↵") {
                if let transcription = viewModel.selectedTranscription {
                    onSelect(transcription)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private func commandPill(
        _ title: LocalizedStringKey,
        systemImage: String?,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Text.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 5))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.Text.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                QuickAccessButtonBackground()
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickAccessScrollEdge<Content: View>: View {
    let edge: Edge
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: edge == .top ? .top : .bottom) {
            edgeMaterial
                .allowsHitTesting(false)

            content()
                .padding(edge == .top ? .top : .bottom, 8)
        }
        .frame(height: edge == .top ? 72 : 64)
    }

    private var edgeMaterial: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .mask(edgeMask)
    }

    private var edgeMask: some View {
        LinearGradient(
            stops: edge == .top
                ? [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.60),
                    .init(color: .clear, location: 1),
                ]
                : [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.40),
                    .init(color: .black, location: 1),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

}

private struct QuickAccessButtonBackground: View {
    var isSelected = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            .fill(AppTheme.Surface.control)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(AppTheme.Selection.fill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.Selection.border : AppTheme.Border.card,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
    }
}

private struct HistoryDetailActionBar: View {
    let transcription: Transcription
    let audioURL: URL?
    let isInfoPresented: Bool
    let onToggleInfo: () -> Void
    let onPaste: () -> Void

    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modeManager = ModeManager.shared

    @State private var isShowingModes = false
    @State private var isShowingPrompts = false
    @State private var isWorking = false
    @State private var selectedPromptOverride: CustomPrompt?

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    private var enhancementConfiguration: EnhancementRuntimeConfiguration? {
        guard let aiService = enhancementService.getAIService() else { return nil }
        return ModeRuntimeResolver.currentEnhancementConfiguration(
            mode: selectedMode,
            enhancementService: enhancementService,
            aiService: aiService
        )
    }

    private var selectedPromptTitle: String {
        selectedPromptOverride?.title
            ?? enhancementConfiguration?.prompt?.title
            ?? transcription.promptName
            ?? String(localized: "Select Prompt")
    }

    var body: some View {
        HStack(spacing: 8) {
            modeButton
            promptButton
            retryButton
            finderButton
            infoButton
            Spacer(minLength: 8)
            pasteButton
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private var modeButton: some View {
        Button {
            isShowingModes.toggle()
        } label: {
            actionLabel(title: selectedMode?.name ?? String(localized: "Select Mode")) {
                if let selectedMode {
                    ModeIconView(
                        icon: selectedMode.icon,
                        size: selectedMode.icon.kind == .emoji ? 13 : 11,
                        color: AppTheme.Text.primary
                    )
                    .frame(width: 16)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .popover(isPresented: $isShowingModes, arrowEdge: .bottom) {
            ModePopover(selectedModeId: selectedMode?.id) { mode in
                modeManager.setActiveConfiguration(mode)
                isShowingModes = false
                retranscribe(using: mode)
            }
        }
        .help("Select a mode and retranscribe")
    }

    private var promptButton: some View {
        Button {
            isShowingPrompts.toggle()
        } label: {
            actionLabel(title: selectedPromptTitle) {
                Image(systemName: "wand.and.stars")
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .popover(isPresented: $isShowingPrompts, arrowEdge: .bottom) {
            promptPopover
        }
        .help("Select a prompt and enhance")
    }

    private var pasteButton: some View {
        Button(action: onPaste) {
            HStack(spacing: 7) {
                Text("Paste Text")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("↵")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Text.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 5))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.Text.secondary)
            .padding(.horizontal, 10)
            .frame(minWidth: 112)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .background(QuickAccessButtonBackground())
        }
        .buttonStyle(.plain)
        .help("Paste enhanced text when available, otherwise paste the original transcription")
    }

    private var retryButton: some View {
        Button {
            guard let selectedMode else {
                showError(String(localized: "No mode selected"))
                return
            }
            retranscribe(using: selectedMode)
        } label: {
            Group {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(AppTheme.Text.secondary)
            .frame(width: 34, height: 32)
            .background(QuickAccessButtonBackground())
        }
        .buttonStyle(.plain)
        .disabled(isWorking || audioURL == nil)
        .help("Retranscribe with the selected mode")
    }

    private var finderButton: some View {
        Button {
            guard let audioURL else { return }
            NSWorkspace.shared.selectFile(
                audioURL.path,
                inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path
            )
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .frame(width: 34, height: 32)
                .background(QuickAccessButtonBackground())
        }
        .buttonStyle(.plain)
        .disabled(audioURL == nil)
        .help("Show recording in Finder")
    }

    private var infoButton: some View {
        Button(action: onToggleInfo) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .frame(width: 34, height: 32)
                .background(QuickAccessButtonBackground(isSelected: isInfoPresented))
        }
        .buttonStyle(.plain)
        .help(isInfoPresented ? "Hide transcription info" : "Show transcription info")
    }

    private func actionLabel<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 7) {
            icon()
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppTheme.Text.muted)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Text.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: 140)
        .frame(height: 32)
        .clipped()
        .background(QuickAccessButtonBackground())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var promptPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Prompt")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ScrollView {
                let prompts = enhancementService.allPrompts
                let promptsUnavailable = enhancementConfiguration?.provider == .voiceInkRefine

                VStack(alignment: .leading, spacing: 4) {
                    if promptsUnavailable {
                        Text("Custom prompts aren't available with VoiceInk Refine. Select another mode first.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }

                    if prompts.isEmpty {
                        Text("No Prompts Available")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(prompts) { prompt in
                            EnhancementPromptRow(
                                prompt: prompt,
                                isSelected: enhancementConfiguration?.prompt?.id == prompt.id,
                                isDisabled: promptsUnavailable,
                                action: {
                                    isShowingPrompts = false
                                    selectedPromptOverride = prompt
                                    enhance(using: prompt)
                                }
                            )
                            .disabled(promptsUnavailable)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 230)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(AppTheme.Surface.window)
        .popoverAppAppearance()
    }

    private func retranscribe(using mode: ModeConfig) {
        guard let audioURL else {
            showError(String(localized: "Audio file is unavailable"))
            return
        }
        guard let configuration = ModeRuntimeResolver.transcriptionConfiguration(
            mode: mode,
            transcriptionModelManager: engine.transcriptionModelManager
        ) else {
            showError(String(localized: "No transcription model selected"))
            return
        }

        isWorking = true
        let service = AudioTranscriptionService(modelContext: modelContext, engine: engine)

        Task {
            do {
                let result = try await service.retranscribeAudio(
                    from: audioURL,
                    using: configuration.model,
                    mode: mode
                )
                await MainActor.run {
                    isWorking = false
                    if let failure = result.enhancementFailure {
                        NotificationManager.shared.showNotification(
                            title: EnhancementFailureFormatter.transcriptionSavedMessage(description: failure),
                            type: .warning
                        )
                    } else {
                        NotificationManager.shared.showNotification(
                            title: String(localized: "Retranscription successful"),
                            type: .success,
                            duration: 1.0
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    showError(
                        error.localizedDescription.isEmpty
                            ? String(localized: "Retranscription failed")
                            : error.localizedDescription
                    )
                }
            }
        }
    }

    private func enhance(using prompt: CustomPrompt) {
        guard let baseConfiguration = enhancementConfiguration else {
            showError(String(localized: "AI Enhancement is not enabled or configured"))
            return
        }

        isWorking = true
        let configuration = baseConfiguration.replacingPrompt(prompt)

        Task {
            do {
                let result = try await enhancementService.enhance(
                    transcription.text,
                    configuration: configuration
                )
                await MainActor.run {
                    transcription.enhancedText = result.text
                    transcription.aiEnhancementModelName =
                        configuration.modelName ?? configuration.provider?.defaultModel
                    transcription.promptName = result.promptName
                    transcription.enhancementDuration = result.duration
                    transcription.aiRequestSystemMessage = result.systemMessage
                    transcription.aiRequestUserMessage = result.userMessage
                    try? modelContext.save()
                    isWorking = false
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Re-enhancement successful"),
                        type: .success,
                        duration: 1.0
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    let description = EnhancementFailureFormatter.description(for: error)
                    showError(
                        EnhancementFailureFormatter.reEnhancementMessage(description: description)
                    )
                }
            }
        }
    }

    private func showError(_ title: String) {
        NotificationManager.shared.showNotification(title: title, type: .error, duration: 3.0)
    }
}

private struct QuickAccessWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableAreaView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableAreaView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct HistoryQuickAccessRow: View {
    let transcription: Transcription
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.Text.primary)
                    .frame(width: 26)

                Text(transcription.preferredHistoryText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if transcription.hasEnhancedHistoryText {
                    enhancedBadge
                } else {
                    Text(transcription.timestamp, format: .relative(presentation: .named))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Text.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let modelName = transcription.transcriptionModelName, !modelName.isEmpty {
                    modelBadge(modelName)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.Selection.fill : (isHovered ? AppTheme.Surface.subtle : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(onPaste)
        )
        .onHover { isHovered = $0 }
        .accessibilityLabel(transcription.hasEnhancedHistoryText ? "Enhanced transcription" : "Original transcription")
        .accessibilityValue(transcription.preferredHistoryText)
        .accessibilityHint("Selects this transcription. Double-click to paste.")
    }

    private var enhancedBadge: some View {
        Text("Enhanced")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .frame(maxWidth: 64)
            .frame(height: 24)
            .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 7))
    }

    private func modelBadge(_ modelName: String) -> some View {
        Text(modelName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppTheme.Text.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .frame(maxWidth: 84)
            .frame(height: 24)
            .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 7))
    }
}
