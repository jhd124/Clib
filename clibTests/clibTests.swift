import XCTest
@testable import clib

final class ItemListTests: XCTestCase {
    func testPushAddsNewestItemAtFront() {
        let existing = Item(content: "old", type: .text)
        var list = ItemList(list: [existing])

        let inserted = list.push(content: "new", type: .text)

        XCTAssertEqual(list.list.map(\.id), [inserted.id, existing.id])
        XCTAssertEqual(list.peek()?.content, "new")
    }

    func testReplacePreservesPositionAndUpdatesContent() {
        let first = Item(content: "first", type: .text)
        let second = Item(content: "second", type: .text)
        var list = ItemList(list: [first, second])
        let updated = second.replacingContent("https://example.com", type: .url)

        list.replace(updated)

        XCTAssertEqual(list.list.map(\.id), [first.id, second.id])
        XCTAssertEqual(list.list[1].content, "https://example.com")
        XCTAssertEqual(list.list[1].type, .url)
    }

    func testImageItemsCompareTheirBinaryPayload() {
        let first = Item(content: "", type: .image, imageData: Data([1, 2, 3]))
        let same = Item(content: "", type: .image, imageData: Data([1, 2, 3]))
        let different = Item(content: "", type: .image, imageData: Data([3, 2, 1]))

        XCTAssertTrue(first.hasSamePayload(as: same))
        XCTAssertFalse(first.hasSamePayload(as: different))
    }
}

