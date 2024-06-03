//
//  ClipboardViewModel.swift
//  clib
//
//  Created by DP on 2024/5/19.
//

import SwiftUI
import Combine

class ClipboardViewModel: ObservableObject {
    @Published var clipboardText: String = "No text found in clipboard"
    private var cancellable: AnyCancellable?

    init() {
        readClipboard()
        startListeningForClipboardChanges()
    }

    private func readClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            clipboardText = text
        } else {
            clipboardText = "No text found in clipboard"
        }
    }

    private func startListeningForClipboardChanges() {
        let pasteboard = NSPasteboard.general
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if let lastChangeCount = UserDefaults.standard.value(forKey: "lastChangeCount") as? Int,
                   lastChangeCount != pasteboard.changeCount {
                    self.readClipboard()
                    UserDefaults.standard.setValue(pasteboard.changeCount, forKey: "lastChangeCount")
                } else if UserDefaults.standard.value(forKey: "lastChangeCount") == nil {
                    UserDefaults.standard.setValue(pasteboard.changeCount, forKey: "lastChangeCount")
                }
            }
    }
}
