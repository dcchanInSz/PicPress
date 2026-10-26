//
//  main.swift
//  PicPressTests
//
//  Dependency-free integration tests: the encoder, the queue and the export
//  step all run for real. `make test` builds and runs this.
//

import AppKit
import Foundation
import ImageIO

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)")
    }
}

func pump(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func waitUntil(_ condition: () -> Bool, timeout: Double = 30) -> Bool {
    var waited = 0.0
    while !condition() && waited < timeout {
        pump(0.02)
        waited += 0.02
    }
    return condition()
}

func makeTestImage(at url: URL, width: Int = 640, height: Int = 480, alpha: Bool = false) -> URL {
    let space = CGColorSpaceCreateDeviceRGB()
    let info: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space, bitmapInfo: info.rawValue)!
    let stripeHeight = alpha ? height / 2 : height
    for x in stride(from: 0, to: width, by: 8) {
        let fraction = Double(x) / Double(width)
        context.setFillColor(CGColor(srgbRed: fraction, green: 0.3, blue: 1 - fraction, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 8, height: stripeHeight))
    }
    if alpha {
        // The upper half stays transparent, with a translucent shape on top.
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 0.6))
        context.fillEllipse(in: CGRect(x: 60, y: height / 2 + 40, width: 240, height: 160))
    }
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    _ = CGImageDestinationFinalize(destination)
    return url
}

func isWebP(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url), data.count > 12 else { return false }
    let riff = String(decoding: data.prefix(4), as: UTF8.self)
    let webp = String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self)
    return riff == "RIFF" && webp == "WEBP"
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("picpress-tests-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // MARK: Engine

    print("• 压缩引擎")
    let source = makeTestImage(at: root.appendingPathComponent("gradient.png"))
    let outputDirectory = root.appendingPathComponent("engine", isDirectory: true)
    let target = outputDirectory.appendingPathComponent("gradient.webp")

    let sourceBytes = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
    let compressed = try! ImageCompressor.compress(source: source,
                                                   settings: CompressSettings(quality: 0.8),
                                                   writingTo: target)
    check(FileManager.default.fileExists(atPath: target.path), "写出 WebP 文件")
    check(isWebP(target), "文件头是 RIFF/WEBP")
    check(compressed.pixelSize == CGSize(width: 640, height: 480), "保持原始尺寸 640×480")
    check(compressed.byteCount < sourceBytes, "体积比原图小（\(sourceBytes) → \(compressed.byteCount)）")

    let scaledTarget = outputDirectory.appendingPathComponent("scaled.webp")
    let scaled = try! ImageCompressor.compress(source: source,
                                               settings: CompressSettings(quality: 0.8, maxEdge: 160),
                                               writingTo: scaledTarget)
    check(max(scaled.pixelSize.width, scaled.pixelSize.height) == 160, "长边限制生效（160）")

    let lowTarget = outputDirectory.appendingPathComponent("low.webp")
    let low = try! ImageCompressor.compress(source: source,
                                            settings: CompressSettings(quality: 0.4),
                                            writingTo: lowTarget)
    check(low.byteCount < compressed.byteCount, "质量 40% 比 80% 更小（\(low.byteCount) < \(compressed.byteCount)）")

    let alphaSource = makeTestImage(at: root.appendingPathComponent("alpha.png"), alpha: true)
    let alphaTarget = outputDirectory.appendingPathComponent("alpha.webp")
    _ = try! ImageCompressor.compress(source: alphaSource,
                                      settings: CompressSettings(quality: 0.8),
                                      writingTo: alphaTarget)
    let alphaData = (try? Data(contentsOf: alphaTarget)) ?? Data()
    check(alphaData.range(of: Data("ALPH".utf8)) != nil, "带透明通道的图片保留了 ALPH")

    let opaqueData = (try? Data(contentsOf: target)) ?? Data()
    check(opaqueData.range(of: Data("ALPH".utf8)) == nil, "不透明图片不写入 ALPH")

    // MARK: Queue

    print("• 队列")
    let queue = CompressionQueue()
    let inputs = (1...3).map { index in
        makeTestImage(at: root.appendingPathComponent("queue-\(index).png"))
    }
    queue.add(urls: inputs)
    check(queue.items.count == 3, "3 个文件进入队列")
    queue.add(urls: inputs)
    check(queue.items.count == 3, "重复拖入同一个文件不会重复添加")

    let queueFinished = waitUntil { !queue.isRunning && queue.finishedItems.count == 3 }
    check(queueFinished, "队列压缩完成")
    check(queue.items.allSatisfy { $0.state == .finished }, "全部为完成状态")
    check(queue.totalOutputBytes < queue.totalSourceBytes, "总体积变小")
    check(queue.savedFraction > 0.5, "节省比例 > 50%（\(Int(queue.savedFraction * 100))%）")
    check(queue.items.allSatisfy { item in
        guard let url = item.output?.url else { return false }
        return FileManager.default.fileExists(atPath: url.path) && isWebP(url)
    }, "每张都有可用的 WebP 输出文件")

    // MARK: Export

    print("• 导出")
    let exportFolder = root.appendingPathComponent("export", isDirectory: true)
    try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
    queue.export(queue.finishedItems, to: exportFolder)
    let exported = waitUntil { queue.lastExport?.count == 3 } && queue.lastExport?.count == 3
    check(exported, "导出 3 个文件")
    let exportedFiles = (try? FileManager.default.contentsOfDirectory(at: exportFolder,
                                                                     includingPropertiesForKeys: nil)) ?? []
    check(exportedFiles.count == 3, "目标文件夹里有 3 个文件")
    check(exportedFiles.allSatisfy(isWebP), "导出的都是 WebP")

    queue.export(queue.finishedItems, to: exportFolder)
    let twice = waitUntil { queue.lastExport?.count == 3 && ((try? FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil).count) ?? 0) == 6 }
    check(twice, "再次导出不会覆盖同名文件")

    // MARK: Errors

    print("• 错误处理")
    let broken = root.appendingPathComponent("broken.png")
    try? Data("not an image".utf8).write(to: broken)
    var throwed = false
    do {
        _ = try ImageCompressor.compress(source: broken, settings: CompressSettings(), writingTo: root.appendingPathComponent("broken.webp"))
    } catch {
        throwed = true
    }
    check(throwed, "损坏文件会抛错而不是崩溃")

    print("")
    if failures == 0 {
        print("✅ 全部通过")
    } else {
        print("❌ \(failures) 项失败")
    }
}

exit(failures == 0 ? 0 : 1)
