import Foundation
import LumenCore

public struct SparkleAppcastItem: Codable, Equatable, Sendable {
    public let title: String
    public let version: String
    public let shortVersion: String?
    public let downloadURL: String
    public let length: Int?
    public let sparkleVersion: String?
    public let minimumSystemVersion: String?
    public let releaseNotesLink: String?
    public let pubDate: String?
    public let edSignature: String?
    public let dsaSignature: String?

    public init(
        title: String,
        version: String,
        shortVersion: String? = nil,
        downloadURL: String,
        length: Int? = nil,
        sparkleVersion: String? = nil,
        minimumSystemVersion: String? = nil,
        releaseNotesLink: String? = nil,
        pubDate: String? = nil,
        edSignature: String? = nil,
        dsaSignature: String? = nil
    ) {
        self.title = title
        self.version = version
        self.shortVersion = shortVersion
        self.downloadURL = downloadURL
        self.length = length
        self.sparkleVersion = sparkleVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.releaseNotesLink = releaseNotesLink
        self.pubDate = pubDate
        self.edSignature = edSignature
        self.dsaSignature = dsaSignature
    }
}

public struct SparkleAppcast: Codable, Equatable, Sendable {
    public let title: String
    public let items: [SparkleAppcastItem]

    public init(title: String, items: [SparkleAppcastItem]) {
        self.title = title
        self.items = items
    }
}

public enum AppcastImporter {

    public static func parse(xmlData: Data) throws -> SparkleAppcast {
        let parser = AppcastXMLParser(data: xmlData)
        guard let appcast = parser.parse() else {
            throw LumenError.invalidMetadataFormat("Cannot parse Sparkle appcast XML")
        }
        return appcast
    }

    public static func parse(xmlString: String) throws -> SparkleAppcast {
        guard let data = xmlString.data(using: .utf8) else {
            throw LumenError.invalidMetadataFormat("Cannot encode appcast string as UTF-8")
        }
        return try parse(xmlData: data)
    }

    public static func convertToLumenTargets(
        _ appcast: SparkleAppcast,
        productID: String,
        channel: String = "stable"
    ) -> [(path: String, version: Int, shortVersion: String, url: String)] {
        return appcast.items.compactMap { item in
            guard let bundleVersion = Int(item.version) else { return nil }
            let shortVersion = item.shortVersion ?? item.version
            let path = "targets/\(productID)-\(bundleVersion).zip"
            return (path: path, version: bundleVersion, shortVersion: shortVersion, url: item.downloadURL)
        }
    }
}

private final class AppcastXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var appcastTitle = ""
    private var items: [SparkleAppcastItem] = []

    private var currentElement = ""
    private var currentText = ""
    private var inItem = false

    private var itemTitle = ""
    private var itemVersion = ""
    private var itemShortVersion: String?
    private var itemDownloadURL = ""
    private var itemLength: Int?
    private var itemSparkleVersion: String?
    private var itemMinSystemVersion: String?
    private var itemReleaseNotesLink: String?
    private var itemPubDate: String?
    private var itemEdSignature: String?
    private var itemDSASignature: String?

    init(data: Data) {
        self.data = data
    }

    func parse() -> SparkleAppcast? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return SparkleAppcast(title: appcastTitle, items: items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            inItem = true
            itemTitle = ""
            itemVersion = ""
            itemShortVersion = nil
            itemDownloadURL = ""
            itemLength = nil
            itemSparkleVersion = nil
            itemMinSystemVersion = nil
            itemReleaseNotesLink = nil
            itemPubDate = nil
            itemEdSignature = nil
            itemDSASignature = nil
        }

        if inItem {
            if elementName == "enclosure" {
                itemDownloadURL = attributeDict["url"] ?? ""
                if let lengthStr = attributeDict["length"] {
                    itemLength = Int(lengthStr)
                }
                if let sv = attributeDict["sparkle:version"] {
                    itemVersion = sv
                    itemSparkleVersion = sv
                }
                if let ssv = attributeDict["sparkle:shortVersionString"] {
                    itemShortVersion = ssv
                }
                if let edSig = attributeDict["sparkle:edSignature"] {
                    itemEdSignature = edSig
                }
                if let dsaSig = attributeDict["sparkle:dsaSignature"] {
                    itemDSASignature = dsaSig
                }
            }
            if let minSys = attributeDict["sparkle:minimumSystemVersion"] {
                itemMinSystemVersion = minSys
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "title" && !inItem {
            appcastTitle = text
        }

        if inItem {
            switch elementName {
            case "title": itemTitle = text
            case "pubDate": itemPubDate = text
            case "sparkle:releaseNotesLink", "releaseNotesLink": itemReleaseNotesLink = text
            case "sparkle:version": if itemVersion.isEmpty { itemVersion = text }
            case "sparkle:minimumSystemVersion": itemMinSystemVersion = text
            case "item":
                let item = SparkleAppcastItem(
                    title: itemTitle,
                    version: itemVersion,
                    shortVersion: itemShortVersion,
                    downloadURL: itemDownloadURL,
                    length: itemLength,
                    sparkleVersion: itemSparkleVersion,
                    minimumSystemVersion: itemMinSystemVersion,
                    releaseNotesLink: itemReleaseNotesLink,
                    pubDate: itemPubDate,
                    edSignature: itemEdSignature,
                    dsaSignature: itemDSASignature
                )
                items.append(item)
                inItem = false
            default: break
            }
        }

        currentElement = ""
        currentText = ""
    }
}
