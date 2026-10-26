//
//  CompressionQueue.swift
//  PicPress
//
//  The model layer: keeps the queue, runs a small worker pool and handles export.
//  Everything here is main-actor bound and reports changes through `onUpdate`.
//

import AppKit

@MainActor
final class CompressionQueue {

    struct Item {
        enum State: Equatable {
            case pending
            case working
            case finished
            case failed(String)

            var isPending: Bool {
                if case .pending = self { return true }
                return false
            }
        }

        let id = UUID()
        let url: URL
        var sourceBytes: Int
        var pixelSize: CGSize?
        var thumbnail: NSImage?
        var state: State = .pending
        var outputURL: URL?
        var output: CompressedOutput?

        var fileName: String { url.lastPathComponent }

        var savingFraction: Double {
            guard let output, sourceBytes > 0 else { return 0 }
            return 1 - Double(output.byteCount) / Double(sourceBytes)
        }
    }

    struct ExportSummary {
        let folder: URL
        let count: Int
        let totalBytes: Int
    }

    // MARK: - Public state

    private(set) var items: [Item] = []
    private(set) var isRunning = false
    private(set) var runDone = 0
    private(set) var runTotal = 0
    private(set) var lastExport: ExportSummary?

    var quality: Double = CompressSettings.defaultQuality
    var maxEdge: Int?

    /// Called whenever anything the UI shows has changed.
    var onUpdate: (() -> Void)?

    var settings: CompressSettings {
        CompressSettings(quality: quality, maxEdge: maxEdge)
    }

    var finishedItems: [Item] {
        items.filter { $0.state == .finished && $0.output != nil }
    }

    var totalSourceBytes: Int { finishedItems.reduce(0) { $0 + $1.sourceBytes } }
    var totalOutputBytes: Int { finishedItems.reduce(0) { $0 + ($1.output?.byteCount ?? 0) } }

    var savedFraction: Double {
        guard totalSourceBytes > 0 else { return 0 }
        return 1 - Double(totalOutputBytes) / Double(totalSourceBytes)
    }

    var progress: Double {
        guard runTotal > 0 else { return 0 }
        return min(1, Double(runDone) / Double(runTotal))
    }

    var hasPendingWork: Bool { items.contains { $0.state.isPending } }

    // MARK: - Private state

    private var currentRun: Task<Void, Never>?
    private var runID = UUID()
    private var stopped = false
    private var usedNames: Set<String> = []
    private var sessionDirectory: URL?

    private var outputDirectory: URL {
        if let directory = sessionDirectory { return directory }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicPress-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sessionDirectory = directory
        return directory
    }

    func cleanupTemporaryFiles() {
        if let directory = sessionDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        sessionDirectory = nil
    }

    private func notify() { onUpdate?() }

    // MARK: - Adding files

    func add(urls: [URL]) {
        let files = expand(urls)
        guard !files.isEmpty else { return }

        var added: [Item] = []
        for url in files {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            var item = Item(url: url, sourceBytes: bytes)
            item.outputURL = reserveOutputURL(for: url)
            added.append(item)
        }

        items.append(contentsOf: added)
        lastExport = nil
        probe(ids: added.map(\.id))
        notify()
        startPending()
    }

