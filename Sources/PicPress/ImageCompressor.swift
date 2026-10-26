//
//  ImageCompressor.swift
//  PicPress
//
//  Decodes any ImageIO-supported image, rasterizes it to RGBA and hands it to
//  libwebp. All work is pure `Foundation`/`CoreGraphics`, so it is safe to call
//  from a background executor.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Settings

struct CompressSettings: Equatable {
    /// 0.0 ... 1.0, the UI exposes 0.4 ... 1.0 with 0.8 as the default.
    var quality: Double = 0.80
    /// Longest allowed edge in pixels, `nil` keeps the original size.
    var maxEdge: Int?
    /// libwebp effort (0...6). 5 is a good size/speed balance for batch work.
    var method: Int = 5

    static let defaultQuality = 0.80
    static let qualityRange: ClosedRange<Double> = 0.40...1.00
    /// WebP cannot store images wider or taller than this.
    static let maxSupportedEdge = 16383
}

// MARK: - Errors

enum CompressionError: LocalizedError, Equatable {
    case unreadable(String)
    case emptyFile
    case unsupportedFormat(String)
    case tooLarge(Int, Int)
    case encodeFailed(Int32)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "无法读取 \(name)"
        case .emptyFile:
            return "文件为空"
        case .unsupportedFormat(let ext):
            return ext.isEmpty ? "不支持的图片格式" : "不支持 .\(ext) 格式"
        case .tooLarge(let w, let h):
            return "图片尺寸过大（\(w)×\(h)）"
        case .encodeFailed(let code):
            return "WebP 编码失败（错误码 \(code)）"
        case .writeFailed(let reason):
            return "写入失败：\(reason)"
        }
    }
}

// MARK: - Result

struct CompressedOutput {
    let url: URL
    let byteCount: Int
    let pixelSize: CGSize
    let sourcePixelSize: CGSize
}

// MARK: - Compressor

enum ImageCompressor {

