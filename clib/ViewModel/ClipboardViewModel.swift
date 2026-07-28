import AppKit

/// Storage is intentionally append-oriented: a remote implementation can later
/// upload each new item without changing ClipboardViewModel.
protocol ClipboardHistoryStore {
    func load() throws -> [Item]
    func append(_ item: Item) throws
    func flush() throws
}

/// Stores one JSON object per line. A partially written final line caused by a
/// crash is ignored on the next launch; all earlier entries remain readable.
final class LocalClipboardHistoryStore: ClipboardHistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [Item] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decodedItems = data
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(Item.self, from: Data($0)) }
            .reversed()

        // Editing appends a new revision with the same ID. Keep only its latest
        // revision while retaining the crash-safe append-only file format.
        var seenIDs = Set<Item.ID>()
        return decodedItems
            .filter { seenIDs.insert($0.id).inserted }
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ item: Item) throws {
        try prepareFileIfNeeded()

        var data = try encoder.encode(item)
        data.append(UInt8(ascii: "\n"))

        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func flush() throws {
        // append(_:) synchronizes every item, so the local store has no pending data.
    }

    private func prepareFileIfNeeded() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("clib", isDirectory: true)
            .appendingPathComponent("clipboard-history.jsonl")
    }
}

final class ClipboardViewModel {
    private(set) var itemList: ItemList {
        didSet {
            onChange?(itemList.list)
        }
    }
    var onChange: (([Item]) -> Void)?

    private let store: ClipboardHistoryStore
    private var clipboardTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var lastPasteboardChangeCount = -1

    init(
        store: ClipboardHistoryStore = LocalClipboardHistoryStore(),
        startMonitoring: Bool = true
    ) {
        self.store = store

        do {
            itemList = ItemList(list: try store.load())
        } catch {
            itemList = ItemList()
            print("读取剪贴板历史失败：\(error)")
        }

        if startMonitoring {
            updateClipboardContent()
            clipboardTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                self?.updateClipboardContent()
            }

            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.flushStore()
            }
        }
    }

    deinit {
        clipboardTimer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        flushStore()
    }

    private func updateClipboardContent() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else {
            return
        }
        lastPasteboardChangeCount = pasteboard.changeCount

        let item: Item
        if let imageType = pasteboard.availableType(from: [.png, .tiff]),
           let imageData = pasteboard.data(forType: imageType) {
            let candidate = Item(content: "", type: .image, imageData: imageData)
            if let existingItem = itemList.list.first(where: {
                $0.hasSamePayload(as: candidate)
            }) {
                guard itemList.peek()?.id != existingItem.id else { return }
                promote(existingItem)
                return
            }
            item = itemList.push(imageData: imageData)
        } else if let content = pasteboard.string(forType: .string),
                  !content.isEmpty {
            let type: ItemType = isWebURL(content) ? .url : .text
            let candidate = Item(content: content, type: type)
            if let existingItem = itemList.list.first(where: {
                $0.hasSamePayload(as: candidate)
            }) {
                guard itemList.peek()?.id != existingItem.id else { return }
                promote(existingItem)
                return
            }
            item = itemList.push(content: content, type: type)
        } else {
            return
        }

        do {
            try store.append(item)
        } catch {
            print("保存剪贴板内容失败：\(error)")
        }
    }

    func promote(_ item: Item) {
        let matchingItems = itemList.list.filter {
            $0.hasSamePayload(as: item)
        }
        guard !matchingItems.isEmpty else { return }

        let promotedItem = item.promoted()
        itemList.list.removeAll { candidate in
            candidate.hasSamePayload(as: item)
        }
        itemList.list.insert(promotedItem, at: 0)

        do {
            for duplicate in matchingItems where duplicate.id != item.id {
                try store.append(duplicate.tombstone())
            }
            try store.append(promotedItem)
        } catch {
            print("更新剪贴板条目顺序失败：\(error)")
        }
    }

    func delete(_ item: Item) {
        itemList.list.removeAll { $0.id == item.id }
        do {
            try store.append(item.tombstone())
        } catch {
            print("删除剪贴板条目失败：\(error)")
        }
    }

    private func isWebURL(_ content: String) -> Bool {
        guard let url = URL(string: content),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    func updateContent(of item: Item, to content: String) {
        guard item.type != .image,
              item.type != .video,
              item.type != .audio else {
            return
        }

        let updatedType: ItemType
        if item.type == .code {
            updatedType = .code
        } else {
            updatedType = isWebURL(content) ? .url : .text
        }
        let updatedItem = item.replacingContent(content, type: updatedType)
        itemList.replace(updatedItem)

        do {
            try store.append(updatedItem)
        } catch {
            print("保存条目修改失败：\(error)")
        }
    }

    func toggleTag(_ tag: String, on item: Item) {
        let updatedItem = item.togglingTag(tag)
        guard updatedItem.tags != item.tags else { return }
        itemList.replace(updatedItem)

        do {
            try store.append(updatedItem)
        } catch {
            print("保存条目标签失败：\(error)")
        }
    }

    private func flushStore() {
        do {
            try store.flush()
        } catch {
            print("刷新剪贴板存储失败：\(error)")
        }
    }
}
