//
//  ClipboardViewModel.swift
//  clib
//
//  Created by DP on 2024/5/31.
//

import SwiftUI
import Combine
import AppKit

class ClipboardViewModel: ObservableObject {
    @Published var itemList = ItemList()
    
    private var clipboardTimer: Timer?
    private var previousContent: String = ""
    

    init() {
        // Initialize clipboard content
        updateClipboardContent()
        
        // Set up the timer to poll clipboard every second
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClipboardContent()
        }
    }

    deinit {
        clipboardTimer?.invalidate()
    }

    private func updateClipboardContent() {
        if let content = NSPasteboard.general.string(forType: .string) {
            if(content != self.itemList.peek().content){
                itemList.push(content: content, type: ItemType.text)
            }
        } else {
            // noop
        }
    }
}
