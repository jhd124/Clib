import XCTest
import AppKit
import CoreImage
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

    func testTagsAreNormalizedAndCanBeToggled() {
        let item = Item(content: "tagged", type: .text, tags: [" 工作 ", "工作", ""])

        XCTAssertEqual(item.tags, ["工作"])
        XCTAssertEqual(item.togglingTag("工作").tags, [])
        XCTAssertEqual(item.togglingTag("收藏").tags, ["工作", "收藏"])
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

    func testDecodesHistoryCreatedBeforeTagsWereAdded() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","content":"legacy","type":"text","createdAt":"1970-01-01T00:00:10Z"}
        """
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try Data((json + "\n").utf8).write(to: historyURL)

        let item = try LocalClipboardHistoryStore(fileURL: historyURL).load().first
        XCTAssertEqual(item?.tags, [])
        XCTAssertEqual(item?.recognizedText, "")
        XCTAssertEqual(item?.qrCodePayloads, [])
        XCTAssertEqual(item?.imageAnalysisCompleted, false)
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

    func testClearHistoryRemovesAllItemsAndPersistsTombstones() {
        let first = Item(content: "first", type: .text)
        let second = Item(content: "second", type: .text)
        let store = MemoryClipboardHistoryStore(initialItems: [first, second])
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.clearHistory()

        XCTAssertTrue(viewModel.itemList.list.isEmpty)
        XCTAssertEqual(Set(store.appendedItems.map(\.id)), Set([first.id, second.id]))
        XCTAssertTrue(store.appendedItems.allSatisfy { $0.deletedAt != nil })
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

    func testToggleTagUpdatesAndPersistsItem() {
        let item = Item(content: "tag me", type: .text)
        let store = MemoryClipboardHistoryStore(initialItems: [item])
        let viewModel = ClipboardViewModel(store: store, startMonitoring: false)

        viewModel.toggleTag("工作", on: item)

        XCTAssertEqual(viewModel.itemList.list[0].tags, ["工作"])
        XCTAssertEqual(store.appendedItems.last?.tags, ["工作"])
    }

    func testRetentionRemovesExpiredItemsButKeepsFavorites() {
        let defaultsName = "ClipboardRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = ClipboardPrivacySettingsStore(defaults: defaults)
        settings.setRetentionPeriod(.sevenDays)

        let oldDate = Calendar.current.date(
            byAdding: .day,
            value: -10,
            to: Date()
        )!
        let expired = Item(
            content: "expired",
            type: .text,
            createdAt: oldDate
        )
        let favorite = Item(
            content: "favorite",
            type: .text,
            createdAt: oldDate,
            tags: [Item.favoriteTag]
        )
        let store = MemoryClipboardHistoryStore(
            initialItems: [expired, favorite]
        )

        let viewModel = ClipboardViewModel(
            store: store,
            privacySettingsStore: settings,
            startMonitoring: false
        )

        XCTAssertEqual(viewModel.itemList.list.map(\.id), [favorite.id])
        XCTAssertEqual(store.appendedItems.count, 1)
        XCTAssertEqual(store.appendedItems.first?.id, expired.id)
        XCTAssertNotNil(store.appendedItems.first?.deletedAt)
    }

    func testUserTriggeredImageAnalysisResultIsStoredAndPersisted() {
        let image = Item(
            content: "",
            type: .image,
            imageData: Data([1, 2, 3])
        )
        let store = MemoryClipboardHistoryStore(initialItems: [image])
        let recognizer = StubImageRecognizer(
            result: ImageRecognitionResult(
                text: "本地 OCR 结果",
                qrCodes: ["https://example.com/from-qr"]
            )
        )
        let viewModel = ClipboardViewModel(
            store: store,
            imageRecognizer: recognizer,
            startMonitoring: false
        )
        let completed = expectation(description: "图片分析结果写入")
        viewModel.onChange = { items in
            if items.first?.imageAnalysisCompleted == true {
                completed.fulfill()
            }
        }

        XCTAssertTrue(viewModel.analyzeImage(image))
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(viewModel.itemList.list.first?.recognizedText, "本地 OCR 结果")
        XCTAssertEqual(
            viewModel.itemList.list.first?.qrCodePayloads,
            ["https://example.com/from-qr"]
        )
        XCTAssertEqual(store.appendedItems.last?.recognizedText, "本地 OCR 结果")
        XCTAssertEqual(recognizer.callCount, 1)
    }

    func testOnlySmallPendingImagesAreRecognizedAutomatically() {
        let smallImage = Item(
            content: "",
            type: .image,
            imageData: Data([1])
        )
        let largeImage = Item(
            content: "",
            type: .image,
            imageData: Data([2])
        )
        let recognizer = StubImageRecognizer(
            result: ImageRecognitionResult(text: "automatic", qrCodes: [])
        )
        let viewModel = ClipboardViewModel(
            store: MemoryClipboardHistoryStore(
                initialItems: [smallImage, largeImage]
            ),
            imageRecognizer: recognizer,
            shouldAutomaticallyRecognizeImage: { $0 == smallImage.imageData },
            startMonitoring: false
        )
        let completed = expectation(description: "小图自动识别完成")
        viewModel.onChange = { items in
            if items.first(where: { $0.id == smallImage.id })?
                .imageAnalysisCompleted == true {
                completed.fulfill()
            }
        }

        viewModel.analyzeEligiblePendingImages()
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(recognizer.callCount, 1)
        XCTAssertEqual(
            viewModel.itemList.list.first {
                $0.id == smallImage.id
            }?.recognizedText,
            "automatic"
        )
        XCTAssertFalse(
            viewModel.itemList.list.first {
                $0.id == largeImage.id
            }?.imageAnalysisCompleted == true
        )
    }

    func testCompletedImageAnalysisIsNotRepeated() {
        let image = Item(
            content: "",
            type: .image,
            imageData: Data([1]),
            recognizedText: "already done",
            imageAnalysisCompleted: true
        )
        let recognizer = StubImageRecognizer(
            result: ImageRecognitionResult(text: "new", qrCodes: [])
        )
        let viewModel = ClipboardViewModel(
            store: MemoryClipboardHistoryStore(initialItems: [image]),
            imageRecognizer: recognizer,
            startMonitoring: false
        )

        XCTAssertFalse(viewModel.analyzeImage(image))

        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertEqual(viewModel.itemList.list.first?.recognizedText, "already done")
    }

    func testCompletedImageCanBeExplicitlyRecognizedAgain() {
        let image = Item(
            content: "",
            type: .image,
            imageData: Data([1]),
            recognizedText: "old",
            imageAnalysisCompleted: true
        )
        let recognizer = StubImageRecognizer(
            result: ImageRecognitionResult(text: "new", qrCodes: [])
        )
        let viewModel = ClipboardViewModel(
            store: MemoryClipboardHistoryStore(initialItems: [image]),
            imageRecognizer: recognizer,
            startMonitoring: false
        )
        let completed = expectation(description: "重新识别结果写入")
        viewModel.onChange = { items in
            if items.first?.recognizedText == "new" {
                completed.fulfill()
            }
        }

        XCTAssertTrue(viewModel.analyzeImage(image, force: true))
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(recognizer.callCount, 1)
        XCTAssertEqual(viewModel.itemList.list.first?.recognizedText, "new")
    }
}

final class ClipboardPrivacyTests: XCTestCase {
    func testDefaultsAreSafeAndNonDestructive() {
        let defaultsName = "ClipboardPrivacyDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let settings = ClipboardPrivacySettingsStore(defaults: defaults).settings

        XCTAssertFalse(settings.isMonitoringPaused)
        XCTAssertTrue(settings.ignoresSensitiveContent)
        XCTAssertEqual(settings.retentionPeriod, .forever)
        XCTAssertTrue(settings.excludedApplications.isEmpty)
    }

    func testExcludedApplicationsAreStoredAndRemoved() {
        let defaultsName = "ClipboardPrivacyApplicationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = ClipboardPrivacySettingsStore(defaults: defaults)
        let application = ExcludedApplication(
            bundleIdentifier: "com.example.secret",
            name: "Secret"
        )

        store.addExcludedApplication(application)
        XCTAssertTrue(
            store.settings.excludes(
                bundleIdentifier: application.bundleIdentifier
            )
        )

        store.removeExcludedApplication(
            bundleIdentifier: application.bundleIdentifier
        )
        XCTAssertFalse(
            store.settings.excludes(
                bundleIdentifier: application.bundleIdentifier
            )
        )
    }

    func testSensitiveDetectorRecognizesSecretsButAllowsJWTDecodeInput() {
        let privateKey = ClipboardSnapshot(
            content: "-----BEGIN PRIVATE KEY-----\nabc",
            type: .text,
            imageData: nil,
            pasteboardItems: [],
            containsSensitiveMarker: false
        )
        let jwt = ClipboardSnapshot(
            content: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature",
            type: .text,
            imageData: nil,
            pasteboardItems: [],
            containsSensitiveMarker: false
        )

        XCTAssertTrue(SensitiveContentDetector.isSensitive(privateKey))
        XCTAssertFalse(SensitiveContentDetector.isSensitive(jwt))
    }
}

final class ClipboardPayloadTests: XCTestCase {
    func testOriginalPastePreservesRichRepresentationsAndPlainPasteStripsThem() throws {
        let source = NSPasteboard(
            name: NSPasteboard.Name("clib-tests-source-\(UUID().uuidString)")
        )
        source.clearContents()
        let sourceItem = NSPasteboardItem()
        sourceItem.setString("formatted", forType: .string)
        let rtf = Data(#"{\rtf1 formatted}"#.utf8)
        sourceItem.setData(rtf, forType: .rtf)
        XCTAssertTrue(source.writeObjects([sourceItem]))
        let snapshot = try XCTUnwrap(ClipboardSnapshot.capture(from: source))
        let item = snapshot.makeItem(sourceApplication: nil)

        let originalDestination = NSPasteboard(
            name: NSPasteboard.Name(
                "clib-tests-original-\(UUID().uuidString)"
            )
        )
        ClipboardPasteboardWriter.write(
            item,
            to: originalDestination,
            mode: .original
        )
        XCTAssertEqual(
            originalDestination.data(forType: .rtf),
            rtf
        )
        XCTAssertEqual(
            originalDestination.string(forType: .string),
            "formatted"
        )

        let plainDestination = NSPasteboard(
            name: NSPasteboard.Name("clib-tests-plain-\(UUID().uuidString)")
        )
        ClipboardPasteboardWriter.write(
            item,
            to: plainDestination,
            mode: .plainText
        )
        XCTAssertEqual(
            plainDestination.string(forType: .string),
            "formatted"
        )
        XCTAssertNil(plainDestination.data(forType: .rtf))
    }
}

final class ClipboardSearchQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testSearchMatchesContentSourceTagsAndStructuredTokens() {
        let item = Item(
            content: "Swift clipboard",
            type: .code,
            createdAt: now.addingTimeInterval(-600),
            tags: ["工作"],
            sourceAppBundleIdentifier: "com.apple.dt.Xcode",
            sourceAppName: "Xcode"
        )

        XCTAssertTrue(ClipboardSearchQuery("clipboard").matches(item, now: now))
        XCTAssertTrue(ClipboardSearchQuery("Xcode").matches(item, now: now))
        XCTAssertTrue(
            ClipboardSearchQuery("app:xcode tag:工作 type:代码 date:1h")
                .matches(item, now: now)
        )
        XCTAssertFalse(
            ClipboardSearchQuery("app:Safari").matches(item, now: now)
        )
    }

    func testSearchMatchesOCRTextAndQRCodePayload() {
        let item = Item(
            content: "",
            type: .image,
            imageData: Data([1]),
            recognizedText: "发票编号 ABC-2026",
            qrCodePayloads: ["https://example.com/order/9527"],
            imageAnalysisCompleted: true
        )

        XCTAssertTrue(ClipboardSearchQuery("ABC-2026").matches(item, now: now))
        XCTAssertTrue(ClipboardSearchQuery("order/9527").matches(item, now: now))
    }
}

final class VisionImageRecognizerTests: XCTestCase {
    func testAutomaticRecognitionPolicyUsesPixelDimensions() throws {
        let color = CIColor(red: 1, green: 1, blue: 1)
        let small = try pngData(
            from: CIImage(color: color).cropped(
                to: CGRect(x: 0, y: 0, width: 800, height: 600)
            )
        )
        let tooWide = try pngData(
            from: CIImage(color: color).cropped(
                to: CGRect(x: 0, y: 0, width: 1_700, height: 200)
            )
        )
        let tooManyPixels = try pngData(
            from: CIImage(color: color).cropped(
                to: CGRect(x: 0, y: 0, width: 1_500, height: 1_500)
            )
        )

        XCTAssertTrue(
            ImageAutoRecognitionPolicy.shouldRecognize(imageData: small)
        )
        XCTAssertFalse(
            ImageAutoRecognitionPolicy.shouldRecognize(imageData: tooWide)
        )
        XCTAssertFalse(
            ImageAutoRecognitionPolicy.shouldRecognize(
                imageData: tooManyPixels
            )
        )
    }

    func testRecognizesGeneratedQRCodeLocally() throws {
        let payload = "https://example.com/clib-qr"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        let output = try XCTUnwrap(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let imageData = try pngData(from: output)
        let completed = expectation(description: "二维码识别完成")
        var result: ImageRecognitionResult?

        VisionImageRecognizer().recognize(imageData: imageData) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)

        XCTAssertEqual(result?.qrCodes, [payload])
    }

    func testRecognizesRenderedTextLocally() throws {
        let image = NSImage(size: NSSize(width: 900, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 900, height: 180)).fill()
        ("HELLO CLIB 2026" as NSString).draw(
            at: NSPoint(x: 28, y: 48),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let completed = expectation(description: "OCR 识别完成")
        var result: ImageRecognitionResult?

        VisionImageRecognizer().recognize(imageData: imageData) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)

        XCTAssertTrue(result?.text.uppercased().contains("CLIB") == true)
    }

    private func pngData(from image: CIImage) throws -> Data {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let cgImage = try XCTUnwrap(
            context.createCGImage(image, from: image.extent)
        )
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
    }
}

final class TextTransformerTests: XCTestCase {
    func testBase64RoundTripSupportsUnicode() throws {
        let source = "剪贴板 Hello 👋"

        let encoded = try TextTransformer.transform(source, using: .base64Encode)
        let decoded = try TextTransformer.transform(encoded, using: .base64Decode)

        XCTAssertEqual(decoded, source)
    }

    func testTransformTrimsLeadingAndTrailingWhitespace() throws {
        let encoded = try TextTransformer.transform(
            "  clipboard value \n",
            using: .base64Encode
        )

        XCTAssertEqual(
            try TextTransformer.transform(encoded, using: .base64Decode),
            "clipboard value"
        )
    }

    func testInvalidUTF8Base64Throws() {
        XCTAssertThrowsError(
            try TextTransformer.transform("////", using: .base64Decode)
        )
    }

    func testJWTDecodeParsesHeaderPayloadAndKeepsSignature() throws {
        let token =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
            "eyJuYW1lIjoi5byg5LiJIiwic3ViIjoiMTIzIn0." +
            "signature"

        let result = try TextTransformer.transform(token, using: .jwtDecode)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )
        let header = try XCTUnwrap(object["header"] as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(header["alg"] as? String, "HS256")
        XCTAssertEqual(payload["sub"] as? String, "123")
        XCTAssertEqual(payload["name"] as? String, "张三")
        XCTAssertEqual(object["signature"] as? String, "signature")
        XCTAssertEqual(object["signatureVerified"] as? Bool, false)
    }

    func testInvalidJWTThrows() {
        XCTAssertThrowsError(
            try TextTransformer.transform("not-a-jwt", using: .jwtDecode)
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
    func testOpenURLSourcesMergeContentAndQRCodeLinks() {
        let item = Item(
            content: " https://example.com/content ",
            type: .image,
            imageData: Data([1]),
            qrCodePayloads: [
                "not a link",
                "https://example.com/qr",
                "https://example.com/content"
            ],
            imageAnalysisCompleted: true
        )

        XCTAssertEqual(
            SearchDestinationResolver.webLinkSources(for: item),
            [
                "https://example.com/content",
                "https://example.com/qr"
            ]
        )
    }

    func testQRCodeOptionsRequireImageWithRecognizedPayload() {
        let textItem = Item(
            content: "text",
            type: .text,
            qrCodePayloads: ["https://example.com/not-valid-for-text"],
            imageAnalysisCompleted: true
        )
        let imageWithoutQRCode = Item(
            content: "",
            type: .image,
            imageData: Data([1]),
            recognizedText: "OCR only",
            imageAnalysisCompleted: true
        )
        let imageWithQRCode = Item(
            content: "",
            type: .image,
            imageData: Data([2]),
            qrCodePayloads: ["qr payload"],
            imageAnalysisCompleted: true
        )

        XCTAssertTrue(
            QRCodeContentResolver.payloads(for: textItem).isEmpty
        )
        XCTAssertTrue(
            QRCodeContentResolver.payloads(for: imageWithoutQRCode).isEmpty
        )
        XCTAssertEqual(
            QRCodeContentResolver.payloads(for: imageWithQRCode),
            ["qr payload"]
        )
    }

    func testOpenURLIgnoresQRCodePayloadsOnNonImageItems() {
        let item = Item(
            content: "plain text",
            type: .text,
            qrCodePayloads: ["https://example.com/ignored"],
            imageAnalysisCompleted: true
        )

        XCTAssertTrue(
            SearchDestinationResolver.webLinkSources(for: item).isEmpty
        )
    }

    func testOpenURLSourcesCanComeOnlyFromQRCode() {
        let item = Item(
            content: "",
            type: .image,
            imageData: Data([1]),
            qrCodePayloads: ["https://example.com/qr-only"],
            imageAnalysisCompleted: true
        )

        XCTAssertEqual(
            SearchDestinationResolver.webLinkSources(for: item),
            ["https://example.com/qr-only"]
        )
    }

    func testWebURLAcceptsHTTPAndHTTPSLinks() {
        XCTAssertEqual(
            SearchDestinationResolver.webURL(for: " https://example.com/path?q=1 ")?
                .absoluteString,
            "https://example.com/path?q=1"
        )
        XCTAssertEqual(
            SearchDestinationResolver.webURL(for: "http://localhost:8080")?
                .absoluteString,
            "http://localhost:8080"
        )
    }

    func testWebURLRejectsPlainTextAndNonWebSchemes() {
        XCTAssertNil(SearchDestinationResolver.webURL(for: "example.com"))
        XCTAssertNil(SearchDestinationResolver.webURL(for: "file:///tmp/example"))
        XCTAssertNil(SearchDestinationResolver.webURL(for: "https://"))
    }

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

final class ShellCommandLauncherTests: XCTestCase {
    func testCreatesExecutableSelfDeletingCommandScript() throws {
        let url = try ShellCommandLauncher.makeScript(for: "printf 'hello'")
        defer { try? FileManager.default.removeItem(at: url) }

        let script = try String(contentsOf: url, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains("rm -f -- \"$0\""))
        XCTAssertTrue(script.contains("printf 'hello'"))
        XCTAssertTrue(script.contains("exec \"${SHELL:-/bin/zsh}\" -l"))
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
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

private final class StubImageRecognizer: ImageRecognizing {
    private let result: ImageRecognitionResult
    private(set) var callCount = 0

    init(result: ImageRecognitionResult) {
        self.result = result
    }

    func recognize(
        imageData: Data,
        completion: @escaping (ImageRecognitionResult) -> Void
    ) {
        callCount += 1
        completion(result)
    }
}
