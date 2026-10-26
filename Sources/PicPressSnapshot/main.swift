//
//  main.swift
//  PicPressSnapshot
//
//  Renders MainViewController offscreen into a PNG so the UI can be reviewed
//  (and diffed) without taking over the screen. Used by scripts/snapshot.sh.
//
//  Usage: picpress-snapshot [--dark] [--empty] [--running] [out.png]
//

import AppKit

func pump(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

MainActor.assumeIsolated {
    var outputPath = "/tmp/picpress-snapshot.png"
    var dark = false
    var empty = false
    var running = false

    for argument in CommandLine.arguments.dropFirst() {
        switch argument {
        case "--dark": dark = true
        case "--empty": empty = true
        case "--running": running = true
        default:
            if !argument.hasPrefix("--") { outputPath = argument }
        }
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let controller = MainViewController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .windowBackgroundColor
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 760, height: 600))
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)

    let sampleDirectory = ProcessInfo.processInfo.environment["PICPRESS_SAMPLES"]
        ?? "/tmp/pixtest/in"
    let candidates = [
        "photo.heic", "photo.png", "small.jpg", "alpha.png", "rotated.jpg", "broken.png"
    ]
    let samples = candidates
        .map { URL(fileURLWithPath: sampleDirectory).appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }

    if !empty {
        if running {
            // Duplicate a heavy file so the queue is still busy when we capture.
            var urls: [URL] = []
            for _ in 0..<4 {
                for sample in samples where sample.pathExtension.lowercased() == "tiff"
                    || sample.pathExtension.lowercased() == "png" {
                    urls.append(sample)
                }
            }
            controller.queue.add(urls: urls.isEmpty ? samples : urls)
            pump(0.9)
        } else {
            controller.queue.add(urls: samples)
            var waited = 0.0
            while controller.queue.isRunning && waited < 60 {
                pump(0.05)
                waited += 0.05
            }
            pump(0.6)
        }
    }

    pump(0.4)

    let view = controller.view
    view.layoutSubtreeIfNeeded()

    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
        exit(1)
    }
    view.cacheDisplay(in: view.bounds, to: representation)

    guard let png = representation.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode png\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: outputPath))
        print("wrote \(outputPath) (\(representation.pixelsWide)×\(representation.pixelsHigh))")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}