    private func expand(_ urls: [URL]) -> [URL] {
        var known = Set(items.map { $0.url.standardizedFileURL })
        var result: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: standardized,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let file as URL in enumerator {
                    guard ImageCompressor.isSupportedImage(file) else { continue }
                    let candidate = file.standardizedFileURL
                    guard !known.contains(candidate) else { continue }
                    known.insert(candidate)
                    result.append(candidate)
                }
            } else if ImageCompressor.isSupportedImage(standardized), !known.contains(standardized) {
                known.insert(standardized)
                result.append(standardized)
            }
        }
        return result
    }

    private func reserveOutputURL(for source: URL) -> URL {
        let base = ImageCompressor.outputFileName(for: source)
        let stem = (base as NSString).deletingPathExtension
        var candidate = base
        var suffix = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(stem)-\(suffix).webp"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())
        return outputDirectory.appendingPathComponent(candidate)
    }

    private func probe(ids: [UUID]) {
        let work = items.filter { ids.contains($0.id) }.map { (id: $0.id, url: $0.url) }
        guard !work.isEmpty else { return }

        Task { [weak self] in
            await withTaskGroup(of: ProbeBox.self) { group in
                for entry in work {
                    group.addTask { ProbeBox(id: entry.id, result: ImageProbe.probe(entry.url)) }
                }
                for await box in group {
                    guard let self, let index = self.items.firstIndex(where: { $0.id == box.id }) else { continue }
                    self.items[index].sourceBytes = box.result.sourceBytes
                    if let size = box.result.pixelSize { self.items[index].pixelSize = size }
                    if let cgImage = box.result.thumbnail {
                        self.items[index].thumbnail = NSImage(cgImage: cgImage,
                                                              size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                    self.notify()
                }
            }
        }
    }

    // MARK: - Compression

    func startPending() {
        guard !isRunning else { return }
        let pending = items.filter { $0.state.isPending }
        guard !pending.isEmpty else { return }

        stopped = false
        isRunning = true
        runID = UUID()
        let activeRunID = runID
        runTotal = items.count
        runDone = items.count - pending.count

        let jobs = pending.compactMap { item -> WorkItem? in
            guard let target = item.outputURL else { return nil }
            return WorkItem(id: item.id, runID: activeRunID, source: item.url, target: target)
        }
        let snapshot = settings
        let limit = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount))

        currentRun = Task { [weak self] in
            await withTaskGroup(of: WorkResult.self) { group in
                var next = 0
                let total = jobs.count

                func submit() {
                    guard next < total else { return }
                    let job = jobs[next]
                    next += 1
                    group.addTask(priority: .userInitiated) { [weak self] in
                        await self?.markWorking(job.id)
                        return Self.perform(job, settings: snapshot)
                    }
                }

                for _ in 0..<min(limit, total) { submit() }

                while let result = await group.next() {
                    let shouldStop = await self?.finishAndCheckStop(result) ?? true
                    if shouldStop {
                        group.cancelAll()
                        break
                    }
                    submit()
                }
            }
            self?.runDidEnd(runID: activeRunID)
        }
    }

    /// Flags a queued row as actively compressing.
    private func markWorking(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].state.isPending else { return }
        items[index].state = .working
        notify()
    }

    private nonisolated static func perform(_ job: WorkItem, settings: CompressSettings) -> WorkResult {
        do {
            let output = try ImageCompressor.compress(source: job.source,
                                                      settings: settings,
                                                      writingTo: job.target)
            return WorkResult(runID: job.runID, id: job.id, output: output, error: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return WorkResult(runID: job.runID, id: job.id, output: nil, error: message)
        }
    }

    /// Applies a finished job and reports whether the user asked to stop.
    private func finishAndCheckStop(_ result: WorkResult) -> Bool {
        if result.runID == runID,
           let index = items.firstIndex(where: { $0.id == result.id }) {
            if let output = result.output {
                items[index].output = output
                items[index].state = .finished
                items[index].pixelSize = items[index].pixelSize ?? output.sourcePixelSize
            } else {
                items[index].state = .failed(result.error ?? "未知错误")
            }
            runDone += 1
            notify()
        }
        return stopped
    }

    private func runDidEnd(runID endedRunID: UUID) {
        guard endedRunID == runID else { return }
        isRunning = false
        notify()
        if stopped { return }
        if hasPendingWork { startPending() }
    }

    func stop() {
        guard isRunning else { return }
        stopped = true
        currentRun?.cancel()
        for index in items.indices where items[index].state == .working {
            items[index].state = .pending
        }
        notify()
    }

    // MARK: - Settings

    func updateQuality(_ value: Double) {
        quality = value
        requeueAll()
    }

    func updateMaxEdge(_ value: Int?) {
        maxEdge = value
        requeueAll()
    }

    private func requeueAll() {
        guard !items.isEmpty else { notify(); return }
        stopped = true
        runID = UUID()   // invalidates results still in flight
        for index in items.indices {
            items[index].state = .pending
            items[index].output = nil
        }
        runDone = 0
        runTotal = items.count
        notify()

        Task { [weak self] in
            await self?.currentRun?.value
            guard let self else { return }
            self.stopped = false
            self.startPending()
        }
    }

    // MARK: - List editing

    func retry(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].state = .pending
        items[index].output = nil
        notify()
        startPending()
    }

    func remove(_ item: Item) {
        if let output = item.output { try? FileManager.default.removeItem(at: output.url) }
        items.removeAll { $0.id == item.id }
        if items.isEmpty { lastExport = nil }
        notify()
    }

    func clear() {
        stopped = true
        currentRun?.cancel()
        runID = UUID()
        isRunning = false
        for item in items {
            if let output = item.output { try? FileManager.default.removeItem(at: output.url) }
        }
        items.removeAll()
        usedNames.removeAll()
        runDone = 0
        runTotal = 0
        lastExport = nil
        notify()
    }

    // MARK: - Export

    func exportAll() {
        let finished = finishedItems
        guard !finished.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出"
        panel.message = "选择保存 \(finished.count) 个 WebP 文件的文件夹"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        export(finished, to: folder)
    }

    func exportOne(_ item: Item) {
        guard let output = item.output else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = output.url.lastPathComponent
        panel.message = "导出 WebP 文件"
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != "webp" {
            destination = destination.appendingPathExtension("webp")
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: output.url, to: destination)
            lastExport = ExportSummary(folder: destination.deletingLastPathComponent(),
                                       count: 1,
                                       totalBytes: output.byteCount)
            notify()
        } catch {
            NSSound.beep()
        }
    }

    /// Copies the finished WebP files into `folder` (exposed for tests).
    func export(_ selected: [Item], to folder: URL) {
        let sources = selected.compactMap { item -> (URL, Int)? in
            guard let output = item.output else { return nil }
            return (output.url, output.byteCount)
        }
        guard !sources.isEmpty else { return }

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (count: Int, bytes: Int) in
                var count = 0
                var bytes = 0
                for (source, size) in sources {
                    let destination = Self.uniqueDestination(for: source.lastPathComponent, in: folder)
                    do {
                        try FileManager.default.copyItem(at: source, to: destination)
                        count += 1
                        bytes += size
                    } catch {
                        continue
                    }
                }
                return (count, bytes)
            }.value

            guard let self else { return }
            self.lastExport = ExportSummary(folder: folder, count: result.count, totalBytes: result.bytes)
            self.notify()
        }
    }

    private nonisolated static func uniqueDestination(for fileName: String, in folder: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            candidate = folder.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "添加"
        panel.message = "选择图片，或选择包含图片的文件夹"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }
}

// MARK: - Concurrency helpers

private struct WorkItem: Sendable {
    let id: UUID
    let runID: UUID
    let source: URL
    let target: URL
}

private struct WorkResult: Sendable {
    let runID: UUID
    let id: UUID
    let output: CompressedOutput?
    let error: String?
}

private struct ProbeBox: @unchecked Sendable {
    let id: UUID
    let result: ImageProbeResult
}
