import AppKit

extension Notification.Name {
    static let clipboardPrivacySettingsDidChange = Notification.Name(
        "clipboardPrivacySettingsDidChange"
    )
}

struct ExcludedApplication: Codable, Equatable, Hashable {
    let bundleIdentifier: String
    let name: String
}

enum ClipboardRetentionPeriod: Int, CaseIterable {
    case forever = 0
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var title: String {
        switch self {
        case .forever: L10n.text("retention.forever")
        case .sevenDays: L10n.text("retention.7_days")
        case .thirtyDays: L10n.text("retention.30_days")
        case .ninetyDays: L10n.text("retention.90_days")
        }
    }

    func cutoffDate(relativeTo date: Date = Date()) -> Date? {
        guard rawValue > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -rawValue, to: date)
    }
}

struct ClipboardPrivacySettings: Equatable {
    let isMonitoringPaused: Bool
    let ignoresSensitiveContent: Bool
    let retentionPeriod: ClipboardRetentionPeriod
    let excludedApplications: [ExcludedApplication]

    func excludes(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }
}

final class ClipboardPrivacySettingsStore {
    private enum Key {
        static let paused = "clipboardPrivacy.monitoringPaused"
        static let ignoreSensitive = "clipboardPrivacy.ignoreSensitive"
        static let retentionDays = "clipboardPrivacy.retentionDays"
        static let excludedApplications = "clipboardPrivacy.excludedApplications"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.paused: false,
            Key.ignoreSensitive: true,
            Key.retentionDays: ClipboardRetentionPeriod.forever.rawValue
        ])
    }

    var settings: ClipboardPrivacySettings {
        let retention = ClipboardRetentionPeriod(
            rawValue: defaults.integer(forKey: Key.retentionDays)
        ) ?? .forever
        return ClipboardPrivacySettings(
            isMonitoringPaused: defaults.bool(forKey: Key.paused),
            ignoresSensitiveContent: defaults.bool(forKey: Key.ignoreSensitive),
            retentionPeriod: retention,
            excludedApplications: excludedApplications
        )
    }

    var excludedApplications: [ExcludedApplication] {
        guard let data = defaults.data(forKey: Key.excludedApplications),
              let applications = try? decoder.decode(
                [ExcludedApplication].self,
                from: data
              ) else {
            return []
        }
        return applications.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func setMonitoringPaused(_ paused: Bool) {
        defaults.set(paused, forKey: Key.paused)
        notifyChange()
    }

    func setIgnoresSensitiveContent(_ ignores: Bool) {
        defaults.set(ignores, forKey: Key.ignoreSensitive)
        notifyChange()
    }

    func setRetentionPeriod(_ period: ClipboardRetentionPeriod) {
        defaults.set(period.rawValue, forKey: Key.retentionDays)
        notifyChange()
    }

    func addExcludedApplication(_ application: ExcludedApplication) {
        var applications = excludedApplications.filter {
            $0.bundleIdentifier != application.bundleIdentifier
        }
        applications.append(application)
        saveExcludedApplications(applications)
    }

    func removeExcludedApplication(bundleIdentifier: String) {
        saveExcludedApplications(
            excludedApplications.filter {
                $0.bundleIdentifier != bundleIdentifier
            }
        )
    }

    private func saveExcludedApplications(_ applications: [ExcludedApplication]) {
        if let data = try? encoder.encode(applications) {
            defaults.set(data, forKey: Key.excludedApplications)
        }
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(
            name: .clipboardPrivacySettingsDidChange,
            object: self
        )
    }
}

