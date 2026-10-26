//
//  main.swift
//  picpress-cli
//
//  Head-less companion to the app: same engine, no UI. Handy for scripts,
//  benchmarks and integration tests.
//
//  Usage: picpress-cli [--quality 80] [--max-edge 2048] [--out DIR] <file|dir>...
//

import Foundation

struct Options {
    var quality: Double = CompressSettings.defaultQuality
    var maxEdge: Int?
    var outputDirectory: URL?
    var inputs: [URL] = []
}

func usage() -> String {
    """
    picpress-cli — 批量把图片压缩成 WebP

    用法:
      picpress-cli [选项] <文件或目录>...

    选项:
      -q, --quality <0-100>   输出质量，默认 80
      -m, --max-edge <px>     限制长边像素（不写则保持原尺寸）
      -o, --out <目录>         输出目录，默认写入临时目录
      -h, --help              显示帮助
    """
}

func parseArguments() -> Options? {
    var options = Options()
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            print(usage())
            exit(0)
        case "-q", "--quality":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]) else {
                FileHandle.standardError.write(Data("错误：--quality 需要一个 0-100 的数字\n".utf8))
                return nil
            }
            options.quality = max(0, min(100, value)) / 100
        case "-m", "--max-edge":
            index += 1
            guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                FileHandle.standardError.write(Data("错误：--max-edge 需要一个正整数\n".utf8))
                return nil
            }
            options.maxEdge = value
        case "-o", "--out":
            index += 1
            guard index < arguments.count else {
                FileHandle.standardError.write(Data("错误：--out 需要一个目录\n".utf8))
                return nil
            }
            options.outputDirectory = URL(fileURLWithPath: arguments[index])
        default:
            if argument.hasPrefix("-") {
                FileHandle.standardError.write(Data("未知选项：\(argument)\n".utf8))
                return nil
            }
            let url = URL(fileURLWithPath: argument)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let child as URL in enumerator where ImageCompressor.isSupportedImage(child) {
                        options.inputs.append(child)
                    }
                }
            } else if ImageCompressor.isSupportedImage(url) {
                options.inputs.append(url)
            } else {
                FileHandle.standardError.write(Data("跳过（不支持的格式）：\(argument)\n".utf8))
            }
        }
        index += 1
    }
    return options
}

func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
    let length = text.count
    guard length < width else { return text }
    let filler = String(repeating: " ", count: width - length)
    return right ? filler + text : text + filler
}

func humanBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func encoderVersion() -> String {
    let version = pp_webp_encoder_version()
    return "\(version >> 16).\((version >> 8) & 0xff).\(version & 0xff)"
}

guard let options = parseArguments(), !options.inputs.isEmpty else {
    print(usage())
    exit(2)
}

let settings = CompressSettings(quality: options.quality, maxEdge: options.maxEdge)
let workDirectory = options.outputDirectory
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("picpress-cli-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

var usedNames: Set<String> = []
var totalIn = 0
var totalOut = 0
var failures = 0

print("")
print("PicPress · \(options.inputs.count) 个文件 · 质量 \(Int((settings.quality * 100).rounded()))% · libwebp \(encoderVersion())")
print(String(repeating: "─", count: 78))

for source in options.inputs {
    let base = ImageCompressor.outputFileName(for: source)
    let stem = (base as NSString).deletingPathExtension
    var name = base
    var suffix = 2
    while usedNames.contains(name.lowercased()) {
        name = "\(stem)-\(suffix).webp"
        suffix += 1
    }
    usedNames.insert(name.lowercased())

    let destination = workDirectory.appendingPathComponent(name)
    let sourceBytes = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0

    do {
        let start = Date()
        let output = try ImageCompressor.compress(source: source, settings: settings, writingTo: destination)
        let elapsed = Date().timeIntervalSince(start)

        totalIn += sourceBytes
        totalOut += output.byteCount
        let dimensions = "\(Int(output.pixelSize.width))×\(Int(output.pixelSize.height))"
        let line = "  " + pad(source.lastPathComponent, 30)
            + pad(humanBytes(sourceBytes), 10, right: true) + " → "
            + pad(humanBytes(output.byteCount), 10, right: true) + "  "
            + pad(ByteFormat.savings(from: sourceBytes, to: output.byteCount), 6, right: true) + "  "
            + pad(dimensions, 13)
            + String(format: "%5.0f ms", elapsed * 1000)
        print(line)
    } catch {
        failures += 1
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        print("  ✗ \(source.lastPathComponent)：\(message)")
    }
}

print(String(repeating: "─", count: 78))
if totalIn > 0 {
    print("  合计 " + pad(humanBytes(totalIn), 10, right: true) + " → "
          + pad(humanBytes(totalOut), 10, right: true) + "  "
          + pad(ByteFormat.savings(from: totalIn, to: totalOut), 6, right: true))
}
print("  输出目录：\(workDirectory.path)")
if options.outputDirectory == nil {
    print("  （未指定 --out，输出在临时目录里）")
}
print("")

exit(failures == 0 ? 0 : 1)
