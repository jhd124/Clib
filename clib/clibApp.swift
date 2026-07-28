import AppKit
import Carbon

extension Notification.Name {
    static let clipboardPickerDidOpen = Notification.Name("clipboardPickerDidOpen")
    static let focusClipboardSearch = Notification.Name("focusClipboardSearch")
    static let openItemTypeFilterMenu = Notification.Name("openItemTypeFilterMenu")
    static let appThemeDidChange = Notification.Name("appThemeDidChange")
}

enum AppTheme: String, CaseIterable {
    case mistBlue, mint, sakura, lavender, amber, graphite

    static let defaultsKey = "appTheme"

    static var current: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let theme = AppTheme(rawValue: raw) else {
                return .mistBlue
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var title: String {
        switch self {
        case .mistBlue: "雾霭蓝"
        case .mint: "清新薄荷"
        case .sakura: "柔雾樱花"
        case .lavender: "暮光薰衣草"
        case .amber: "暖调琥珀"
        case .graphite: "高级石墨"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .mistBlue: NSColor(srgbRed: 0.28, green: 0.55, blue: 0.92, alpha: 1)
        case .mint: NSColor(srgbRed: 0.20, green: 0.67, blue: 0.57, alpha: 1)
        case .sakura: NSColor(srgbRed: 0.91, green: 0.45, blue: 0.60, alpha: 1)
        case .lavender: NSColor(srgbRed: 0.55, green: 0.43, blue: 0.86, alpha: 1)
        case .amber: NSColor(srgbRed: 0.88, green: 0.55, blue: 0.20, alpha: 1)
        case .graphite: NSColor(srgbRed: 0.38, green: 0.43, blue: 0.50, alpha: 1)
        }
    }

    var favoriteColor: NSColor {
        switch self {
        case .mint: NSColor(srgbRed: 0.12, green: 0.56, blue: 0.45, alpha: 1)
        case .graphite: NSColor(srgbRed: 0.46, green: 0.50, blue: 0.57, alpha: 1)
        default: accentColor
        }
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ClipboardWindowController?
    private var eventMonitor: Any?
    private var statusItem: NSStatusItem?
    private weak var themeMenu: NSMenu?
    private var previouslyActiveApplication: NSRunningApplication?
    private(set) var isPinned = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        setupStatusItem()
        checkAccessibilityPermissions()
        setupGlobalHotkeyListener()

        let controller = ClipboardWindowController(appDelegate: self)
        windowController = controller
        DispatchQueue.main.async {
            self.presentMainWindow()
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        let themes = NSMenu(title: "主题")
        for theme in AppTheme.allCases {
            let item = NSMenuItem(
                title: theme.title,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            item.image = theme.menuSwatch
            themes.addItem(item)
        }
        themeItem.submenu = themes
        themeMenu = themes
        applicationMenu.addItem(themeItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "清空剪贴板记录…",
            action: #selector(confirmClearHistory),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "退出 clib",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu

        let clipboardItem = NSMenuItem()
        mainMenu.addItem(clipboardItem)
        let clipboardMenu = NSMenu(title: "剪贴板")
        clipboardMenu.addItem(
            withTitle: "搜索",
            action: #selector(focusSearch),
            keyEquivalent: "f"
        )
        clipboardMenu.addItem(
            withTitle: "筛选类型",
            action: #selector(openFilter),
            keyEquivalent: "d"
        )
        clipboardItem.submenu = clipboardMenu
        NSApp.mainMenu = mainMenu
        updateThemeMenuState()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = AppTheme(rawValue: raw) else { return }
        AppTheme.current = theme
        updateThemeMenuState()
        NotificationCenter.default.post(name: .appThemeDidChange, object: theme)
    }

    private func updateThemeMenuState() {
        let selected = AppTheme.current
        themeMenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == selected.rawValue ? .on : .off
        }
    }

    @objc private func confirmClearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清空所有剪贴板记录？"
        alert.informativeText = "此操作会删除全部历史记录，且无法撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        alert.buttons[1].keyEquivalent = "\u{1b}"

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        windowController?.contentController.clearHistory()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "打开 clib"
            )
            button.image?.isTemplate = true
            button.toolTip = "打开 clib"
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmost
        }
        presentMainWindow()
        NotificationCenter.default.post(name: .clipboardPickerDidOpen, object: nil)
    }

    @objc private func focusSearch() {
        NotificationCenter.default.post(name: .focusClipboardSearch, object: nil)
    }

    @objc private func openFilter() {
        NotificationCenter.default.post(name: .openItemTypeFilterMenu, object: nil)
    }

    private func checkAccessibilityPermissions() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func setupGlobalHotkeyListener() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.modifierFlags.contains([.command, .option]),
                  event.keyCode == kVK_ANSI_V else { return }
            DispatchQueue.main.async { self?.showClipboardPicker() }
        }
    }

    private func showClipboardPicker() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmost
        }
        presentMainWindow()
        NotificationCenter.default.post(name: .clipboardPickerDidOpen, object: nil)
    }

    private func presentMainWindow() {
        guard let windowController, let window = windowController.window else {
            return
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentMainWindow()
        return true
    }

    @objc func togglePin() {
        isPinned.toggle()
        windowController?.window?.level = isPinned ? .floating : .normal
        windowController?.contentController.updatePinState(isPinned)
    }

    func pasteIntoPreviouslyActiveApplication(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.type == .image,
           let data = item.imageData,
           let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(item.content, forType: .string)
        }

        guard AXIsProcessTrusted(), let target = previouslyActiveApplication else {
            NSSound.beep()
            return
        }
        NSApp.hide(nil)
        target.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            )
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

private extension AppTheme {
    var menuSwatch: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.accentColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

final class ClipboardWindowController: NSWindowController {
    let contentController: ItemListViewController

    init(appDelegate: AppDelegate) {
        contentController = ItemListViewController(appDelegate: appDelegate)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = contentController
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.minSize = NSSize(width: 380, height: 300)
        window.contentMinSize = NSSize(width: 380, height: 268)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.styleMask.insert(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        window.setContentSize(NSSize(width: 520, height: 620))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