struct ClipboardSnapshot {
    let content: String
    let type: ItemType
    let imageData: Data?
    let pasteboardItems: [ClipboardPayloadItem]
    let containsSensitiveMarker: Bool

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot? {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let typeIdentifiers = pasteboardItems.flatMap {
            $0.types.map(\.rawValue)
        }
        let hasSensitiveMarker = typeIdentifiers.contains {
            SensitiveContentDetector.isControlTypeSensitive($0)
        }

        var remainingBytes = 32 * 1_024 * 1_024
        let payloadItems = pasteboardItems.compactMap { pasteboardItem in
            var representations: [ClipboardRepresentation] = []
            for type in pasteboardItem.types {
                guard !SensitiveContentDetector.shouldOmitRepresentation(
                    type.rawValue
                ),
                let data = pasteboardItem.data(forType: type),
                data.count <= 12 * 1_024 * 1_024,
                data.count <= remainingBytes else {
                    continue
                }
                representations.append(
                    ClipboardRepresentation(
                        typeIdentifier: type.rawValue,
                        data: data
                    )
                )
                remainingBytes -= data.count
            }
            return representations.isEmpty
                ? nil
                : ClipboardPayloadItem(representations: representations)
        }

        if let imageType = pasteboard.availableType(from: [.png, .tiff]),
           let imageData = pasteboard.data(forType: imageType) {
            return ClipboardSnapshot(
                content: "",
                type: .image,
                imageData: imageData,
                pasteboardItems: payloadItems,
                containsSensitiveMarker: hasSensitiveMarker
            )
        }

        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else {
            return nil
        }
        return ClipboardSnapshot(
            content: content,
            type: Self.isWebURL(content) ? .url : .text,
            imageData: nil,
            pasteboardItems: payloadItems,
            containsSensitiveMarker: hasSensitiveMarker
        )
    }

    func makeItem(sourceApplication: NSRunningApplication?) -> Item {
        Item(
            content: content,
            type: type,
            imageData: imageData,
            pasteboardItems: pasteboardItems,
            sourceAppBundleIdentifier: sourceApplication?.bundleIdentifier,
            sourceAppName: sourceApplication?.localizedName
        )
    }

    private static func isWebURL(_ content: String) -> Bool {
        guard let url = URL(string: content),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

enum ClipboardPasteMode {
    case original
    case plainText
}

enum ClipboardPasteboardWriter {
    static func write(
        _ item: Item,
        to pasteboard: NSPasteboard,
        mode: ClipboardPasteMode
    ) {
        pasteboard.clearContents()

        if mode == .original, writeOriginalPayload(of: item, to: pasteboard) {
            return
        }
        if item.type == .image,
           let data = item.imageData,
           let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(item.content, forType: .string)
        }
    }

    @discardableResult
    private static func writeOriginalPayload(
        of item: Item,
        to pasteboard: NSPasteboard
    ) -> Bool {
        let writableItems: [NSPasteboardItem] = item.pasteboardItems.compactMap {
            payloadItem in
            let pasteboardItem = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in payloadItem.representations {
                let type = NSPasteboard.PasteboardType(
                    representation.typeIdentifier
                )
                wroteRepresentation =
                    pasteboardItem.setData(representation.data, forType: type) ||
                    wroteRepresentation
            }
            return wroteRepresentation ? pasteboardItem : nil
        }
        guard !writableItems.isEmpty else { return false }
        return pasteboard.writeObjects(writableItems)
    }
}

enum SensitiveContentDetector {
    private static let secretPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            options: [.caseInsensitive]
        ),
        try! NSRegularExpression(
            pattern: #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#
        ),
        try! NSRegularExpression(
            pattern: #"\bgh[pousr]_[A-Za-z0-9]{30,}\b"#
        ),
        try! NSRegularExpression(
            pattern: #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#
        ),
        try! NSRegularExpression(
            pattern: #"\bsk-[A-Za-z0-9_-]{20,}\b"#
        )
    ]

    static func isSensitive(_ snapshot: ClipboardSnapshot) -> Bool {
        if snapshot.containsSensitiveMarker { return true }
        let range = NSRange(
            snapshot.content.startIndex..<snapshot.content.endIndex,
            in: snapshot.content
        )
        return secretPatterns.contains {
            $0.firstMatch(in: snapshot.content, range: range) != nil
        }
    }

    static func isControlTypeSensitive(_ typeIdentifier: String) -> Bool {
        let value = typeIdentifier.lowercased()
        return value.contains("concealedtype") ||
            value.contains("transienttype")
    }

    static func shouldOmitRepresentation(_ typeIdentifier: String) -> Bool {
        let value = typeIdentifier.lowercased()
        return isControlTypeSensitive(typeIdentifier) ||
            value.contains("autogeneratedtype")
    }
}