    /// Extensions ImageIO (plus libwebp) can open here.
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "heic", "heif", "tif", "tiff",
        "gif", "webp", "bmp", "jp2", "j2k", "avif", "ico", "psd", "tga", "exr"
    ]

    static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// `IMG_1234.HEIC` -> `IMG_1234.webp`
    static func outputFileName(for source: URL) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "image" : trimmed) + ".webp"
    }

    // MARK: Entry point

    static func compress(source: URL,
                         settings: CompressSettings,
                         writingTo target: URL) throws -> CompressedOutput {
        let image = try decode(source: source, settings: settings)
        let sourceSize = CGSize(width: image.width, height: image.height)

        var pixels = try rasterize(image)
        unpremultiply(&pixels)

        let quality = Float(max(1, min(100, (settings.quality * 100).rounded())))
        let encoded = try encodeWebP(pixels: pixels,
                                     width: image.width,
                                     height: image.height,
                                     quality: quality,
                                     method: Int32(settings.method))

        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoded.write(to: target, options: .atomic)
        } catch {
            throw CompressionError.writeFailed(error.localizedDescription)
        }

        return CompressedOutput(url: target,
                                byteCount: encoded.count,
                                pixelSize: CGSize(width: image.width, height: image.height),
                                sourcePixelSize: sourceSize)
    }

    // MARK: Decoding

    private static func decode(source: URL, settings: CompressSettings) throws -> CGImage {
        let ext = source.pathExtension.lowercased()
        guard isSupportedImage(source) else { throw CompressionError.unsupportedFormat(ext) }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        guard fileSize > 0 else { throw CompressionError.emptyFile }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, sourceOptions),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw CompressionError.unreadable(source.lastPathComponent)
        }

        // Work out the longest edge we are willing to keep.
        var longEdge = settings.maxEdge ?? 0
        if longEdge <= 0 {
            if let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
               let width = props[kCGImagePropertyPixelWidth] as? Int,
               let height = props[kCGImagePropertyPixelHeight] as? Int {
                longEdge = max(width, height)
            } else {
                longEdge = CompressSettings.maxSupportedEdge
            }
        }
        longEdge = max(1, min(longEdge, CompressSettings.maxSupportedEdge))

        // ImageIO bakes the EXIF orientation in and downsamples in one pass.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0,
                                                             thumbnailOptions as CFDictionary) else {
            throw CompressionError.unreadable(source.lastPathComponent)
        }
        guard image.width > 0, image.height > 0 else {
            throw CompressionError.unreadable(source.lastPathComponent)
        }
        guard image.width <= CompressSettings.maxSupportedEdge,
              image.height <= CompressSettings.maxSupportedEdge else {
            throw CompressionError.tooLarge(image.width, image.height)
        }
        return image
    }

    // MARK: Bitmap conversion

    /// Draws `image` into a tightly packed 8-bit RGBA buffer.
    private static func rasterize(_ image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height

        let needsAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            needsAlpha = false
        default:
            needsAlpha = true
        }

        let alphaInfo: CGImageAlphaInfo = needsAlpha ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: alphaInfo.rawValue) else {
            throw CompressionError.tooLarge(width, height)
        }

        if needsAlpha {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let raw = context.data else {
            throw CompressionError.unreadable("bitmap")
        }

        var pixels = [UInt8](repeating: 0, count: byteCount)
        pixels.withUnsafeMutableBytes { destination in
            if let base = destination.baseAddress {
                memcpy(base, raw, byteCount)
            }
        }
        return pixels
    }

    /// Core Graphics gives premultiplied alpha, libwebp wants straight alpha.
    /// Fully transparent pixels are normalized to transparent black so that the
    /// encoder can collapse them losslessly.
    private static func unpremultiply(_ pixels: inout [UInt8]) {
        pixels.withUnsafeMutableBufferPointer { buffer in
            var index = 3
            let count = buffer.count
            while index < count {
                let alpha = Int(buffer[index])
                if alpha != 255 {
                    if alpha == 0 {
                        buffer[index - 3] = 0
                        buffer[index - 2] = 0
                        buffer[index - 1] = 0
                    } else {
                        let scale = 255.0 / Double(alpha)
                        let red = Int((Double(buffer[index - 3]) * scale).rounded())
                        let green = Int((Double(buffer[index - 2]) * scale).rounded())
                        let blue = Int((Double(buffer[index - 1]) * scale).rounded())
                        buffer[index - 3] = UInt8(min(255, red))
                        buffer[index - 2] = UInt8(min(255, green))
                        buffer[index - 1] = UInt8(min(255, blue))
                    }
                }
                index += 4
            }
        }
    }

    // MARK: Encoding

    private static func encodeWebP(pixels: [UInt8],
                                   width: Int,
                                   height: Int,
                                   quality: Float,
                                   method: Int32) throws -> Data {
        var outPointer: UnsafeMutablePointer<UInt8>?
        var outSize = 0

        let status: Int32 = pixels.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return pp_webp_encode(base,
                                  Int32(width),
                                  Int32(height),
                                  Int32(width * 4),
                                  quality,
                                  method,
                                  &outPointer,
                                  &outSize)
        }

        guard status == 0, let pointer = outPointer, outSize > 0 else {
            if let pointer = outPointer { pp_webp_free(pointer) }
            throw CompressionError.encodeFailed(status)
        }
        defer { pp_webp_free(pointer) }
        return Data(bytes: pointer, count: outSize)
    }
}

// MARK: - Metadata probe (thumbnails for the list)

struct ImageProbeResult {
    let pixelSize: CGSize?
    let thumbnail: CGImage?
    let sourceBytes: Int
}

enum ImageProbe {
    static func probe(_ url: URL, thumbnailEdge: Int = 128) -> ImageProbeResult {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return ImageProbeResult(pixelSize: nil, thumbnail: nil, sourceBytes: bytes)
        }

        var pixelSize: CGSize?
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
            pixelSize = (orientation >= 5 && orientation <= 8)
                ? CGSize(width: height, height: width)
                : CGSize(width: width, height: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailEdge
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return ImageProbeResult(pixelSize: pixelSize, thumbnail: thumbnail, sourceBytes: bytes)
    }
}
