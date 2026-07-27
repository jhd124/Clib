import SwiftUI
import Carbon

private enum ItemTypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case url
    case code
    case video
    case audio

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .text: "字符串"
        case .image: "图片"
        case .url: "URL"
        case .code: "代码"
        case .video: "视频"
        case .audio: "音频"
        }
    }

    func includes(_ item: Item) -> Bool {
        switch self {
        case .all: true
        case .text: item.type == .text
        case .image: item.type == .image
        case .url: item.type == .url
        case .code: item.type == .code
        case .video: item.type == .video
        case .audio: item.type == .audio
        }
    }
}

private enum ContextAction: Hashable {
    case search
    case transform
    case edit
    case delete
}

private enum TopControl: Hashable {
    case search
}

struct ItemListView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var selectedItemID: Item.ID?
    @State private var searchText = ""
    @State private var typeFilter: ItemTypeFilter = .all
    @State private var contextMenuItemID: Item.ID?
    @State private var transformingItem: Item?
    @State private var editingItem: Item?
    @State private var focusedContextAction: ContextAction?
    @State private var contextKeyMonitor: Any?
    @State private var listKeyMonitor: Any?
    @FocusState private var isListFocused: Bool
    @FocusState private var focusedTopControl: TopControl?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    WindowDragHandle()
                        .frame(width: 22, height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.12))
                        }
                        .overlay {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                        .help("拖动窗口")

                    TextField("搜索剪贴板", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($focusedTopControl, equals: .search)

                    ItemTypeFilterMenu(selection: $typeFilter)
                        .frame(width: 76, height: 22)
                    .fixedSize()

                    Button {
                        appDelegate.togglePin()
                    } label: {
                        Image(systemName: appDelegate.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appDelegate.isPinned ? Color.accentColor : .secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(appDelegate.isPinned ? "取消置顶" : "始终置顶")
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 30)
                .background(Color.clear)

                Divider()

                List(selectableItems) { item in
                    itemContent(item)
                        .padding(.vertical, 8)
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedItemID == item.id {
                                paste(item)
                            } else {
                                selectedItemID = item.id
                            }
                        }
                        .contextMenu {
                            contextMenuButtons(for: item)
                        }
                        .popover(
                            isPresented: Binding(
                                get: { contextMenuItemID == item.id },
                                set: {
                                    if !$0 {
                                        focusedContextAction = nil
                                        contextMenuItemID = nil
                                    }
                                }
                            ),
                            arrowEdge: .trailing
                        ) {
                            keyboardContextMenu(for: item)
                        }
                        .listRowBackground(
                            selectedItemID == item.id
                                ? Color.accentColor.opacity(0.22)
                                : Color.clear
                        )
                }
                .scrollContentBackground(.hidden)
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.return) {
                    pasteSelectedItem()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    if contextMenuItemID == nil {
                        showContextMenuForSelectedItem()
                    } else {
                        focusFirstContextAction()
                    }
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    guard contextMenuItemID != nil else { return .ignored }
                    contextMenuItemID = nil
                    return .handled
                }
                .onKeyPress(.escape) {
                    NSApp.hide(nil)
                    return .handled
                }
                .onAppear {
                    selectFirstItem()
                    startListKeyMonitor(proxy: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .clipboardPickerDidOpen)) { _ in
                    selectFirstItem()
                }
                .onChange(of: viewModel.itemList.list) {
                    guard let firstItem = selectableItems.first else { return }
                    if selectedItemID == nil {
                        selectedItemID = firstItem.id
                    }
                    withAnimation {
                        proxy.scrollTo(firstItem.id, anchor: .top)
                    }
                }
                .onChange(of: searchText) {
                    selectFirstFilteredItem(proxy: proxy)
                }
                .onChange(of: typeFilter) {
                    selectFirstFilteredItem(proxy: proxy)
                }
            }
            .background {
                windowBackground
            }
            .sheet(item: $transformingItem, onDismiss: restoreListFocus) { item in
                TextTransformSheet(item: item)
            }
            .sheet(item: $editingItem, onDismiss: restoreListFocus) { item in
                EditItemSheet(item: item) { content in
                    viewModel.updateContent(of: item, to: content)
                }
            }
            .onChange(of: contextMenuItemID) {
                if contextMenuItemID == nil {
                    stopContextKeyMonitor()
                } else {
                    startContextKeyMonitor()
                }
            }
            .onDisappear {
                stopContextKeyMonitor()
                stopListKeyMonitor()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSMenu.didEndTrackingNotification
                )
            ) { _ in
                restoreListFocus()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                restoreListFocus()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .focusClipboardSearch
                )
            ) { _ in
                focusSearchField()
            }
        }
    }

    @ViewBuilder
    private var windowBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                .opacity(0.86)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .opacity(0.86)
        }
    }

    private var selectableItems: [Item] {
        viewModel.itemList.list.filter {
            let hasDisplayableContent = !$0.content.isEmpty || $0.imageData != nil
            let matchesType = typeFilter.includes($0)
            let matchesSearch = searchText.isEmpty ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            return hasDisplayableContent && matchesType && matchesSearch
        }
    }

    @ViewBuilder
    private func itemContent(_ item: Item) -> some View {
        if item.type == .image,
           let imageData = item.imageData,
           let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
                .accessibilityLabel("剪贴板图片")
        } else {
            Text(item.content)
                .lineLimit(7)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectFirstItem() {
        stopContextKeyMonitor()
        contextMenuItemID = nil
        focusedContextAction = nil
        selectedItemID = selectableItems.first?.id

        // The app may have been hidden while FocusState remained true. Force a
        // fresh first-responder request every time the global shortcut opens it.
        isListFocused = false
        DispatchQueue.main.async {
            guard NSApp.isActive else { return }
            NSApp.keyWindow?.makeKey()
            isListFocused = true
        }
    }

    private func selectFirstFilteredItem(proxy: ScrollViewProxy) {
        selectedItemID = selectableItems.first?.id
        guard let selectedItemID else { return }
        withAnimation {
            proxy.scrollTo(selectedItemID, anchor: .top)
        }
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        guard !selectableItems.isEmpty else { return }
        let currentIndex = selectedItemID.flatMap { id in
            selectableItems.firstIndex { $0.id == id }
        } ?? 0
        let newIndex = min(max(currentIndex + offset, 0), selectableItems.count - 1)
        let item = selectableItems[newIndex]
        selectedItemID = item.id
        withAnimation {
            proxy.scrollTo(item.id, anchor: .center)
        }
    }

    private func pasteSelectedItem() {
        guard let selectedItemID,
              let item = selectableItems.first(where: { $0.id == selectedItemID }) else {
            return
        }
        paste(item)
    }

    @ViewBuilder
    private func contextMenuButtons(for item: Item) -> some View {
        Button {
            search(item)
        } label: {
            Label("搜索", systemImage: "magnifyingglass")
        }
        .disabled(!isTextItem(item))

        Button {
            openTransformSheet(for: item)
        } label: {
            Label("Decode / Format", systemImage: "text.badge.gearshape")
        }
        .disabled(!isTextItem(item))

        Divider()

        Button {
            openEditSheet(for: item)
        } label: {
            Label("编辑内容", systemImage: "pencil")
        }
        .disabled(!isEditable(item))

        Divider()

        Button(role: .destructive) {
            delete(item)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func keyboardContextMenu(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            contextActionButton(
                "搜索",
                systemImage: "magnifyingglass",
                contextAction: .search,
                disabled: !isTextItem(item)
            ) {
                contextMenuItemID = nil
                search(item)
            }
            contextActionButton(
                "Decode / Format",
                systemImage: "text.badge.gearshape",
                contextAction: .transform,
                disabled: !isTextItem(item)
            ) {
                openTransformSheet(for: item)
            }
            Divider()
            contextActionButton(
                "编辑内容",
                systemImage: "pencil",
                contextAction: .edit,
                disabled: !isEditable(item)
            ) {
                openEditSheet(for: item)
            }
            Divider()
            contextActionButton(
                "删除",
                systemImage: "trash",
                contextAction: .delete,
                isDestructive: true
            ) {
                delete(item)
            }
        }
        .padding(6)
        .frame(width: 190)
        .onKeyPress(.rightArrow) {
            focusFirstContextAction()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            focusedContextAction = nil
            contextMenuItemID = nil
            DispatchQueue.main.async {
                isListFocused = true
            }
            return .handled
        }
    }

    private func contextActionButton(
        _ title: String,
        systemImage: String,
        contextAction: ContextAction,
        disabled: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .background {
                    if focusedContextAction == contextAction {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.22))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func showContextMenuForSelectedItem() {
        guard let selectedItemID,
              selectableItems.contains(where: { $0.id == selectedItemID }) else {
            return
        }
        contextMenuItemID = selectedItemID
    }

    private func focusFirstContextAction() {
        guard let contextMenuItemID,
              let item = selectableItems.first(where: { $0.id == contextMenuItemID }) else {
            return
        }
        focusedContextAction = availableContextActions(for: item).first
    }

    private func startContextKeyMonitor() {
        guard contextKeyMonitor == nil else { return }
        contextKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard contextMenuItemID != nil else { return event }

            switch Int(event.keyCode) {
            case kVK_RightArrow:
                focusFirstContextAction()
                return nil
            case kVK_LeftArrow:
                closeKeyboardContextMenu()
                return nil
            case kVK_UpArrow:
                moveContextAction(by: -1)
                return nil
            case kVK_DownArrow:
                moveContextAction(by: 1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                guard focusedContextAction != nil else { return event }
                executeFocusedContextAction()
                return nil
            default:
                return event
            }
        }
    }

    private func startListKeyMonitor(proxy: ScrollViewProxy) {
        guard listKeyMonitor == nil else { return }
        listKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.isActive,
                  transformingItem == nil,
                  editingItem == nil else {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command),
               modifiers.intersection([.option, .control]).isEmpty {
                switch Int(event.keyCode) {
                case kVK_ANSI_F:
                    stopContextKeyMonitor()
                    contextMenuItemID = nil
                    focusedContextAction = nil
                    isListFocused = false
                    focusedTopControl = .search
                    return nil
                case kVK_ANSI_D:
                    stopContextKeyMonitor()
                    contextMenuItemID = nil
                    focusedContextAction = nil
                    focusedTopControl = nil
                    isListFocused = false
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .openItemTypeFilterMenu,
                            object: nil
                        )
                    }
                    return nil
                default:
                    return event
                }
            }

            guard contextMenuItemID == nil,
                  modifiers.intersection([.command, .option, .control]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else {
                return event
            }

            switch Int(event.keyCode) {
            case kVK_UpArrow:
                moveSelection(by: -1, proxy: proxy)
                return nil
            case kVK_DownArrow:
                moveSelection(by: 1, proxy: proxy)
                return nil
            case kVK_RightArrow:
                showContextMenuForSelectedItem()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                pasteSelectedItem()
                return nil
            case kVK_Escape:
                NSApp.hide(nil)
                return nil
            default:
                return event
            }
        }
    }

    private func focusSearchField() {
        guard transformingItem == nil, editingItem == nil else { return }
        stopContextKeyMonitor()
        contextMenuItemID = nil
        focusedContextAction = nil
        isListFocused = false
        DispatchQueue.main.async {
            focusedTopControl = .search
        }
    }

    private func stopListKeyMonitor() {
        guard let listKeyMonitor else { return }
        NSEvent.removeMonitor(listKeyMonitor)
        self.listKeyMonitor = nil
    }

    private func stopContextKeyMonitor() {
        guard let contextKeyMonitor else { return }
        NSEvent.removeMonitor(contextKeyMonitor)
        self.contextKeyMonitor = nil
        focusedContextAction = nil
    }

    private func closeKeyboardContextMenu() {
        focusedContextAction = nil
        contextMenuItemID = nil
        DispatchQueue.main.async {
            isListFocused = true
        }
    }

    private func availableContextActions(for item: Item) -> [ContextAction] {
        var actions: [ContextAction] = []
        if isTextItem(item) {
            actions.append(contentsOf: [.search, .transform])
        }
        if isEditable(item) {
            actions.append(.edit)
        }
        actions.append(.delete)
        return actions
    }

    private func moveContextAction(by offset: Int) {
        guard let contextMenuItemID,
              let item = selectableItems.first(where: { $0.id == contextMenuItemID }) else {
            return
        }
        let actions = availableContextActions(for: item)
        guard !actions.isEmpty else { return }
        let currentIndex = focusedContextAction.flatMap(actions.firstIndex(of:)) ?? 0
        let newIndex = min(max(currentIndex + offset, 0), actions.count - 1)
        focusedContextAction = actions[newIndex]
    }

    private func executeFocusedContextAction() {
        guard let menuItemID = contextMenuItemID,
              let item = selectableItems.first(where: { $0.id == menuItemID }),
              let focusedContextAction else {
            return
        }

        switch focusedContextAction {
        case .search:
            contextMenuItemID = nil
            search(item)
        case .transform:
            openTransformSheet(for: item)
        case .edit:
            openEditSheet(for: item)
        case .delete:
            delete(item)
        }
    }

    private func search(_ item: Item) {
        guard isTextItem(item) else { return }
        let destination = SearchDestinationResolver.destination(for: item.content)
        if let destination {
            NSWorkspace.shared.open(destination)
        }
    }

    private func openTransformSheet(for item: Item) {
        stopContextKeyMonitor()
        contextMenuItemID = nil
        DispatchQueue.main.async {
            transformingItem = item
        }
    }

    private func openEditSheet(for item: Item) {
        stopContextKeyMonitor()
        contextMenuItemID = nil
        DispatchQueue.main.async {
            editingItem = item
        }
    }

    private func restoreListFocus() {
        guard transformingItem == nil,
              editingItem == nil,
              contextMenuItemID == nil else {
            return
        }

        stopContextKeyMonitor()
        contextMenuItemID = nil
        focusedContextAction = nil

        // The sheet destroys its focused control. Toggle FocusState so SwiftUI
        // makes a fresh first-responder request for the borderless main window.
        isListFocused = false
        DispatchQueue.main.async {
            // A menu action may have intentionally opened another application.
            // In that case, don't steal focus back from it.
            guard NSApp.isActive else { return }
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            isListFocused = true
        }
    }

    private func isTextItem(_ item: Item) -> Bool {
        item.type != .image && item.type != .video && item.type != .audio
    }

    private func isEditable(_ item: Item) -> Bool {
        isTextItem(item)
    }

    private func delete(_ item: Item) {
        stopContextKeyMonitor()
        contextMenuItemID = nil
        viewModel.delete(item)
        selectedItemID = selectableItems.first?.id
        DispatchQueue.main.async {
            isListFocused = true
        }
    }

    private func paste(_ item: Item) {
        viewModel.promote(item)
        selectedItemID = item.id
        appDelegate.pasteIntoPreviouslyActiveApplication(item)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

private struct ItemTypeFilterMenu: NSViewRepresentable {
    @Binding var selection: ItemTypeFilter

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))

        for filter in ItemTypeFilter.allCases {
            button.addItem(withTitle: filter.title)
            button.lastItem?.representedObject = filter.rawValue
        }
        button.selectItem(withTitle: selection.title)
        context.coordinator.attach(to: button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        if button.titleOfSelectedItem != selection.title {
            button.selectItem(withTitle: selection.title)
        }
    }

    static func dismantleNSView(
        _ nsView: NSPopUpButton,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        private var selection: Binding<ItemTypeFilter>
        private weak var button: NSPopUpButton?
        private var openMenuObserver: NSObjectProtocol?

        init(selection: Binding<ItemTypeFilter>) {
            self.selection = selection
        }

        func attach(to button: NSPopUpButton) {
            self.button = button
            openMenuObserver = NotificationCenter.default.addObserver(
                forName: .openItemTypeFilterMenu,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let button = self?.button,
                      button.window?.isKeyWindow == true else {
                    return
                }
                button.window?.makeFirstResponder(button)
                button.performClick(nil)
            }
        }

        func detach() {
            if let openMenuObserver {
                NotificationCenter.default.removeObserver(openMenuObserver)
            }
            openMenuObserver = nil
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String,
                  let filter = ItemTypeFilter(rawValue: rawValue) else {
                return
            }
            selection.wrappedValue = filter
        }
    }
}

