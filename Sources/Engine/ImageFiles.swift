import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Export file formats.
enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case jpg, png, heic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        }
    }

    var detail: String {
        switch self {
        case .jpg: return "Opens everywhere."
        case .png: return "Lossless, larger files."
        case .heic: return "Small files, best quality for the size."
        }
    }

    var utType: UTType {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        }
    }

    var isLossy: Bool { self != .png }

    /// True when this device can write the format (HEIC needs a hardware encoder).
    var isSupported: Bool {
        let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return types.contains(utType.identifier)
    }
}

/// Reading photos safely: every decode is size-capped and returns nil for anything that is not a readable image.
enum ImageDecoder {
    struct Info: Equatable {
        var pixelSize: PixelSize
        /// Upright size (width and height swapped for rotated EXIF orientations).
        var uprightSize: PixelSize
    }

    static func info(_ source: CGImageSource) -> Info? {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let rotated = orientation >= 5 && orientation <= 8
        let size = PixelSize(width: width, height: height)
        return Info(pixelSize: size, uprightSize: rotated ? PixelSize(width: height, height: width) : size)
    }

    /// Decodes upright, at most `maxPixel` on the long side (never enlarges).
    static func decode(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        guard let info = info(source) else { return nil }
        let limit = max(16, min(maxPixel, info.pixelSize.longSide))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func decode(data: Data, maxPixel: Int) -> CGImage? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decode(source, maxPixel: maxPixel)
    }

    static func decode(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decode(source, maxPixel: maxPixel)
    }

    /// The photo's metadata (EXIF, GPS, TIFF, IPTC...), as ImageIO reports it.
    static func metadata(data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }
}

/// Writes finished photos. Metadata is either kept (camera, date, location, with orientation reset because the
/// pixels are already upright) or stripped completely, including GPS.
enum ImageWriter {
    /// Top-level metadata dictionaries carried over when keeping metadata.
    static let keptDictionaries: [CFString] = [
        kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
        kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary,
    ]

    /// Properties for `CGImageDestinationAddImage`.
    static func properties(format: ImageFormat, quality: Double, sourceMetadata: [String: Any]?, keepMetadata: Bool, size: PixelSize) -> [CFString: Any] {
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.05), 1)
        }
        guard keepMetadata, let source = sourceMetadata else { return properties }
        for key in keptDictionaries {
            guard var dictionary = source[key as String] as? [String: Any] else { continue }
            if key == kCGImagePropertyTIFFDictionary {
                dictionary[kCGImagePropertyTIFFOrientation as String] = 1
            }
            if key == kCGImagePropertyExifDictionary {
                dictionary[kCGImagePropertyExifPixelXDimension as String] = size.width
                dictionary[kCGImagePropertyExifPixelYDimension as String] = size.height
            }
            properties[key] = dictionary
        }
        return properties
    }

    static func data(_ image: CGImage, format: ImageFormat, quality: Double, sourceMetadata: [String: Any]?, keepMetadata: Bool) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, format.utType.identifier as CFString, 1, nil) else { return nil }
        let props = properties(format: format, quality: quality, sourceMetadata: sourceMetadata, keepMetadata: keepMetadata,
                               size: PixelSize(width: image.width, height: image.height))
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double, sourceMetadata: [String: Any]?, keepMetadata: Bool) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw EnhanceError.writeFailed
        }
        let props = properties(format: format, quality: quality, sourceMetadata: sourceMetadata, keepMetadata: keepMetadata,
                               size: PixelSize(width: image.width, height: image.height))
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EnhanceError.writeFailed }
    }
}
