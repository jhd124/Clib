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
    let imageData: Data?
    let createdAt: Date
    let deletedAt: Date?
    
    init(
        id: UUID = UUID(),
        content: String,
        type: ItemType,
        imageData: Data? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.imageData = imageData
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
    
    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.type == rhs.type &&
        lhs.content == rhs.content &&
        lhs.imageData == rhs.imageData
    }

    func replacingContent(_ content: String, type: ItemType) -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }

    func promoted() -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: Date()
        )
    }

    func tombstone() -> Item {
        Item(
            id: id,
            content: "",
            type: type,
            imageData: nil,
            createdAt: createdAt,
            deletedAt: Date()
        )
    }

    func hasSamePayload(as other: Item) -> Bool {
        type == other.type &&
        content == other.content &&
        imageData == other.imageData
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