final class LocalClipboardHistoryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var historyURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clib-tests-\(UUID().uuidString)", isDirectory: true)
        historyURL = temporaryDirectory.appendingPathComponent("history.jsonl")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testAppendAndLoadReturnsNewestFirst() throws {
        let store = LocalClipboardHistoryStore(fileURL: historyURL)
        let older = Item(
            content: "older",
            type: .text,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newer = Item(
            content: "newer",
            type: .text,
            createdAt: Date(timeIntervalSince1970: 20)
        )

        try store.append(older)
        try store.append(newer)

        XCTAssertEqual(try store.load().map(\.id), [newer.id, older.id])
    }

    func testLatestRevisionWinsWithoutChangingIdentity() throws {
        let store = LocalClipboardHistoryStore(fileURL: historyURL)
        let original = Item(
            content: "before",
            type: .text,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let updated = original.replacingContent("after", type: .text)

        try store.append(original)
        try store.append(updated)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, original.id)
        XCTAssertEqual(loaded[0].content, "after")
    }

    func testTombstoneRemovesItemAfterReload() throws {
        let store = LocalClipboardHistoryStore(fileURL: historyURL)
        let item = Item(content: "delete me", type: .text)

        try store.append(item)
        try store.append(item.tombstone())

        XCTAssertTrue(try store.load().isEmpty)
    }

    func testIncompleteFinalLineIsIgnored() throws {
        let store = LocalClipboardHistoryStore(fileURL: historyURL)
        let valid = Item(content: "survives", type: .text)
        try store.append(valid)

        let handle = try FileHandle(forWritingTo: historyURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
        try handle.close()

        XCTAssertEqual(try store.load().map(\.id), [valid.id])
    }
}

final class ClipboardViewModelTests: XCTestCase {
    func testPromoteMovesSelectedItemToFrontAndRemovesDuplicates() {
        let duplicateA = Item(content: "same", type: .text)
        let other = Item(content: "other", type: .text)
        let duplicateB = Item(content: "same", type: .text)
        let store = MemoryClipboardHistoryStore(
            initialItems: [duplicateA, other, duplicateB]
        )
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.promote(duplicateB)

        XCTAssertEqual(viewModel.itemList.list.first?.id, duplicateB.id)
        XCTAssertEqual(
            viewModel.itemList.list.filter { $0.content == "same" }.count,
            1
        )
        XCTAssertTrue(
            store.appendedItems.contains {
                $0.id == duplicateA.id && $0.deletedAt != nil
            }
        )
        XCTAssertEqual(store.appendedItems.last?.id, duplicateB.id)
    }

    func testDeleteRemovesItemAndPersistsTombstone() {
        let item = Item(content: "delete", type: .text)
        let store = MemoryClipboardHistoryStore(initialItems: [item])
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.delete(item)

        XCTAssertTrue(viewModel.itemList.list.isEmpty)
        XCTAssertEqual(store.appendedItems.last?.id, item.id)
        XCTAssertNotNil(store.appendedItems.last?.deletedAt)
    }

    func testEditingTextIntoURLReclassifiesAndPersistsIt() {
        let item = Item(content: "example", type: .text)
        let store = MemoryClipboardHistoryStore(initialItems: [item])
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.updateContent(of: item, to: "https://example.com/path")

        XCTAssertEqual(viewModel.itemList.list[0].id, item.id)
        XCTAssertEqual(viewModel.itemList.list[0].type, .url)
        XCTAssertEqual(store.appendedItems.last?.type, .url)
    }

    func testMediaItemsCannotBeEdited() {
        let image = Item(content: "", type: .image, imageData: Data([1]))
        let store = MemoryClipboardHistoryStore(initialItems: [image])
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.updateContent(of: image, to: "not allowed")

        XCTAssertEqual(viewModel.itemList.list[0].type, .image)
        XCTAssertTrue(store.appendedItems.isEmpty)
    }
}

final class TextTransformerTests: XCTestCase {
    func testBase64RoundTripSupportsUnicode() throws {
        let source = "剪贴板 Hello 👋"

        let encoded = try TextTransformer.transform(source, using: .base64Encode)
        let decoded = try TextTransformer.transform(encoded, using: .base64Decode)

        XCTAssertEqual(decoded, source)
    }

    func testInvalidUTF8Base64Throws() {
        XCTAssertThrowsError(
            try TextTransformer.transform("////", using: .base64Decode)
        )
    }

    func testFormatAndCompressJSON() throws {
        let source = #"{"b":2,"a":{"value":1}}"#

        let formatted = try TextTransformer.transform(source, using: .formatJSON)
        let compressed = try TextTransformer.transform(source, using: .compressJSON)

        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertEqual(compressed, #"{"a":{"value":1},"b":2}"#)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(
            try TextTransformer.transform("{invalid}", using: .formatJSON)
        )
    }

    func testRecursivelyParsesNestedURLParameters() throws {
        let source =
            "https://example.com/callback?next=" +
            "https%3A%2F%2Fnested.example%2Fpath%3Ftoken%3Dabc"

        let result = try TextTransformer.transform(source, using: .parseURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )
        let parameters = try XCTUnwrap(object["parameters"] as? [String: Any])
        let nested = try XCTUnwrap(parameters["next"] as? [String: Any])
        let nestedParameters = try XCTUnwrap(
            nested["parameters"] as? [String: Any]
        )

        XCTAssertEqual(object["host"] as? String, "example.com")
        XCTAssertEqual(nested["host"] as? String, "nested.example")
        XCTAssertEqual(nestedParameters["token"] as? String, "abc")
    }
}

final class SearchDestinationResolverTests: XCTestCase {
    func testHTTPURLIsOpenedDirectly() {
        XCTAssertEqual(
            SearchDestinationResolver.destination(
                for: " https://example.com/path?q=1 "
            )?.absoluteString,
            "https://example.com/path?q=1"
        )
    }

    func testPlainTextBecomesGoogleQuery() throws {
        let url = try XCTUnwrap(
            SearchDestinationResolver.destination(for: "Swift 剪贴板")
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "q" })?.value,
            "Swift 剪贴板"
        )
    }

    func testBlankSearchHasNoDestination() {
        XCTAssertNil(SearchDestinationResolver.destination(for: " \n "))
    }
}

private final class MemoryClipboardHistoryStore: ClipboardHistoryStore {
    let initialItems: [Item]
    private(set) var appendedItems: [Item] = []
    private(set) var flushCount = 0

    init(initialItems: [Item]) {
        self.initialItems = initialItems
    }

    func load() throws -> [Item] {
        initialItems
    }

    func append(_ item: Item) throws {
        appendedItems.append(item)
    }

    func flush() throws {
        flushCount += 1
    }
}
