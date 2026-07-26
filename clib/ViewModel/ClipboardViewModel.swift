import SwiftUI
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
        return data
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(Item.self, from: Data($0)) }
            .reversed()
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

final class ClipboardViewModel: ObservableObject {
    @Published var itemList: ItemList

    private let store: ClipboardHistoryStore
    private var clipboardTimer: Timer?
    private var terminationObserver: NSObjectProtocol?

    init(store: ClipboardHistoryStore = LocalClipboardHistoryStore()) {
        self.store = store

        do {
            itemList = ItemList(list: try store.load())
        } catch {
            itemList = ItemList()
            print("读取剪贴板历史失败：\(error)")
        }

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

    deinit {
        clipboardTimer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        flushStore()
    }

    private func updateClipboardContent() {
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.isEmpty,
              content != itemList.peek()?.content else {
            return
        }

        let item = itemList.push(content: content, type: .text)
        do {
            try store.append(item)
        } catch {
            print("保存剪贴板内容失败：\(error)")
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
