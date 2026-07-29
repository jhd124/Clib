//
//  Task_swift.swift
//  clib
//
//  Created by DP on 2024/5/26.
//

import Foundation

struct ClipboardRepresentation: Codable, Equatable {
    let typeIdentifier: String
    let data: Data
}

struct ClipboardPayloadItem: Codable, Equatable {
    let representations: [ClipboardRepresentation]
}

struct Item: Identifiable, Equatable, Codable {
    static let favoriteTag = "收藏"

    let id: UUID
    let content: String
    let type: ItemType
    let imageData: Data?
    let createdAt: Date
    let deletedAt: Date?
    let tags: [String]
    let pasteboardItems: [ClipboardPayloadItem]
    let sourceAppBundleIdentifier: String?
    let sourceAppName: String?
    let recognizedText: String
    let qrCodePayloads: [String]
    let imageAnalysisCompleted: Bool
    
    init(
        id: UUID = UUID(),
        content: String,
        type: ItemType,
        imageData: Data? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil,
        tags: [String] = [],
        pasteboardItems: [ClipboardPayloadItem] = [],
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil,
        recognizedText: String = "",
        qrCodePayloads: [String] = [],
        imageAnalysisCompleted: Bool = false
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.imageData = imageData
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.tags = Self.normalized(tags)
        self.pasteboardItems = pasteboardItems
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.recognizedText = recognizedText
        self.qrCodePayloads = Self.normalized(qrCodePayloads)
        self.imageAnalysisCompleted = imageAnalysisCompleted
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
            tags: tags,
            pasteboardItems: Self.plainTextPayload(content),
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName,
            recognizedText: recognizedText,
            qrCodePayloads: qrCodePayloads,
            imageAnalysisCompleted: imageAnalysisCompleted
        )
    }

    func promoted() -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: Date(),
            tags: tags,
            pasteboardItems: pasteboardItems,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName,
            recognizedText: recognizedText,
            qrCodePayloads: qrCodePayloads,
            imageAnalysisCompleted: imageAnalysisCompleted
        )
    }

    func recaptured(from candidate: Item) -> Item {
        let canReuseAnalysis =
            imageData == candidate.imageData && imageAnalysisCompleted
        return Item(
            id: id,
            content: candidate.content,
            type: candidate.type,
            imageData: candidate.imageData,
            createdAt: Date(),
            tags: tags,
            pasteboardItems: candidate.pasteboardItems,
            sourceAppBundleIdentifier: candidate.sourceAppBundleIdentifier,
            sourceAppName: candidate.sourceAppName,
            recognizedText: canReuseAnalysis
                ? recognizedText
                : candidate.recognizedText,
            qrCodePayloads: canReuseAnalysis
                ? qrCodePayloads
                : candidate.qrCodePayloads,
            imageAnalysisCompleted: canReuseAnalysis ||
                candidate.imageAnalysisCompleted
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
            tags: tags,
            pasteboardItems: pasteboardItems,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName,
            recognizedText: recognizedText,
            qrCodePayloads: qrCodePayloads,
            imageAnalysisCompleted: imageAnalysisCompleted
        )
    }

    func replacingImageAnalysis(with result: ImageRecognitionResult) -> Item {
        Item(
            id: id,
            content: content,
            type: type,
            imageData: imageData,
            createdAt: createdAt,
            deletedAt: deletedAt,
            tags: tags,
            pasteboardItems: pasteboardItems,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName,
            recognizedText: result.text,
            qrCodePayloads: result.qrCodes,
            imageAnalysisCompleted: true
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
            tags: tags,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            sourceAppName: sourceAppName
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
        case pasteboardItems, sourceAppBundleIdentifier, sourceAppName
        case recognizedText, qrCodePayloads, imageAnalysisCompleted
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
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            pasteboardItems: try container.decodeIfPresent(
                [ClipboardPayloadItem].self,
                forKey: .pasteboardItems
            ) ?? [],
            sourceAppBundleIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .sourceAppBundleIdentifier
            ),
            sourceAppName: try container.decodeIfPresent(
                String.self,
                forKey: .sourceAppName
            ),
            recognizedText: try container.decodeIfPresent(
                String.self,
                forKey: .recognizedText
            ) ?? "",
            qrCodePayloads: try container.decodeIfPresent(
                [String].self,
                forKey: .qrCodePayloads
            ) ?? [],
            imageAnalysisCompleted: try container.decodeIfPresent(
                Bool.self,
                forKey: .imageAnalysisCompleted
            ) ?? false
        )
    }

    private static func plainTextPayload(_ content: String) -> [ClipboardPayloadItem] {
        guard let data = content.data(using: .utf8) else { return [] }
        return [
            ClipboardPayloadItem(
                representations: [
                    ClipboardRepresentation(
                        typeIdentifier: "public.utf8-plain-text",
                        data: data
                    )
                ]
            )
        ]
    }

    private static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag).inserted ? tag : nil
        }
    }
}
