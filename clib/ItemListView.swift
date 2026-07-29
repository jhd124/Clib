import AppKit
import Carbon
import UniformTypeIdentifiers

private enum ItemTypeFilter: String, CaseIterable {
    case all, text, image, url, code, video, audio

    var title: String {
        switch self {
        case .all: L10n.text("item_type.all")
        case .text: L10n.text("item_type.text")
        case .image: L10n.text("item_type.image")
        case .url: L10n.text("item_type.url")
        case .code: L10n.text("item_type.code")
        case .video: L10n.text("item_type.video")
        case .audio: L10n.text("item_type.audio")
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

enum ClipboardTimeFilter: String, CaseIterable {
    case lastHour, today, lastSevenDays, lastThirtyDays

    var title: String {
        switch self {
        case .lastHour: L10n.text("time.last_hour")
        case .today: L10n.text("time.today")
        case .lastSevenDays: L10n.text("time.last_7_days")
        case .lastThirtyDays: L10n.text("time.last_30_days")
        }
    }

    func includes(_ item: Item, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .lastHour:
            return item.createdAt >= now.addingTimeInterval(-3_600)
        case .today:
            return calendar.isDate(item.createdAt, inSameDayAs: now)
        case .lastSevenDays:
            return item.createdAt >=
                (calendar.date(byAdding: .day, value: -7, to: now) ?? now)
        case .lastThirtyDays:
            return item.createdAt >=
                (calendar.date(byAdding: .day, value: -30, to: now) ?? now)
        }
    }
}

struct ClipboardSearchQuery {
    private let tokens: [String]

    init(_ value: String) {
        tokens = value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    func matches(_ item: Item, now: Date = Date()) -> Bool {
        tokens.allSatisfy { token in
            if let value = value(afterAnyPrefix: ["app:", "来源:"], in: token) {
                return searchableSource(of: item)
                    .localizedCaseInsensitiveContains(value)
            }
            if let value = value(afterAnyPrefix: ["tag:", "标签:"], in: token) {
                return item.tags.contains {
                    $0.localizedCaseInsensitiveContains(value)
                }
            }
            if let value = value(afterAnyPrefix: ["type:", "类型:"], in: token) {
                return typeAliases(for: item.type).contains {
                    $0.localizedCaseInsensitiveContains(value)
                }
            }
            if let value = value(afterAnyPrefix: ["date:", "时间:"], in: token) {
                return matchesDate(value, item: item, now: now)
            }
            return searchableText(of: item)
                .localizedCaseInsensitiveContains(token)
        }
    }

    private func value(afterAnyPrefix prefixes: [String], in token: String) -> String? {
        for prefix in prefixes where token.lowercased().hasPrefix(prefix.lowercased()) {
            return String(token.dropFirst(prefix.count))
        }
        return nil
    }

    private func searchableText(of item: Item) -> String {
        [
            item.content,
            item.recognizedText,
            item.qrCodePayloads.joined(separator: " "),
            searchableSource(of: item),
            localizedTags(item.tags).joined(separator: " "),
            typeAliases(for: item.type).joined(separator: " "),
            Self.dayFormatter.string(from: item.createdAt)
        ].joined(separator: " ")
    }

    private func searchableSource(of item: Item) -> String {
        [
            item.sourceAppName,
            item.sourceAppBundleIdentifier
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func localizedTags(_ tags: [String]) -> [String] {
        tags.map {
            $0 == Item.favoriteTag ? L10n.text("favorite") : $0
        }
    }

    private func matchesDate(_ value: String, item: Item, now: Date) -> Bool {
        let normalized = value.lowercased()
        switch normalized {
        case "1h", "hour", "小时":
            return ClipboardTimeFilter.lastHour.includes(item, now: now)
        case "today", "今天":
            return ClipboardTimeFilter.today.includes(item, now: now)
        case "7d", "week", "本周", "一周":
            return ClipboardTimeFilter.lastSevenDays.includes(item, now: now)
        case "30d", "month", "本月", "一月":
            return ClipboardTimeFilter.lastThirtyDays.includes(item, now: now)
        default:
            return Self.dayFormatter.string(from: item.createdAt)
                .localizedCaseInsensitiveContains(value)
        }
    }

    private func typeAliases(for type: ItemType) -> [String] {
        switch type {
        case .text: ["text", "字符串", "文本", L10n.text("item_type.text")]
        case .url: ["url", "链接", L10n.text("item_type.url")]
        case .image: ["image", "图片", L10n.text("item_type.image")]
        case .video: ["video", "视频", L10n.text("item_type.video")]
        case .audio: ["audio", "音频", L10n.text("item_type.audio")]
        case .code: ["code", "代码", L10n.text("item_type.code")]
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
        layer?.cornerRadius = 6

        imageView.image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: L10n.text("accessibility.drag_window")
        )
        imageView.contentTintColor = .secondaryLabelColor
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 8,
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
            .withAlphaComponent(0.08)
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
    private let metadataLabel = NSTextField(labelWithString: "")
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
        metadataLabel.font = .systemFont(ofSize: 10.5)
        metadataLabel.textColor = .tertiaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        tagStack.orientation = .horizontal
        tagStack.alignment = .centerY
        tagStack.spacing = 5
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        addSubview(metadataLabel)
        addSubview(tagStack)
        tagHeightConstraint = tagStack.heightAnchor.constraint(equalToConstant: 0)
        tagSpacingConstraint = tagStack.topAnchor.constraint(
            equalTo: metadataLabel.bottomAnchor
        )
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metadataLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 4),
            metadataLabel.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: textField.trailingAnchor),
            metadataLabel.heightAnchor.constraint(equalToConstant: 14),
            tagSpacingConstraint,
            tagStack.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            tagStack.trailingAnchor.constraint(lessThanOrEqualTo: textField.trailingAnchor),
            tagHeightConstraint,
            tagStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    func configure(_ item: Item) {
        textField.stringValue = item.content
        metadataLabel.stringValue = ItemMetadataFormatter.string(for: item)
        configureTags(item.tags)
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
    private let recognitionLabel = NSTextField(wrappingLabelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tagStack = NSStackView()
    private var recognitionHeightConstraint: NSLayoutConstraint!
    private var recognitionSpacingConstraint: NSLayoutConstraint!
    private var tagHeightConstraint: NSLayoutConstraint!
    private var tagSpacingConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignLeft
        imageView.translatesAutoresizingMaskIntoConstraints = false
        recognitionLabel.font = .systemFont(ofSize: 11)
        recognitionLabel.textColor = .secondaryLabelColor
        recognitionLabel.maximumNumberOfLines = 2
        recognitionLabel.lineBreakMode = .byTruncatingTail
        recognitionLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 10.5)
        metadataLabel.textColor = .tertiaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        tagStack.orientation = .horizontal
        tagStack.alignment = .centerY
        tagStack.spacing = 5
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(recognitionLabel)
        addSubview(metadataLabel)
        addSubview(tagStack)
        recognitionHeightConstraint = recognitionLabel.heightAnchor
            .constraint(equalToConstant: 0)
        recognitionSpacingConstraint = recognitionLabel.topAnchor.constraint(
            equalTo: imageView.bottomAnchor
        )
        tagHeightConstraint = tagStack.heightAnchor.constraint(equalToConstant: 0)
        tagSpacingConstraint = tagStack.topAnchor.constraint(
            equalTo: metadataLabel.bottomAnchor
        )
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            recognitionSpacingConstraint,
            recognitionLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            recognitionLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            recognitionHeightConstraint,
            metadataLabel.topAnchor.constraint(
                equalTo: recognitionLabel.bottomAnchor,
                constant: 4
            ),
            metadataLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            metadataLabel.heightAnchor.constraint(equalToConstant: 14),
            tagSpacingConstraint,
            tagStack.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            tagStack.trailingAnchor.constraint(lessThanOrEqualTo: imageView.trailingAnchor),
            tagHeightConstraint,
            tagStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    func configure(_ item: Item, image: NSImage) {
        imageView.image = image
        let recognitionSummary = Self.recognitionSummary(for: item)
        recognitionLabel.stringValue = recognitionSummary
        recognitionLabel.isHidden = recognitionSummary.isEmpty
        let lineCount =
            !item.recognizedText.isEmpty && !item.qrCodePayloads.isEmpty ? 2 : 1
        recognitionHeightConstraint.constant = recognitionSummary.isEmpty
            ? 0
            : CGFloat(lineCount * 15)
        recognitionSpacingConstraint.constant = recognitionSummary.isEmpty ? 0 : 5
        metadataLabel.stringValue = ItemMetadataFormatter.string(for: item)
        configureTags(item.tags)
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

    private static func recognitionSummary(for item: Item) -> String {
        var values: [String] = []
        if let firstCode = item.qrCodePayloads.first {
            let suffix = item.qrCodePayloads.count > 1
                ? L10n.format(
                    "image.qr_more_format",
                    item.qrCodePayloads.count - 1
                )
                : ""
            values.append(
                L10n.format("image.qr_summary_format", firstCode, suffix)
            )
        }
        if !item.recognizedText.isEmpty {
            let text = item.recognizedText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            values.append(L10n.format("image.ocr_summary_format", text))
        }
        return values.joined(separator: "\n")
    }
}

private enum ItemMetadataFormatter {
    static func string(for item: Item, relativeTo date: Date = Date()) -> String {
        let time = relativeFormatter.localizedString(
            for: item.createdAt,
            relativeTo: date
        )
        guard let source = item.sourceAppName, !source.isEmpty else {
            return time
        }
        return "\(source)  ·  \(time)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = .current
        return formatter
    }()
}

private final class TagBadgeView: NSView {
    init(tag: String) {
        let title = tag == Item.favoriteTag ? L10n.text("favorite") : tag
        let theme = AppTheme.current
        super.init(frame: .zero)
        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let label = NSTextField(labelWithString: title)
        label.textColor = tag == Item.favoriteTag
            ? theme.favoriteColor
            : theme.accentColor
        label.font = font
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.backgroundColor = (
            tag == Item.favoriteTag
                ? theme.favoriteColor.withAlphaComponent(0.16)
                : theme.accentColor.withAlphaComponent(0.12)
        ).cgColor
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let width = min(
            max((title as NSString).size(withAttributes: [.font: font]).width + 18, 44),
            180
        )
        widthAnchor.constraint(equalToConstant: ceil(width)).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        toolTip = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GlassListScrollView: NSScrollView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = AppTheme.current.accentColor
            .withAlphaComponent(0.025)
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
    private let emptyLabel = NSTextField(
        labelWithString: L10n.text("clipboard.empty")
    )
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
            glass.tintColor = AppTheme.current.accentColor.withAlphaComponent(0.055)

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
        applyTheme()
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
        searchField.placeholderString = L10n.text("search.placeholder")
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
        pinButton.image = NSImage(
            systemSymbolName: "pin",
            accessibilityDescription: L10n.text("accessibility.pin")
        )
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
            dragHandle.widthAnchor.constraint(equalToConstant: 24),
            dragHandle.heightAnchor.constraint(equalTo: dragHandle.widthAnchor),
            searchField.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 8),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            searchField.centerYAnchor.constraint(equalTo: dragHandle.centerYAnchor),
            filterButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            filterButton.widthAnchor.constraint(equalToConstant: 136),
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
        observers.append(center.addObserver(
            forName: .appThemeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        stopContextMenuCloseMonitor()
    }

    func updatePinState(_ pinned: Bool) {
        pinButton.image = NSImage(
            systemSymbolName: pinned ? "pin.fill" : "pin",
            accessibilityDescription: pinned
                ? L10n.text("accessibility.unpin")
                : L10n.text("accessibility.pin")
        )
        pinButton.contentTintColor = pinned
            ? AppTheme.current.accentColor
            : .secondaryLabelColor
    }

    private func applyTheme() {
        let theme = AppTheme.current
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.tintColor = theme.accentColor.withAlphaComponent(0.055)
        } else {
            view.layer?.backgroundColor = theme.accentColor
                .withAlphaComponent(0.045)
                .cgColor
        }
        if appDelegate.isPinned {
            pinButton.contentTintColor = theme.accentColor
        }
        scrollView.needsDisplay = true
        scrollView.needsLayout = true
        tableView.reloadData()
    }

    func clearHistory() {
        viewModel.clearHistory()
        filter = .type(.all)
        reloadItems(selectFirst: false)
    }

    func notePasteboardWrite() {
        viewModel.notePasteboardWrite()
    }

    func showPrivacySettings() {
        presentAsSheet(PrivacySettingsViewController())
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
        let query = ClipboardSearchQuery(searchField.stringValue)
        displayedItems = viewModel.itemList.list.filter {
            (!$0.content.isEmpty || $0.imageData != nil) &&
            includesInCurrentFilter($0) &&
            query.matches($0)
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
        let tags = Set(viewModel.itemList.list.flatMap(\.tags)).sorted {
            if $0 == Item.favoriteTag { return true }
            if $1 == Item.favoriteTag { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
        if !tags.isEmpty {
            for tag in tags {
                filterButton.addItem(
                    withTitle: tag == Item.favoriteTag
                        ? L10n.text("favorite")
                        : L10n.format("filter.tag_format", tag)
                )
                filterButton.lastItem?.representedObject = "tag:\(tag)"
            }
            filterButton.menu?.addItem(.separator())
        }

        for value in ItemTypeFilter.allCases {
            filterButton.addItem(withTitle: value.title)
            filterButton.lastItem?.representedObject = "type:\(value.rawValue)"
        }

        if let item = filterButton.itemArray.first(where: {
            ($0.representedObject as? String) == selectedValue
        }) {
            filterButton.select(item)
        } else {
            filter = .type(.all)
            filterButton.select(
                filterButton.itemArray.first {
                    ($0.representedObject as? String) == "type:all"
                }
            )
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedItems.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let item = displayedItems[row]
        let tagHeight: CGFloat = item.tags.isEmpty ? 0 : 26
        let metadataHeight: CGFloat = 18
        guard item.type != .image else {
            let recognitionHeight: CGFloat
            if item.recognizedText.isEmpty && item.qrCodePayloads.isEmpty {
                recognitionHeight = 0
            } else if !item.recognizedText.isEmpty &&
                        !item.qrCodePayloads.isEmpty {
                recognitionHeight = 35
            } else {
                recognitionHeight = 20
            }
            return 220 + metadataHeight + tagHeight + recognitionHeight
        }

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
        return max(54, textHeight + 20) + metadataHeight + tagHeight
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
            cell.configure(item, image: image)
            return cell
        }
        let identifier = NSUserInterfaceItemIdentifier("textCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? TextItemCellView ?? TextItemCellView(frame: .zero)
        cell.identifier = identifier
        cell.configure(item)
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
        appDelegate.pasteIntoPreviouslyActiveApplication(item, mode: .original)
    }

    @objc private func pasteSelectedAsPlainText() {
        guard let item = selectedItem(), isTextItem(item) else { return }
        viewModel.promote(item)
        appDelegate.pasteIntoPreviouslyActiveApplication(item, mode: .plainText)
    }

    private func selectedItem() -> Item? {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard displayedItems.indices.contains(row) else { return nil }
        return displayedItems[row]
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(
            withTitle: L10n.text("context.paste_plain_text"),
            action: #selector(pasteSelectedAsPlainText),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.text("context.search"),
            action: #selector(searchItem),
            keyEquivalent: ""
        )
        let openURLItem = menu.addItem(
            withTitle: L10n.text("context.open_url"),
            action: #selector(openURLItem(_:)),
            keyEquivalent: ""
        )
        openURLItem.identifier = NSUserInterfaceItemIdentifier("openURL")
        let recognizeImageItem = menu.addItem(
            withTitle: L10n.text("context.recognize_image"),
            action: #selector(recognizeImage(_:)),
            keyEquivalent: ""
        )
        recognizeImageItem.identifier = NSUserInterfaceItemIdentifier(
            "recognizeImage"
        )
        let copyOCRItem = menu.addItem(
            withTitle: L10n.text("context.copy_ocr"),
            action: #selector(copyRecognizedText),
            keyEquivalent: ""
        )
        copyOCRItem.identifier = NSUserInterfaceItemIdentifier("copyOCR")
        let copyQRItem = menu.addItem(
            withTitle: L10n.text("context.copy_qr"),
            action: #selector(copyQRCode(_:)),
            keyEquivalent: ""
        )
        copyQRItem.identifier = NSUserInterfaceItemIdentifier("copyQRCode")
        menu.addItem(
            withTitle: L10n.text("context.run_command"),
            action: #selector(runCommandItem),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: L10n.text("context.decode_format"),
            action: #selector(transformItem),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.text("context.edit"),
            action: #selector(editItem),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.text("context.favorite"),
            action: #selector(toggleFavorite),
            keyEquivalent: ""
        )
        let tagItem = NSMenuItem(
            title: L10n.text("context.tags"),
            action: nil,
            keyEquivalent: ""
        )
        tagItem.identifier = NSUserInterfaceItemIdentifier("tagMenu")
        tagItem.submenu = NSMenu()
        menu.addItem(tagItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L10n.text("context.delete"),
            action: #selector(deleteItem),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let editable = selectedItem().map(isTextItem) ?? false
        menu.items.first(where: {
            $0.action == #selector(pasteSelectedAsPlainText)
        })?.isEnabled = editable
        menu.items.first(where: { $0.action == #selector(searchItem) })?.isEnabled = editable
        let selected = selectedItem()
        if let openURLItem = menu.items.first(where: {
            $0.identifier?.rawValue == "openURL"
        }) {
            configurePayloadMenuItem(
                openURLItem,
                payloads: selected.map(
                    SearchDestinationResolver.webLinkSources
                ) ?? [],
                action: #selector(openURLItem(_:))
            )
        }
        if let recognizeImageItem = menu.items.first(where: {
            $0.identifier?.rawValue == "recognizeImage"
        }) {
            configureRecognitionMenuItem(
                recognizeImageItem,
                for: selected
            )
        }
        menu.items.first(where: {
            $0.identifier?.rawValue == "copyOCR"
        })?.isEnabled = selected?.recognizedText.isEmpty == false
        if let copyQRItem = menu.items.first(where: {
            $0.identifier?.rawValue == "copyQRCode"
        }) {
            configurePayloadMenuItem(
                copyQRItem,
                payloads: QRCodeContentResolver.payloads(for: selected),
                action: #selector(copyQRCode(_:))
            )
        }
        let canRunCommand = selectedItem().map {
            isTextItem($0) &&
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        menu.items.first(where: { $0.action == #selector(runCommandItem) })?.isEnabled = canRunCommand
        menu.items.first(where: { $0.action == #selector(transformItem) })?.isEnabled = editable
        menu.items.first(where: { $0.action == #selector(editItem) })?.isEnabled = editable
        let item = selectedItem()
        let favorite = menu.items.first(where: { $0.action == #selector(toggleFavorite) })
        favorite?.title = item?.tags.contains(Item.favoriteTag) == true
            ? L10n.text("context.unfavorite")
            : L10n.text("context.favorite")
        favorite?.state = item?.tags.contains(Item.favoriteTag) == true ? .on : .off
        if let tagMenu = menu.items.first(where: {
            $0.identifier?.rawValue == "tagMenu"
        })?.submenu {
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

    @objc private func openURLItem(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? String,
              let url = SearchDestinationResolver.webURL(for: source) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func recognizeImage(_ sender: NSMenuItem) {
        guard let item = selectedItem() else { return }
        let force = item.imageAnalysisCompleted
        if viewModel.analyzeImage(item, force: force) {
            sender.title = L10n.text("context.recognizing_image")
            sender.isEnabled = false
        }
    }

    private func configureRecognitionMenuItem(
        _ menuItem: NSMenuItem,
        for item: Item?
    ) {
        guard let item, item.type == .image else {
            menuItem.title = L10n.text("context.recognize_image")
            menuItem.isEnabled = false
            return
        }
        if viewModel.isAnalyzingImage(item) {
            menuItem.title = L10n.text("context.recognizing_image")
            menuItem.isEnabled = false
        } else {
            menuItem.title = item.imageAnalysisCompleted
                ? L10n.text("context.recognize_image_again")
                : L10n.text("context.recognize_image")
            menuItem.isEnabled = true
        }
    }

    @objc private func copyRecognizedText() {
        guard let text = selectedItem()?.recognizedText, !text.isEmpty else {
            return
        }
        copyToPasteboard(text)
    }

    @objc private func copyQRCode(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        copyToPasteboard(payload)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        viewModel.notePasteboardWrite()
    }

    private func configurePayloadMenuItem(
        _ item: NSMenuItem,
        payloads: [String],
        action: Selector
    ) {
        item.submenu = nil
        item.target = self
        item.action = action
        item.representedObject = payloads.first
        item.isEnabled = !payloads.isEmpty
        guard payloads.count > 1 else { return }

        item.action = nil
        item.representedObject = nil
        let submenu = NSMenu()
        for (index, payload) in payloads.enumerated() {
            let title = payload.count > 60
                ? String(payload.prefix(57)) + "…"
                : payload
            let child = submenu.addItem(
                withTitle: "\(index + 1). \(title)",
                action: action,
                keyEquivalent: ""
            )
            child.target = self
            child.representedObject = payload
            child.toolTip = payload
        }
        item.submenu = submenu
    }

    @objc private func runCommandItem() {
        guard let item = selectedItem() else { return }
        let command = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        do {
            let scriptURL = try ShellCommandLauncher.makeScript(for: command)
            NSWorkspace.shared.open(
                scriptURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.showCommandLaunchError(error)
                }
            }
        } catch {
            showCommandLaunchError(error)
        }
    }

    private func showCommandLaunchError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("command.launch_error")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("common.ok"))
        alert.runModal()
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
            withTitle: L10n.text("tag.new_ellipsis"),
            action: #selector(createTag),
            keyEquivalent: ""
        )
        newTag.target = self
    }

    @objc private func toggleFavorite() {
        toggleFavoriteOfSelectedItem()
    }

    func toggleFavoriteOfSelectedItem() {
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
        alert.messageText = L10n.text("tag.new")
        alert.informativeText = L10n.text("tag.prompt")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = L10n.text("tag.placeholder")
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.text("common.add"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.buttons[1].keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let tag = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              tag != Item.favoriteTag,
              tag != L10n.text("favorite") else {
            return
        }
        if !item.tags.contains(tag) {
            viewModel.toggleTag(tag, on: item)
            reloadItems(selectFirst: false)
        }
    }
}

private final class PrivacySettingsViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate {
    private let settingsStore = ClipboardPrivacySettingsStore()
    private let pauseCheckbox = NSButton(
        checkboxWithTitle: L10n.text("privacy.pause"),
        target: nil,
        action: nil
    )
    private let sensitiveCheckbox = NSButton(
        checkboxWithTitle: L10n.text("privacy.ignore_sensitive"),
        target: nil,
        action: nil
    )
    private let retentionPopup = NSPopUpButton()
    private let tableView = NSTableView()
    private let removeButton = NSButton(
        title: L10n.text("common.remove"),
        target: nil,
        action: nil
    )
    private var applications: [ExcludedApplication] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 430))
        applications = settingsStore.excludedApplications

        let title = NSTextField(labelWithString: L10n.text("privacy.title"))
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let description = NSTextField(
            wrappingLabelWithString: L10n.text("privacy.description")
        )
        description.textColor = .secondaryLabelColor

        pauseCheckbox.target = self
        pauseCheckbox.action = #selector(togglePause)
        sensitiveCheckbox.target = self
        sensitiveCheckbox.action = #selector(toggleSensitiveContent)

        for period in ClipboardRetentionPeriod.allCases {
            retentionPopup.addItem(withTitle: period.title)
            retentionPopup.lastItem?.representedObject = period.rawValue
        }
        retentionPopup.target = self
        retentionPopup.action = #selector(retentionChanged)

        let retentionRow = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("privacy.retention")),
            NSView(),
            retentionPopup
        ])
        retentionRow.orientation = .horizontal
        retentionRow.alignment = .centerY

        let excludedTitle = NSTextField(
            labelWithString: L10n.text("privacy.excluded_apps")
        )
        excludedTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let excludedHint = NSTextField(
            labelWithString: L10n.text("privacy.excluded_apps_hint")
        )
        excludedHint.textColor = .secondaryLabelColor
        excludedHint.font = .systemFont(ofSize: 11)

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("excludedApplication")
        )
        column.title = L10n.text("privacy.application")
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(removeSelectedApplication)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(
            title: L10n.text("privacy.add_app_ellipsis"),
            target: self,
            action: #selector(addApplication)
        )
        removeButton.target = self
        removeButton.action = #selector(removeSelectedApplication)
        let appButtons = NSStackView(views: [addButton, removeButton, NSView()])
        appButtons.orientation = .horizontal
        appButtons.spacing = 8

        let closeButton = NSButton(
            title: L10n.text("common.done"),
            target: self,
            action: #selector(close)
        )
        closeButton.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), closeButton])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [
            title,
            description,
            pauseCheckbox,
            sensitiveCheckbox,
            retentionRow,
            excludedTitle,
            excludedHint,
            scrollView,
            appButtons,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            retentionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 145),
            appButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshControls()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        applications.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("excludedApplicationCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let label: NSTextField
        if let existing = cell.textField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let application = applications[row]
        label.stringValue =
            "\(application.name)  (\(application.bundleIdentifier))"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    private func refreshControls() {
        let settings = settingsStore.settings
        pauseCheckbox.state = settings.isMonitoringPaused ? .on : .off
        sensitiveCheckbox.state = settings.ignoresSensitiveContent ? .on : .off
        if let item = retentionPopup.itemArray.first(where: {
            ($0.representedObject as? Int) == settings.retentionPeriod.rawValue
        }) {
            retentionPopup.select(item)
        }
        applications = settings.excludedApplications
        tableView.reloadData()
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    @objc private func togglePause() {
        settingsStore.setMonitoringPaused(pauseCheckbox.state == .on)
    }

    @objc private func toggleSensitiveContent() {
        settingsStore.setIgnoresSensitiveContent(sensitiveCheckbox.state == .on)
    }

    @objc private func retentionChanged() {
        guard let rawValue = retentionPopup.selectedItem?.representedObject as? Int,
              let period = ClipboardRetentionPeriod(rawValue: rawValue) else {
            return
        }
        settingsStore.setRetentionPeriod(period)
    }

    @objc private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("privacy.choose_apps")
        panel.prompt = L10n.text("privacy.exclude")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier else {
                    continue
                }
                let name =
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                        as? String ??
                    bundle.object(forInfoDictionaryKey: "CFBundleName")
                        as? String ??
                    url.deletingPathExtension().lastPathComponent
                settingsStore.addExcludedApplication(
                    ExcludedApplication(
                        bundleIdentifier: bundleIdentifier,
                        name: name
                    )
                )
            }
            refreshControls()
        }
    }

    @objc private func removeSelectedApplication() {
        let row = tableView.selectedRow
        guard applications.indices.contains(row) else { return }
        settingsStore.removeExcludedApplication(
            bundleIdentifier: applications[row].bundleIdentifier
        )
        refreshControls()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    @objc private func close() {
        dismiss(nil)
    }
}

enum TextTransform: String, CaseIterable {
    case base64Encode, base64Decode, jwtDecode, formatJSON, compressJSON, parseURL
    var title: String {
        switch self {
        case .base64Encode: L10n.text("transform.base64_encode")
        case .base64Decode: L10n.text("transform.base64_decode")
        case .jwtDecode: L10n.text("transform.jwt_decode")
        case .formatJSON: L10n.text("transform.format_json")
        case .compressJSON: L10n.text("transform.compress_json")
        case .parseURL: L10n.text("transform.parse_url")
        }
    }
}

enum TextTransformError: LocalizedError {
    case invalidBase64
    case invalidJWT

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            L10n.text("transform.invalid_base64")
        case .invalidJWT:
            L10n.text("transform.invalid_jwt")
        }
    }
}

struct QRCodeContentResolver {
    static func payloads(for item: Item?) -> [String] {
        guard let item, item.type == .image else { return [] }
        return item.qrCodePayloads
    }
}

struct SearchDestinationResolver {
    static func webLinkSources(for item: Item) -> [String] {
        var seen = Set<String>()
        let qrCodePayloads = QRCodeContentResolver.payloads(for: item)
        return ([item.content] + qrCodePayloads).compactMap { source in
            let trimmed = source.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard webURL(for: trimmed) != nil,
                  seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    static func webURL(for source: String) -> URL? {
        let content = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: content),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    static func destination(for source: String) -> URL? {
        let content = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        if let url = webURL(for: content) { return url }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: content)]
        return components?.url
    }
}

enum ShellCommandLauncher {
    static func makeScript(for command: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clib-commands", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let scriptURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("command")
        let completionMessage = L10n.text("command.finished_format")
        let script = """
        #!/bin/zsh
        rm -f -- "$0"
        \(command)
        status=$?
        printf '\\n\(completionMessage)\\n' "$status"
        exec "${SHELL:-/bin/zsh}" -l
        """
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }
}

struct TextTransformer {
    static func transform(_ source: String, using transform: TextTransform) throws -> String {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch transform {
        case .base64Encode:
            Data(source.utf8).base64EncodedString()
        case .base64Decode:
            try decodeBase64(source)
        case .jwtDecode:
            try decodeJWT(source)
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

    private static func decodeJWT(_ source: String) throws -> String {
        let segments = source.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let header = try decodeJWTSegment(String(segments[0])),
              let payload = try decodeJWTSegment(String(segments[1])) else {
            throw TextTransformError.invalidJWT
        }
        return try serialize(
            [
                "header": header,
                "payload": payload,
                "signature": String(segments[2]),
                "signatureVerified": false
            ],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func decodeJWTSegment(_ segment: String) throws -> Any? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw TextTransformError.invalidJWT
        }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
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
    private let resultView = NSTextView()
    private let errorLabel = NSTextField(labelWithString: "")
    private var tabKeyMonitor: Any?

    init(item: Item) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 620, height: 380)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        removeTabKeyMonitor()
    }

    override func loadView() {
        view = NSView()
        popup.addItems(withTitles: TextTransform.allCases.map(\.title))
        popup.selectItem(at: 1)
        popup.target = self
        popup.action = #selector(run)
        resultView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultView.isEditable = false
        errorLabel.textColor = .systemRed

        let runButton = NSButton(
            title: L10n.text("transform.run"),
            target: self,
            action: #selector(run)
        )
        let copyButton = NSButton(
            title: L10n.text("transform.copy_result"),
            target: self,
            action: #selector(copyResult)
        )
        let closeButton = NSButton(
            title: L10n.text("common.close"),
            target: self,
            action: #selector(close)
        )
        let top = NSStackView(views: [popup, runButton])
        top.orientation = .horizontal
        let buttons = NSStackView(views: [closeButton, copyButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [
            top, scroll(resultView), errorLabel, buttons
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
            resultView.heightAnchor.constraint(greaterThanOrEqualToConstant: 230)
        ])
        run()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installTabKeyMonitor()
    }

    override func viewWillDisappear() {
        removeTabKeyMonitor()
        super.viewWillDisappear()
    }

    private func installTabKeyMonitor() {
        removeTabKeyMonitor()
        tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  view.window?.isKeyWindow == true,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                return event
            }
            if event.keyCode == kVK_Escape {
                close()
                return nil
            }
            guard event.keyCode == kVK_Tab else { return event }
            DispatchQueue.main.async { [weak self] in
                self?.popup.performClick(nil)
            }
            return nil
        }
    }

    private func removeTabKeyMonitor() {
        guard let tabKeyMonitor else { return }
        NSEvent.removeMonitor(tabKeyMonitor)
        self.tabKeyMonitor = nil
    }

    @objc private func run() {
        do {
            let result = try TextTransformer.transform(
                item.content, using: TextTransform.allCases[popup.indexOfSelectedItem]
            )
            resultView.string = result.isEmpty ? item.content : result
            errorLabel.stringValue = ""
        } catch {
            resultView.string = item.content
            errorLabel.stringValue = error.localizedDescription
        }
    }
    @objc private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultView.string, forType: .string)
    }
    @objc private func close() { dismiss(nil) }
}

private final class EditTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class EditItemViewController: NSViewController {
    private let item: Item
    private let onSave: (String) -> Void
    private let textView = EditTextView()
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
        let cancel = NSButton(
            title: L10n.text("common.cancel"),
            target: self,
            action: #selector(close)
        )
        let save = NSButton(
            title: L10n.text("common.save"),
            target: self,
            action: #selector(save)
        )
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = .command
        cancel.keyEquivalent = "\u{1b}"
        textView.onSave = { [weak self] in self?.save() }
        textView.onCancel = { [weak self] in self?.close() }
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
