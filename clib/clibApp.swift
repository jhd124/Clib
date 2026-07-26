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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var eventMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibilityPermissions()
        setupGlobalHotkeyListener()
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            print("需要辅助功能权限")
        }
    }

    private func setupGlobalHotkeyListener() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]),
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
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .clipboardPickerDidOpen, object: nil)
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
