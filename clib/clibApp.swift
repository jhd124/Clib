import SwiftUI
import SwiftData
import Carbon

extension Notification.Name {
    static let clipboardPickerDidOpen = Notification.Name("clipboardPickerDidOpen")
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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var isPinned = false

    private var eventMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibilityPermissions()
        setupGlobalHotkeyListener()
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
        window.isMovableByWindowBackground = true
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

    func pasteIntoPreviouslyActiveApplication(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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
    }
}
