//
//  FileRowView.swift
//  PicPress
//

import AppKit

/// Rounded thumbnail that draws its image aspect-filled, plus a spinner while busy.
final class ThumbView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var showsSpinner: Bool = false {
        didSet {
            spinner.isHidden = !showsSpinner
            if showsSpinner { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
            needsDisplay = true
        }
    }

    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateBorderColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09)
            .cgColor(for: effectiveAppearance)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
        bounds.fill()

        guard let image else { return }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: bounds.midX - drawSize.width / 2,
                          y: bounds.midY - drawSize.height / 2,
                          width: drawSize.width,
                          height: drawSize.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: showsSpinner ? 0.45 : 1)
    }
}

final class FileRowView: NSView, NSDraggingSource {
    static let height: CGFloat = 56

    private(set) var item: CompressionQueue.Item?
    weak var queue: CompressionQueue?

    private let thumbView = ThumbView()
    private let nameLabel = UI.label("", size: 13, weight: .medium)
    private let metaLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let spinner = NSProgressIndicator()
    private let statusLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let sizeGroup = NSStackView()
    private let sourceSizeLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let outputSizeLabel = UI.label("", size: 11)
    private let arrowImage = NSImageView()
    private let badge = PillLabel()
    private let trailingStack = NSStackView()
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [nameLabel, metaLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        sourceSizeLabel.font = UI.monospacedDigits(11)
        outputSizeLabel.font = UI.monospacedDigits(11)

        arrowImage.image = Glyph.image("arrow.right", pointSize: 8, weight: .semibold)
        arrowImage.contentTintColor = .tertiaryLabelColor
        arrowImage.translatesAutoresizingMaskIntoConstraints = false

        sizeGroup.orientation = .horizontal
        sizeGroup.alignment = .centerY
        sizeGroup.spacing = 5
        sizeGroup.setViews([sourceSizeLabel, arrowImage, outputSizeLabel], in: .leading)
        sizeGroup.translatesAutoresizingMaskIntoConstraints = false
        sizeGroup.isHidden = true

        badge.isHidden = true

        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.setViews([spinner, statusLabel, sizeGroup, badge], in: .leading)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(thumbView)
        addSubview(textStack)
        addSubview(trailingStack)

        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 40),
            thumbView.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -12),

            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingStack.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 12)
        ])
    }

    // MARK: - Appearance

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = isHovering
            ? Palette.rowHover.cgColor(for: effectiveAppearance)
            : NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    // MARK: - Configuration

    func configure(with item: CompressionQueue.Item, isRunning: Bool) {
        self.item = item
        nameLabel.stringValue = item.fileName

        if let size = item.pixelSize {
            metaLabel.stringValue = "\(Int(size.width))×\(Int(size.height))  ·  \(ByteFormat.string(item.sourceBytes))"
        } else {
            metaLabel.stringValue = ByteFormat.string(item.sourceBytes)
        }

        thumbView.image = item.thumbnail

        let hasOutput = item.output != nil
        sizeGroup.isHidden = !hasOutput
        badge.isHidden = !hasOutput
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = false
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        thumbView.showsSpinner = false
        statusLabel.stringValue = ""

        switch item.state {
        case .pending:
            statusLabel.stringValue = isRunning ? "等待中" : "待压缩"

        case .working:
            spinner.isHidden = false
            spinner.startAnimation(nil)
            thumbView.showsSpinner = true
            statusLabel.stringValue = "压缩中…"

        case .finished:
            statusLabel.isHidden = true
            if let output = item.output {
                sourceSizeLabel.attributedStringValue = struckThrough(ByteFormat.string(item.sourceBytes))
                outputSizeLabel.stringValue = ByteFormat.string(output.byteCount)
                let grew = output.byteCount >= item.sourceBytes
                badge.text = ByteFormat.savings(from: item.sourceBytes, to: output.byteCount)
                badge.textColor = grew ? Palette.warning : Palette.positive
                badge.fillColor = (grew ? Palette.warning : Palette.positive).withAlphaComponent(0.13)
            }

        case .failed(let message):
            statusLabel.stringValue = "失败：\(message)"
            statusLabel.textColor = Palette.warning
        }

        updateMenu()
    }

    private func struckThrough(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UI.monospacedDigits(11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.tertiaryLabelColor
        ])
    }

    // MARK: - Menu

    private func updateMenu() {
        let menu = NSMenu()
        if item?.output != nil {
            menu.addItem(menuItem("导出这一张…", #selector(exportOne)))
            menu.addItem(menuItem("在访达中显示", #selector(revealOutput)))
            menu.addItem(.separator())
        }
        if case .failed = item?.state {
            menu.addItem(menuItem("重试", #selector(retry)))
            menu.addItem(.separator())
        }
        menu.addItem(menuItem("在访达中显示原图", #selector(revealSource)))
        menu.addItem(menuItem("移除", #selector(removeItem)))
        self.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func exportOne() {
        if let item { queue?.exportOne(item) }
    }

    @objc private func revealOutput() {
        if let url = item?.output?.url { queue?.revealInFinder(url) }
    }

    @objc private func revealSource() {
        if let url = item?.url { queue?.revealInFinder(url) }
    }

    @objc private func retry() {
        if let item { queue?.retry(item) }
    }

    @objc private func removeItem() {
        if let item { queue?.remove(item) }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let url = item?.output?.url {
                queue?.revealInFinder(url)
            } else if let url = item?.url {
                queue?.revealInFinder(url)
            }
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Dragging out

    override func mouseDragged(with event: NSEvent) {
        guard let url = item?.output?.url else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(url.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let frameInWindow = convert(thumbView.frame, to: nil)
        draggingItem.setDraggingFrame(frameInWindow,
                                      contents: item?.thumbnail ?? BrandIcon.image(size: 40))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
