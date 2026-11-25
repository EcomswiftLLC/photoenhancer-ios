import Foundation
import CoreGraphics
import ImageIO

/// The bundled sample photos (Sources/Resources/Samples, with an optional samples.json for order, titles and credits).
enum SampleLibrary {
    private static let photoExtensions = ["jpg", "jpeg", "png", "heic"]

    private static func urls(bundle: Bundle) -> [URL] {
        var found = [URL]()
        for ext in photoExtensions {
            found += bundle.urls(forResourcesWithExtension: ext, subdirectory: "Samples") ?? []
            found += bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        // Never offer the app icon or anything that is not a sample photo.
        return found.filter { !$0.lastPathComponent.lowercased().hasPrefix("appicon") }
    }

    struct Entry: Equatable {
        var name: String
        var title: String
        var credit: String?
        /// What the sample shows off, an `EnhanceOperation` case name such as "upscale" or "restoreOld".
        var tool: String?
        var blurb: String?
    }

    static func catalog(bundle: Bundle = .main) -> [Entry] {
        let candidates = [bundle.url(forResource: "samples", withExtension: "json", subdirectory: "Samples"),
                          bundle.url(forResource: "samples", withExtension: "json")]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let photos = object["photos"] as? [[String: Any]] else { continue }
            return photos.compactMap { item in
                guard let file = item["file"] as? String else { return nil }
                let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                return Entry(name: name, title: (item["title"] as? String) ?? titleFromName(name),
                             credit: item["credit"] as? String,
                             tool: (item["suggestedTool"] as? String) ?? (item["tool"] as? String),
                             blurb: item["blurb"] as? String)
            }
        }
        return []
    }

    /// Sample names in samples.json order first, then any others sorted.
    static func availableNames(bundle: Bundle = .main) -> [String] {
        let all = Set(urls(bundle: bundle).map { $0.deletingPathExtension().lastPathComponent })
        let preferred = catalog(bundle: bundle).map(\.name).filter { all.contains($0) }
        return preferred + all.subtracting(preferred).sorted()
    }

    static func url(named name: String, bundle: Bundle = .main) -> URL? {
        urls(bundle: bundle).first { $0.deletingPathExtension().lastPathComponent == name }
    }

    static func image(named name: String, maxPixel: Int, bundle: Bundle = .main) -> CGImage? {
        guard let url = url(named: name, bundle: bundle) else { return nil }
        return ImageDecoder.decode(url: url, maxPixel: maxPixel)
    }

    static func title(for name: String, bundle: Bundle = .main) -> String {
        catalog(bundle: bundle).first { $0.name == name }?.title ?? titleFromName(name)
    }

    /// "old-portrait_02" becomes "Old portrait".
    static func titleFromName(_ name: String) -> String {
        var text = name
        if text.lowercased().hasPrefix("sample") { text = String(text.dropFirst("sample".count)) }
        let words = text.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").filter { Int($0) == nil }.map(String.init)
        guard let first = words.first else { return "Sample" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    /// "Title: credit" lines for the licences screen.
    static func credits(bundle: Bundle = .main) -> [String] {
        let available = Set(availableNames(bundle: bundle))
        return catalog(bundle: bundle).compactMap { entry in
            guard available.contains(entry.name), let credit = entry.credit else { return nil }
            return "\(entry.title): \(credit)"
        }
    }
}

/// Recent results, kept in the app's own container for 7 days. Nothing leaves the device.
final class HistoryStore {
    static let shared = HistoryStore()

    struct Item: Codable, Identifiable, Equatable {
        var id: UUID
        var title: String
        var date: Date
        var fileName: String
        var thumbnailName: String
        var summary: String
        var pixelWidth: Int
        var pixelHeight: Int
    }

    static let maxAge: TimeInterval = 7 * 86_400

    let folder: URL
    private let fileManager = FileManager.default

    init(folder: URL? = nil) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.folder = folder ?? base.appendingPathComponent("History", isDirectory: true)
        try? fileManager.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    func items() -> [Item] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private func save(_ list: [Item]) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: indexURL, options: .atomic) }
    }

    func url(of item: Item) -> URL { folder.appendingPathComponent(item.fileName) }
    func thumbnailURL(of item: Item) -> URL { folder.appendingPathComponent(item.thumbnailName) }

    /// Copies a finished file into history with a small thumbnail.
    @discardableResult
    func add(fileAt source: URL, title: String, summary: String, image: CGImage) -> Item? {
        let id = UUID()
        let fileName = "\(id.uuidString).\(source.pathExtension.isEmpty ? "jpg" : source.pathExtension)"
        let thumbName = "\(id.uuidString)-thumb.jpg"
        do {
            try fileManager.copyItem(at: source, to: folder.appendingPathComponent(fileName))
        } catch {
            return nil
        }
        if let thumb = Enhancer.resize(image, to: PixelSize(width: image.width, height: image.height).fitting(longSide: 480)),
           let data = ImageWriter.data(thumb, format: .jpg, quality: 0.8, sourceMetadata: nil, keepMetadata: false) {
            try? data.write(to: folder.appendingPathComponent(thumbName))
        }
        let item = Item(id: id, title: title, date: Date(), fileName: fileName, thumbnailName: thumbName,
                        summary: summary, pixelWidth: image.width, pixelHeight: image.height)
        var list = items()
        list.insert(item, at: 0)
        save(Array(list.prefix(60)))
        return item
    }

    func remove(_ item: Item) {
        try? fileManager.removeItem(at: url(of: item))
        try? fileManager.removeItem(at: thumbnailURL(of: item))
        save(items().filter { $0.id != item.id })
    }

    func clearAll() {
        for item in items() { remove(item) }
        save([])
    }

    /// Removes results older than `maxAge` (run at launch).
    func pruneOld(now: Date = Date()) {
        let list = items()
        let keep = list.filter { now.timeIntervalSince($0.date) < Self.maxAge }
        for item in list where !keep.contains(item) {
            try? fileManager.removeItem(at: url(of: item))
            try? fileManager.removeItem(at: thumbnailURL(of: item))
        }
        if keep.count != list.count { save(keep) }
    }
}
