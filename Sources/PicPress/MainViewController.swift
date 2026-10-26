//
//  MainViewController.swift
//  PicPress
//

import AppKit
import UniformTypeIdentifiers

/// Window root: accepts file drops anywhere in the window.
final class DropRootView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    var onDragActiveChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor(for: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        guard let items = info.draggingPasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            guard let string = item.string(forType: .fileURL) else { return nil }
            return URL(string: string)
        }
    }

    private func accepts(_ info: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: info)
        guard !urls.isEmpty else { return false }
        return urls.contains { url in
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return true
            }
            return ImageCompressor.isSupportedImage(url)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        onDragActiveChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragActiveChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragActiveChanged?(false)
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragActiveChanged?(false)
    }
}

// MARK: -

final class MainViewController: NSViewController {
    let queue = CompressionQueue()

    private let header = HeaderBar()
    private let listView = FileListView()
    private let emptyState = EmptyStateView()
    private let footer = FooterBar()
    private let banner = ExportBanner()
    private let overlay = DropOverlay()
    private var bannerHeight: NSLayoutConstraint!

    override func loadView() {
        let root = DropRootView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        root.wantsLayer = true
        view = root
        buildLayout(in: root)
        wire()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    private func buildLayout(in root: NSView) {
        let headerHairline = HairlineView()
        let footerHairline = HairlineView()
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        for subview in [header, headerHairline, content, banner, footerHairline, footer, overlay] {
            root.addSubview(subview)
        }

        content.addSubview(listView)
        content.addSubview(emptyState)

        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 78),

            headerHairline.topAnchor.constraint(equalTo: header.bottomAnchor),
            headerHairline.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerHairline.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerHairline.heightAnchor.constraint(equalToConstant: 1),

            content.topAnchor.constraint(equalTo: headerHairline.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: banner.topAnchor),

            banner.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            banner.bottomAnchor.constraint(equalTo: footerHairline.topAnchor),
            bannerHeight,

            footerHairline.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerHairline.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerHairline.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footerHairline.heightAnchor.constraint(equalToConstant: 1),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 50),

            listView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            listView.topAnchor.constraint(equalTo: content.topAnchor),
            listView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            emptyState.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: content.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            overlay.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            overlay.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            overlay.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6)
        ])
    }

    private func wire() {
        header.onQualityLive = { [weak self] value in
            self?.queue.quality = value
        }
        header.onQualityCommit = { [weak self] value in
            self?.queue.updateQuality(value)
        }
        header.onEdgeChange = { [weak self] edge in
            self?.queue.updateMaxEdge(edge)
        }

        footer.onAdd = { [weak self] in self?.queue.chooseFiles() }
        footer.onClear = { [weak self] in self?.queue.clear() }
        footer.onExport = { [weak self] in self?.queue.exportAll() }
        footer.onStop = { [weak self] in self?.queue.stop() }

        emptyState.onChoose = { [weak self] in self?.queue.chooseFiles() }

        banner.onReveal = { [weak self] in
            guard let self, let summary = self.queue.lastExport else { return }
            self.queue.openFolder(summary.folder)
        }

        if let root = view as? DropRootView {
            root.onDropFiles = { [weak self] urls in
                self?.queue.add(urls: urls)
            }
            root.onDragActiveChanged = { [weak self] active in
                self?.overlay.isHidden = !active
            }
        }

        queue.onUpdate = { [weak self] in
            self?.refresh()
        }

        header.setQuality(queue.quality)
        header.setMaxEdge(queue.maxEdge)
    }

    // MARK: - Refresh

    private func refresh() {
        let hasItems = !queue.items.isEmpty
        listView.isHidden = !hasItems
        emptyState.isHidden = hasItems

        listView.update(items: queue.items, queue: queue)
        footer.update(with: queue)

        if let summary = queue.lastExport {
            banner.set(summary: summary)
            banner.isHidden = false
            bannerHeight.constant = 28
        } else {
            banner.isHidden = true
            bannerHeight.constant = 0
        }

        view.needsLayout = true
    }
}
