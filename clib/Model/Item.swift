//
//  Task_swift.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import Foundation

struct Item: Identifiable {
    let id = UUID()
    let content: String
    let type: ItemType
    
    init(content: String, type: ItemType){
        self.content = content
        self.type = type
    }
    
    static func example() -> Item {
        Item(content: "This is what you copyed", type: ItemType.text)
    }
    
    static func examples() -> [Item] {
        [
            Item(content: "This is what you copyed", type: ItemType.text)
        ]
    }
}