enum TextTransform: String, CaseIterable, Identifiable {
    case base64Encode
    case base64Decode
    case formatJSON
    case compressJSON
    case parseURL

    var id: Self { self }

    var title: String {
        switch self {
        case .base64Encode: "Base64 Encode"
        case .base64Decode: "Base64 Decode"
        case .formatJSON: "Format JSON"
        case .compressJSON: "Compress JSON"
        case .parseURL: "递归解析 URL 参数"
        }
    }
}

enum TextTransformError: LocalizedError {
    case invalidBase64

    var errorDescription: String? {
        switch self {
        case .invalidBase64: "内容不是有效的 UTF-8 Base64 字符串"
        }
    }
}

struct SearchDestinationResolver {
    static func destination(for source: String) -> URL? {
        let content = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        if let url = URL(string: content),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: content)]
        return components?.url
    }
}

struct TextTransformer {
    static func transform(
        _ source: String,
        using transform: TextTransform
    ) throws -> String {
        switch transform {
        case .base64Encode:
            return Data(source.utf8).base64EncodedString()

        case .base64Decode:
            guard let data = Data(
                base64Encoded: source,
                options: .ignoreUnknownCharacters
            ), let decoded = String(data: data, encoding: .utf8) else {
                throw TextTransformError.invalidBase64
            }
            return decoded

        case .formatJSON:
            return try jsonString(from: source, prettyPrinted: true)

        case .compressJSON:
            return try jsonString(from: source, prettyPrinted: false)

        case .parseURL:
            let object = try recursiveURLObject(from: source, depth: 0)
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func jsonString(
        from source: String,
        prettyPrinted: Bool
    ) throws -> String {
        let object = try JSONSerialization.jsonObject(
            with: Data(source.utf8),
            options: [.fragmentsAllowed]
        )
        var options: JSONSerialization.WritingOptions = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .fragmentsAllowed
        ]
        if prettyPrinted {
            options.insert(.prettyPrinted)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        return String(decoding: data, as: UTF8.self)
    }

    private static func recursiveURLObject(
        from source: String,
        depth: Int
    ) throws -> Any {
        guard depth < 8 else { return fullyPercentDecoded(source) }
        let decodedSource = fullyPercentDecoded(source)

        let components: URLComponents?
        if decodedSource.contains("://") {
            components = URLComponents(string: decodedSource)
        } else if decodedSource.contains("=") {
            components = URLComponents(string: "https://local.invalid/?\(decodedSource)")
        } else {
            components = nil
        }

        guard let components,
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return decodedSource
        }

        var parameters: [String: Any] = [:]
        for queryItem in queryItems {
            parameters[queryItem.name] = try recursiveURLObject(
                from: queryItem.value ?? "",
                depth: depth + 1
            )
        }

        var object: [String: Any] = ["parameters": parameters]
        if decodedSource.contains("://") {
            object["scheme"] = components.scheme ?? ""
            object["host"] = components.host ?? ""
            object["path"] = components.path
        }
        return object
    }

    private static func fullyPercentDecoded(_ source: String) -> String {
        var value = source
        for _ in 0..<8 {
            guard let decoded = value.removingPercentEncoding,
                  decoded != value else {
                break
            }
            value = decoded
        }
        return value
    }
}

private struct TextTransformSheet: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @State private var transform: TextTransform = .base64Decode
    @State private var result = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Decode / Format")
                    .font(.headline)
                Spacer()
                Picker("操作", selection: $transform) {
                    ForEach(TextTransform.allCases) { transform in
                        Text(transform.title).tag(transform)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                Button("执行") {
                    performTransform()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            GroupBox("原始内容") {
                ScrollView {
                    Text(item.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(minHeight: 80)
            }

            GroupBox("处理结果") {
                TextEditor(text: $result)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                Button("复制结果") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(result, forType: .string)
                }
                .disabled(result.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 620, height: 460)
        .onAppear {
            performTransform()
        }
        .onChange(of: transform) {
            performTransform()
        }
    }

    private func performTransform() {
        do {
            result = try TextTransformer.transform(item.content, using: transform)
            errorMessage = nil
        } catch {
            result = ""
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditItemSheet: View {
    let item: Item
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(item: Item, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _content = State(initialValue: item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑内容")
                .font(.headline)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 520, minHeight: 280)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    onSave(content)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(content.isEmpty)
            }
        }
        .padding(16)
    }
}
