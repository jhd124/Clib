//
//  Task_swift.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import Foundation

struct Item: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let type: ItemType
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        content: String,
        type: ItemType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.createdAt = createdAt
    }
    
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs.type == rhs.type && lhs.content == rhs.content
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
