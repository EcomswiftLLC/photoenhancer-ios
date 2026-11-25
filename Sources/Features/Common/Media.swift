import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// Turning picked photos, files and drops into `PhotoAsset`s. Decoding happens off the main thread.
enum MediaImport {
    static let maxBatch = 30

    static func asset(from item: PhotosPickerItem, index: Int) async -> PhotoAsset? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            PhotoAsset.from(data: data, title: index == 0 ? "Photo" : "Photo \(index + 1)")
        }.value
    }

    static func assets(from items: [PhotosPickerItem]) async -> (assets: [PhotoAsset], failed: Int) {
        var assets: [PhotoAsset] = []
        var failed = 0
        for (index, item) in items.prefix(maxBatch).enumerated() {
            if let asset = await asset(from: item, index: index) { assets.append(asset) } else { failed += 1 }
        }
        return (assets, failed)
    }

    /// A file chosen in the Files app.
    static func asset(fromFile url: URL) async -> PhotoAsset? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= PhotoAsset.maxFileBytes, let data = try? Data(contentsOf: url) else { return nil }
        let title = url.deletingPathExtension().lastPathComponent
        return await Task.detached(priority: .userInitiated) { PhotoAsset.from(data: data, title: title) }.value
    }

    static func assets(fromFiles urls: [URL]) async -> (assets: [PhotoAsset], failed: Int) {
        var assets: [PhotoAsset] = []
        var failed = 0
        for url in urls.prefix(maxBatch) {
            if let asset = await asset(fromFile: url) { assets.append(asset) } else { failed += 1 }
        }
        return (assets, failed)
    }

    /// Photos dropped on the window (iPad drag and drop).
    static func assets(fromDrop providers: [NSItemProvider]) async -> [PhotoAsset] {
        var assets: [PhotoAsset] = []
        for (index, provider) in providers.prefix(maxBatch).enumerated() {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data else { continue }
            let title = provider.suggestedName ?? (index == 0 ? "Photo" : "Photo \(index + 1)")
            if let asset = await Task.detached(priority: .userInitiated, operation: { PhotoAsset.from(data: data, title: title) }).value {
                assets.append(asset)
            }
        }
        return assets
    }
}

enum LibrarySaver {
    enum SaveError: Error { case denied, failed }

    /// True when Clarivo may add to the library. Asks the system the first time.
    static func ensureAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }

    static func save(_ items: [ExportItem]) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        let entries = items.map { ($0.url, $0.utType.identifier) }
        try await PHPhotoLibrary.shared().performChanges {
            for (url, identifier) in entries {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = identifier
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: url, options: options)
            }
        }
    }
}

/// The system share sheet. `onFinish(completed)` runs when it closes for any reason.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// "Save to Files": the system document picker in export mode. `onFinish(saved)`.
struct FilesExporter: UIViewControllerRepresentable {
    let urls: [URL]
    var onFinish: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}

/// Plain wording for sizes.
enum CVFormat {
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func pixels(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height)"
    }

    static func megapixels(_ size: PixelSize) -> String {
        let mp = size.megapixels
        return mp >= 10 ? String(format: "%.0f MP", mp) : String(format: "%.1f MP", mp)
    }

    static func seconds(_ value: Double) -> String {
        value < 60 ? "\(Int(value.rounded())) s" : "\(Int(value / 60)) min \(Int(value.truncatingRemainder(dividingBy: 60))) s"
    }
}
