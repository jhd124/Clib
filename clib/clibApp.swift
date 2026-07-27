import SwiftUI
import SwiftData
import Carbon

extension Notification.Name {
    static let clipboardPickerDidOpen = Notification.Name("clipboardPickerDidOpen")
    static let focusClipboardSearch = Notification.Name("focusClipboardSearch")
    static let openItemTypeFilterMenu = Notification.Name("openItemTypeFilterMenu")
}

@main
struct clibApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ItemListView()
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("剪贴板") {
                Button("搜索") {
                    NotificationCenter.default.post(
                        name: .focusClipboardSearch,
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("筛选类型") {
                    NotificationCenter.default.post(
                        name: .openItemTypeFilterMenu,
                        object: nil
                    )
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var isPinned = false

    private var eventMonitor: Any?
    private var appShortcutMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibilityPermissions()
        setupGlobalHotkeyListener()
        setupAppShortcutListener()
        DispatchQueue.main.async { [weak self] in
            self?.configurePickerWindow()
        }
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            print("需要辅助功能权限")
        }
    }

    private func setupGlobalHotkeyListener() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .option]),
                  event.keyCode == kVK_ANSI_V else {
                return
            }
            DispatchQueue.main.async {
                self?.showClipboardPicker()
            }
        }
    }

    private func setupAppShortcutListener() {
        appShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.isActive else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command),
                  modifiers.intersection([.option, .control]).isEmpty else {
                return event
            }

            switch Int(event.keyCode) {
            case kVK_ANSI_F:
                NotificationCenter.default.post(
                    name: .focusClipboardSearch,
                    object: nil
                )
                return nil
            case kVK_ANSI_D:
                NotificationCenter.default.post(
                    name: .openItemTypeFilterMenu,
                    object: nil
                )
                return nil
            default:
                return event
            }
        }
    }

    private func showClipboardPicker() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        }

        NSApp.activate(ignoringOtherApps: true)
        configurePickerWindow()
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .clipboardPickerDidOpen, object: nil)
    }

    private func configurePickerWindow() {
        guard let window = NSApp.windows.first else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.titled)
        window.isMovableByWindowBackground = false
        window.level = isPinned ? .floating : .normal
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 10
        window.contentView?.layer?.masksToBounds = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    func togglePin() {
        isPinned.toggle()
        NSApp.windows.first?.level = isPinned ? .floating : .normal
    }

    func pasteIntoPreviouslyActiveApplication(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .image:
            guard let imageData = item.imageData,
                  let image = NSImage(data: imageData) else {
                NSSound.beep()
                return
            }
            pasteboard.writeObjects([image])
        default:
            pasteboard.setString(item.content, forType: .string)
        }

        guard AXIsProcessTrusted(), let targetApplication = previouslyActiveApplication else {
            NSSound.beep()
            return
        }

        NSApp.hide(nil)
        targetApplication.activate()

        // Give the target application time to restore its focused control.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            )
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let appShortcutMonitor {
            NSEvent.removeMonitor(appShortcutMonitor)
        }
    }
}
