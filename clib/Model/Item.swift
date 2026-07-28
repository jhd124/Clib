//
//  Task_swift.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import Foundation

struct Item: Identifiable, Equatable, Codable {
    static let favoriteTag = "收藏"

    let id: UUID
    let content: String
    let type: ItemType
    let imageData: Data?
    let createdAt: Date
    let deletedAt: Date?
    let tags: [String]
    
    init(
        id: UUID = UUID(),
        content: String,
        type: ItemType,
        imageData: Data? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.imageData = imageData
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.tags = Self.normalized(tags)
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
            deletedAt: deletedAt,
            tags: tags
        )
    }

    func promoted() -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: Date(),
            tags: tags
        )
    }

    func replacingTags(_ tags: [String]) -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: createdAt,
            deletedAt: deletedAt,
            tags: tags
        )
    }

    func togglingTag(_ tag: String) -> Item {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return self }
        var updatedTags = tags
        if let index = updatedTags.firstIndex(of: normalizedTag) {
            updatedTags.remove(at: index)
        } else {
            updatedTags.append(normalizedTag)
        }
        return replacingTags(updatedTags)
    }

    func tombstone() -> Item {
        Item(
            id: id,
            content: "",
            type: type,
            imageData: nil,
            createdAt: createdAt,
            deletedAt: Date(),
            tags: tags
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

    private enum CodingKeys: String, CodingKey {
        case id, content, type, imageData, createdAt, deletedAt, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            content: try container.decode(String.self, forKey: .content),
            type: try container.decode(ItemType.self, forKey: .type),
            imageData: try container.decodeIfPresent(Data.self, forKey: .imageData),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
    }

    private static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag).inserted ? tag : nil
        }
    }
}
