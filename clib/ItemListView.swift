import AppKit
import Carbon

private enum ItemTypeFilter: String, CaseIterable {
    case all, text, image, url, code, video, audio

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
        self == .all || item.type.rawValue == rawValue
    }
}

private enum ItemFilter: Equatable {
    case type(ItemTypeFilter)
    case tag(String)
}

private final class ClipboardTableView: NSTableView {
    var handleKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if handleKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

private final class ClipboardSearchField: NSSearchField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class WindowDragHandleView: NSView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7

        imageView.image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "拖动窗口"
        )
        imageView.contentTintColor = .secondaryLabelColor
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 10,
            weight: .semibold
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(0.16)
            .cgColor
    }

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

private final class TextItemCellView: NSView {
    let textField = NSTextField(wrappingLabelWithString: "")
    private let tagStack = NSStackView()
    private var tagHeightConstraint: NSLayoutConstraint!
    private var tagSpacingConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField.maximumNumberOfLines = 7
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = true
        textField.cell?.truncatesLastVisibleLine = true
        textField.font = .systemFont(ofSize: 13.5)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        tagStack.orientation = .horizontal
        tagStack.alignment = .centerY
        tagStack.spacing = 5
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        addSubview(tagStack)
        tagHeightConstraint = tagStack.heightAnchor.constraint(equalToConstant: 0)
        tagSpacingConstraint = tagStack.topAnchor.constraint(equalTo: textField.bottomAnchor)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            tagSpacingConstraint,
            tagStack.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            tagStack.trailingAnchor.constraint(lessThanOrEqualTo: textField.trailingAnchor),
            tagHeightConstraint,
            tagStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureTags(_ tags: [String]) {
        tagStack.arrangedSubviews.forEach {
            tagStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        tags.forEach { tagStack.addArrangedSubview(TagBadgeView(tag: $0)) }
        tagStack.isHidden = tags.isEmpty
        tagHeightConstraint.constant = tags.isEmpty ? 0 : 20
        tagSpacingConstraint.constant = tags.isEmpty ? 0 : 6
    }
}

private final class ImageItemCellView: NSView {
    let imageView = NSImageView()
    private let tagStack = NSStackView()
    private var tagHeightConstraint: NSLayoutConstraint!
    private var tagSpacingConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignLeft
        imageView.translatesAutoresizingMaskIntoConstraints = false
        tagStack.orientation = .horizontal
        tagStack.alignment = .centerY
        tagStack.spacing = 5
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(tagStack)
        tagHeightConstraint = tagStack.heightAnchor.constraint(equalToConstant: 0)
        tagSpacingConstraint = tagStack.topAnchor.constraint(equalTo: imageView.bottomAnchor)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            tagSpacingConstraint,
            tagStack.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            tagStack.trailingAnchor.constraint(lessThanOrEqualTo: imageView.trailingAnchor),
            tagHeightConstraint,
            tagStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureTags(_ tags: [String]) {
        tagStack.arrangedSubviews.forEach {
            tagStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        tags.forEach { tagStack.addArrangedSubview(TagBadgeView(tag: $0)) }
        tagStack.isHidden = tags.isEmpty
        tagHeightConstraint.constant = tags.isEmpty ? 0 : 20
        tagSpacingConstraint.constant = tags.isEmpty ? 0 : 6
    }
}

private final class TagBadgeView: NSTextField {
    init(tag: String) {
        let title = tag == Item.favoriteTag ? "★ 收藏" : tag
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = tag == Item.favoriteTag
            ? NSColor.systemYellow.withAlphaComponent(0.18)
            : NSColor.controlAccentColor.withAlphaComponent(0.12)
        textColor = tag == Item.favoriteTag ? .systemOrange : .controlAccentColor
        font = .systemFont(ofSize: 10.5, weight: .medium)
        alignment = .center
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.usesSingleLineMode = true
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        let width = min(max((title as NSString).size(withAttributes: [.font: font!]).width + 14, 36), 120)
        widthAnchor.constraint(equalToConstant: ceil(width)).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GlassListScrollView: NSScrollView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.5)
            .cgColor
    }
}

final class ItemListViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let viewModel = ClipboardViewModel()
    private unowned let appDelegate: AppDelegate
    private let dragHandle = WindowDragHandleView()
    private let searchField = ClipboardSearchField()
    private let filterButton = NSPopUpButton()
    private let pinButton = NSButton()
    private let tableView = ClipboardTableView()
    private let scrollView = GlassListScrollView()
    private let emptyLabel = NSTextField(labelWithString: "暂无剪贴板记录")
    private var contentHost: NSView!
    private var displayedItems: [Item] = []
    private var filter: ItemFilter = .type(.all)
    private var observers: [NSObjectProtocol] = []
    private var lastMeasuredTableWidth: CGFloat = 0
    private var contextMenuCloseMonitor: Any?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 16
            glass.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.035)

            let host = NSView(frame: glass.bounds)
            host.autoresizingMask = [.width, .height]
            glass.contentView = host
            contentHost = host
            view = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 16
            effect.layer?.masksToBounds = true
            contentHost = effect
            view = effect
        }
        configureToolbar()
        configureTable()
        installConstraints()
        installObservers()
        viewModel.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.reloadItems(selectFirst: false) }
        }
        reloadItems(selectFirst: true)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateRowHeightsIfNeeded()
        focusList()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateRowHeightsIfNeeded()
    }

    private func configureToolbar() {
        searchField.placeholderString = "搜索剪贴板"
        searchField.controlSize = .regular
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.onEscape = { [weak self] in
            self?.focusList()
        }

        filterButton.controlSize = .regular
        rebuildFilterMenu()
        filterButton.target = self
        filterButton.action = #selector(filterChanged)

        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.contentTintColor = .secondaryLabelColor
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "始终置顶")
        pinButton.target = appDelegate
        pinButton.action = #selector(AppDelegate.togglePin)

        [dragHandle, searchField, filterButton, pinButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview($0)
        }
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelected)
        tableView.menu = makeContextMenu()
        tableView.handleKey = { [weak self] event in
            self?.handleTableKey(event) ?? false
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(scrollView)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(emptyLabel)
    }

    private func installConstraints() {
        NSLayoutConstraint.activate([
            dragHandle.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 10),
            dragHandle.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 12),
            dragHandle.widthAnchor.constraint(equalToConstant: 28),
            dragHandle.heightAnchor.constraint(equalToConstant: 28),
            searchField.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 8),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            searchField.centerYAnchor.constraint(equalTo: dragHandle.centerYAnchor),
            filterButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            filterButton.widthAnchor.constraint(equalToConstant: 94),
            pinButton.leadingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: 6),
            pinButton.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -12),
            pinButton.widthAnchor.constraint(equalToConstant: 26),
            searchField.centerYAnchor.constraint(equalTo: filterButton.centerYAnchor),
            pinButton.centerYAnchor.constraint(equalTo: filterButton.centerYAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .focusClipboardSearch, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            view.window?.makeFirstResponder(searchField)
        })
        observers.append(center.addObserver(
            forName: .openItemTypeFilterMenu, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildFilterMenu()
            self?.filterButton.performClick(nil)
        })
        observers.append(center.addObserver(
            forName: NSPopUpButton.willPopUpNotification,
            object: filterButton,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildFilterMenu()
        })
        observers.append(center.addObserver(
            forName: .clipboardPickerDidOpen, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadItems(selectFirst: true)
            self?.focusList()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        stopContextMenuCloseMonitor()
    }

    func updatePinState(_ pinned: Bool) {
        pinButton.image = NSImage(
            systemSymbolName: pinned ? "pin.fill" : "pin",
            accessibilityDescription: pinned ? "取消置顶" : "始终置顶"
        )
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
    }

    private func focusList() {
        view.window?.makeFirstResponder(tableView)
    }

    private func updateRowHeightsIfNeeded() {
        let width = tableView.bounds.width
        guard width > 0, abs(width - lastMeasuredTableWidth) > 0.5 else {
            return
        }
        lastMeasuredTableWidth = width
        guard !displayedItems.isEmpty else { return }
        tableView.noteHeightOfRows(
            withIndexesChanged: IndexSet(integersIn: displayedItems.indices)
        )
    }

    @objc private func searchChanged() {
        reloadItems(selectFirst: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadItems(selectFirst: true)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchField,
              commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }
        focusList()
        return true
    }

    @objc private func filterChanged() {
        guard let value = filterButton.selectedItem?.representedObject as? String else { return }
        if value.hasPrefix("type:"),
           let selected = ItemTypeFilter(rawValue: String(value.dropFirst(5))) {
            filter = .type(selected)
        } else if value.hasPrefix("tag:") {
            filter = .tag(String(value.dropFirst(4)))
        }
        reloadItems(selectFirst: true)
    }

    private func reloadItems(selectFirst: Bool) {
        rebuildFilterMenu()
        let query = searchField.stringValue
        displayedItems = viewModel.itemList.list.filter {
            (!$0.content.isEmpty || $0.imageData != nil) &&
            includesInCurrentFilter($0) &&
            (query.isEmpty || $0.content.localizedCaseInsensitiveContains(query))
        }
        tableView.reloadData()
        emptyLabel.isHidden = !displayedItems.isEmpty
        if selectFirst && !displayedItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func includesInCurrentFilter(_ item: Item) -> Bool {
        switch filter {
        case .type(let type): type.includes(item)
        case .tag(let tag): item.tags.contains(tag)
        }
    }

    private func rebuildFilterMenu() {
        let selectedValue: String
        switch filter {
        case .type(let type): selectedValue = "type:\(type.rawValue)"
        case .tag(let tag): selectedValue = "tag:\(tag)"
        }

        filterButton.removeAllItems()
        for value in ItemTypeFilter.allCases {
            filterButton.addItem(withTitle: value.title)
            filterButton.lastItem?.representedObject = "type:\(value.rawValue)"
        }

        let tags = Set(viewModel.itemList.list.flatMap(\.tags)).sorted {
            if $0 == Item.favoriteTag { return true }
            if $1 == Item.favoriteTag { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
        if !tags.isEmpty {
            filterButton.menu?.addItem(.separator())
            for tag in tags {
                filterButton.addItem(withTitle: tag == Item.favoriteTag ? "★ 收藏" : "标签：\(tag)")
                filterButton.lastItem?.representedObject = "tag:\(tag)"
            }
        }

        if let item = filterButton.itemArray.first(where: {
            ($0.representedObject as? String) == selectedValue
        }) {
            filterButton.select(item)
        } else {
            filter = .type(.all)
            filterButton.selectItem(at: 0)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedItems.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let item = displayedItems[row]
        let tagHeight: CGFloat = item.tags.isEmpty ? 0 : 26
        guard item.type != .image else { return 220 + tagHeight }

        let font = NSFont.systemFont(ofSize: 13.5)
        let resolvedWidth = max(
            tableView.bounds.width,
            contentHost.bounds.width,
            preferredContentSize.width
        )
        let availableWidth = max(resolvedWidth - 28, 120)
        let measured = (item.content as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textHeight = min(ceil(measured), lineHeight * 7)
        return max(54, textHeight + 20) + tagHeight
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let item = displayedItems[row]
        if item.type == .image, let data = item.imageData, let image = NSImage(data: data) {
            let identifier = NSUserInterfaceItemIdentifier("imageCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self)
                as? ImageItemCellView ?? ImageItemCellView(frame: .zero)
            cell.identifier = identifier
            cell.imageView.image = image
            cell.configureTags(item.tags)
            return cell
        }
        let identifier = NSUserInterfaceItemIdentifier("textCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? TextItemCellView ?? TextItemCellView(frame: .zero)
        cell.identifier = identifier
        cell.textField.stringValue = item.content
        cell.configureTags(item.tags)
        return cell
    }

    private func handleTableKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected()
            return true
        case kVK_Escape:
            NSApp.hide(nil)
            return true
        case kVK_RightArrow:
            showContextMenu()
            return true
        default:
            return false
        }
    }

    @objc private func pasteSelected() {
        guard let item = selectedItem() else { return }
        viewModel.promote(item)
        appDelegate.pasteIntoPreviouslyActiveApplication(item)
    }

    private func selectedItem() -> Item? {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard displayedItems.indices.contains(row) else { return nil }
        return displayedItems[row]
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "搜索", action: #selector(searchItem), keyEquivalent: "")
        menu.addItem(withTitle: "Decode / Format", action: #selector(transformItem), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "编辑内容", action: #selector(editItem), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "收藏", action: #selector(toggleFavorite), keyEquivalent: "")
        let tagItem = NSMenuItem(title: "标签", action: nil, keyEquivalent: "")
        tagItem.submenu = NSMenu()
        menu.addItem(tagItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "删除", action: #selector(deleteItem), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let editable = selectedItem().map(isTextItem) ?? false
        menu.items.first(where: { $0.action == #selector(searchItem) })?.isEnabled = editable
        menu.items.first(where: { $0.action == #selector(transformItem) })?.isEnabled = editable
        menu.items.first(where: { $0.action == #selector(editItem) })?.isEnabled = editable
        let item = selectedItem()
        let favorite = menu.items.first(where: { $0.action == #selector(toggleFavorite) })
        favorite?.title = item?.tags.contains(Item.favoriteTag) == true ? "取消收藏" : "收藏"
        favorite?.state = item?.tags.contains(Item.favoriteTag) == true ? .on : .off
        if let tagMenu = menu.items.first(where: { $0.title == "标签" })?.submenu {
            rebuildTagMenu(tagMenu, for: item)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        stopContextMenuCloseMonitor()
        contextMenuCloseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .rightMouseDown]
        ) { event in
            if event.type == .rightMouseDown {
                menu.cancelTracking()
                return nil
            }

            if event.keyCode == kVK_LeftArrow {
                menu.cancelTracking()
                return nil
            }
            return event
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        stopContextMenuCloseMonitor()
        focusList()
    }

    private func stopContextMenuCloseMonitor() {
        guard let contextMenuCloseMonitor else { return }
        NSEvent.removeMonitor(contextMenuCloseMonitor)
        self.contextMenuCloseMonitor = nil
    }

    private func showContextMenu() {
        guard tableView.selectedRow >= 0, let menu = tableView.menu else { return }
        let rect = tableView.rect(ofRow: tableView.selectedRow)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.maxX - 8, y: rect.midY), in: tableView)
    }

    private func isTextItem(_ item: Item) -> Bool {
        ![ItemType.image, .video, .audio].contains(item.type)
    }

    @objc private func searchItem() {
        guard let item = selectedItem(),
              let url = SearchDestinationResolver.destination(for: item.content) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func transformItem() {
        guard let item = selectedItem() else { return }
        presentAsSheet(TransformViewController(item: item))
    }

    @objc private func editItem() {
        guard let item = selectedItem() else { return }
        presentAsSheet(EditItemViewController(item: item) { [weak self] content in
            self?.viewModel.updateContent(of: item, to: content)
        })
    }

    @objc private func deleteItem() {
        guard let item = selectedItem() else { return }
        viewModel.delete(item)
        reloadItems(selectFirst: true)
    }

    private func rebuildTagMenu(_ menu: NSMenu, for item: Item?) {
        menu.removeAllItems()
        let tags = Set(viewModel.itemList.list.flatMap(\.tags))
            .filter { $0 != Item.favoriteTag }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for tag in tags {
            let menuItem = menu.addItem(
                withTitle: tag,
                action: #selector(toggleTagFromMenu(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = tag
            menuItem.state = item?.tags.contains(tag) == true ? .on : .off
        }
        if !tags.isEmpty { menu.addItem(.separator()) }
        let newTag = menu.addItem(
            withTitle: "新建标签…",
            action: #selector(createTag),
            keyEquivalent: ""
        )
        newTag.target = self
    }

    @objc private func toggleFavorite() {
        guard let item = selectedItem() else { return }
        viewModel.toggleTag(Item.favoriteTag, on: item)
        reloadItems(selectFirst: false)
    }

    @objc private func toggleTagFromMenu(_ sender: NSMenuItem) {
        guard let item = selectedItem(), let tag = sender.representedObject as? String else { return }
        viewModel.toggleTag(tag, on: item)
        reloadItems(selectFirst: false)
    }

    @objc private func createTag() {
        guard let item = selectedItem() else { return }
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入要添加到此条目的标签名称。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "标签名称"
        alert.accessoryView = input
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let tag = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, tag != Item.favoriteTag else { return }
        if !item.tags.contains(tag) {
            viewModel.toggleTag(tag, on: item)
            reloadItems(selectFirst: false)
        }
    }
}

enum TextTransform: String, CaseIterable {
    case base64Encode, base64Decode, formatJSON, compressJSON, parseURL
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
    var errorDescription: String? { "内容不是有效的 UTF-8 Base64 字符串" }
}

struct SearchDestinationResolver {
    static func destination(for source: String) -> URL? {
        let content = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        if let url = URL(string: content),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: content)]
        return components?.url
    }
}

struct TextTransformer {
    static func transform(_ source: String, using transform: TextTransform) throws -> String {
        switch transform {
        case .base64Encode:
            Data(source.utf8).base64EncodedString()
        case .base64Decode:
            try decodeBase64(source)
        case .formatJSON:
            try jsonString(source, pretty: true)
        case .compressJSON:
            try jsonString(source, pretty: false)
        case .parseURL:
            try serialize(recursiveURLObject(source, depth: 0))
        }
    }

    private static func decodeBase64(_ source: String) throws -> String {
        guard let data = Data(base64Encoded: source, options: .ignoreUnknownCharacters),
              let value = String(data: data, encoding: .utf8) else {
            throw TextTransformError.invalidBase64
        }
        return value
    }

    private static func jsonString(_ source: String, pretty: Bool) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(source.utf8), options: .fragmentsAllowed)
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted) }
        return try serialize(object, options: options)
    }

    private static func serialize(
        _ object: Any,
        options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: options), as: UTF8.self)
    }

    private static func recursiveURLObject(_ source: String, depth: Int) throws -> Any {
        guard depth < 8 else { return fullyDecoded(source) }
        let decoded = fullyDecoded(source)
        let components = URLComponents(
            string: decoded.contains("://") ? decoded :
                (decoded.contains("=") ? "https://local.invalid/?\(decoded)" : "")
        )
        guard let components, let queryItems = components.queryItems, !queryItems.isEmpty else {
            return decoded
        }
        var parameters: [String: Any] = [:]
        for item in queryItems {
            parameters[item.name] = try recursiveURLObject(item.value ?? "", depth: depth + 1)
        }
        var object: [String: Any] = ["parameters": parameters]
        if decoded.contains("://") {
            object["scheme"] = components.scheme ?? ""
            object["host"] = components.host ?? ""
            object["path"] = components.path
        }
        return object
    }

    private static func fullyDecoded(_ source: String) -> String {
        var value = source
        for _ in 0..<8 {
            guard let decoded = value.removingPercentEncoding, decoded != value else { break }
            value = decoded
        }
        return value
    }
}

private final class TransformViewController: NSViewController {
    private let item: Item
    private let popup = NSPopUpButton()
    private let sourceView = NSTextView()
    private let resultView = NSTextView()
    private let errorLabel = NSTextField(labelWithString: "")

    init(item: Item) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 620, height: 460)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        popup.addItems(withTitles: TextTransform.allCases.map(\.title))
        popup.selectItem(at: 1)
        popup.target = self
        popup.action = #selector(run)
        sourceView.string = item.content
        sourceView.isEditable = false
        resultView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        errorLabel.textColor = .systemRed

        let runButton = NSButton(title: "执行", target: self, action: #selector(run))
        let copyButton = NSButton(title: "复制结果", target: self, action: #selector(copyResult))
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(close))
        let top = NSStackView(views: [popup, runButton])
        top.orientation = .horizontal
        let buttons = NSStackView(views: [closeButton, copyButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [
            top, scroll(sourceView), scroll(resultView), errorLabel, buttons
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            sourceView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            resultView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
        run()
    }

    @objc private func run() {
        do {
            resultView.string = try TextTransformer.transform(
                item.content, using: TextTransform.allCases[popup.indexOfSelectedItem]
            )
            errorLabel.stringValue = ""
        } catch {
            resultView.string = ""
            errorLabel.stringValue = error.localizedDescription
        }
    }
    @objc private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultView.string, forType: .string)
    }
    @objc private func close() { dismiss(nil) }
}

private final class EditItemViewController: NSViewController {
    private let item: Item
    private let onSave: (String) -> Void
    private let textView = NSTextView()
    init(item: Item, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 560, height: 350)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView()
        textView.string = item.content
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let cancel = NSButton(title: "取消", target: self, action: #selector(close))
        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [scroll(textView), buttons])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
    @objc private func save() {
        guard !textView.string.isEmpty else { return }
        onSave(textView.string)
        dismiss(nil)
    }
    @objc private func close() { dismiss(nil) }
}

private func scroll(_ documentView: NSView) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.documentView = documentView
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    return scroll
}
