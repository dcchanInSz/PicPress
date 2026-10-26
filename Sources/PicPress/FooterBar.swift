//
//  FooterBar.swift
//  PicPress
//

import AppKit

final class FooterBar: NSView {
    var onStop: (() -> Void)?
    var onAdd: (() -> Void)?
    var onClear: (() -> Void)?
    var onExport: (() -> Void)?

    private let progressBar = NSProgressIndicator()
    private let statusLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private let stopButton: NSButton
    private let addButton: NSButton
    private let clearButton: NSButton
    private let exportButton: NSButton

    init() {
        stopButton = NSButton(title: "停止", target: nil, action: nil)
        addButton = NSButton(title: "添加", target: nil, action: nil)
        clearButton = NSButton(title: "清空", target: nil, action: nil)
        exportButton = NSButton(title: "全部导出", target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.controlSize = .small
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true

        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.lineBreakMode = .byTruncatingTail

        let statusGroup = NSStackView(views: [progressBar, statusLabel])
        statusGroup.orientation = .horizontal
        statusGroup.alignment = .centerY
        statusGroup.spacing = 9
        statusGroup.translatesAutoresizingMaskIntoConstraints = false

        configure(addButton, title: "添加", image: "plus", action: #selector(addTapped))
        configure(clearButton, title: "清空", image: nil, action: #selector(clearTapped))
        configure(stopButton, title: "停止", image: nil, action: #selector(stopTapped))
        stopButton.isHidden = true

        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .regular
        exportButton.font = .systemFont(ofSize: 12, weight: .medium)
        exportButton.image = Glyph.image("square.and.arrow.down", pointSize: 11, weight: .medium)
        exportButton.imagePosition = .imageLeading
        exportButton.keyEquivalent = "\r"
        UI.applyPrimaryTint(to: exportButton)
        exportButton.target = self
        exportButton.action = #selector(exportTapped)
        exportButton.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [stopButton, addButton, clearButton, exportButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.setCustomSpacing(12, after: stopButton)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statusGroup)
        addSubview(buttons)

        NSLayoutConstraint.activate([
            progressBar.widthAnchor.constraint(equalToConstant: 108),
            progressBar.heightAnchor.constraint(equalToConstant: 10),

            statusGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusGroup.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),

            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configure(_ button: NSButton, title: String, image: String?, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12)
        if let image {
            button.image = Glyph.image(image, pointSize: 11)
            button.imagePosition = .imageLeading
        }
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Update

    func update(with queue: CompressionQueue) {
        if queue.isRunning {
            progressBar.isHidden = false
            progressBar.doubleValue = queue.progress
            statusLabel.stringValue = "压缩中 \(queue.runDone)/\(queue.runTotal)"
            statusLabel.textColor = .secondaryLabelColor
            stopButton.isHidden = false
        } else {
            progressBar.isHidden = true
            stopButton.isHidden = true
            statusLabel.attributedStringValue = summary(for: queue)
        }

        clearButton.isEnabled = !queue.items.isEmpty
        exportButton.isEnabled = !queue.finishedItems.isEmpty
        addButton.isEnabled = true
    }

    private func summary(for queue: CompressionQueue) -> NSAttributedString {
        guard !queue.finishedItems.isEmpty else {
            return NSAttributedString(string: "拖入图片或文件夹即可开始", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
        }

        let text = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        text.append(NSAttributedString(string: "\(queue.finishedItems.count) 张", attributes: base))
        text.append(NSAttributedString(string: "  ·  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.quaternaryLabelColor
        ]))
        text.append(NSAttributedString(
            string: "\(ByteFormat.string(queue.totalSourceBytes)) → \(ByteFormat.string(queue.totalOutputBytes))",
            attributes: [
                .font: UI.monospacedDigits(11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        text.append(NSAttributedString(string: "  ·  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.quaternaryLabelColor
        ]))
        text.append(NSAttributedString(
            string: "节省 \(Int((queue.savedFraction * 100).rounded()))%",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: Palette.positive
            ]))
        return text
    }

    // MARK: - Actions

    @objc private func stopTapped() { onStop?() }
    @objc private func addTapped() { onAdd?() }
    @objc private func clearTapped() { onClear?() }
    @objc private func exportTapped() { onExport?() }
}

// MARK: - Export banner

final class ExportBanner: NSView {
    var onReveal: (() -> Void)?

    private let label = UI.label("", size: 11, color: .secondaryLabelColor)
    private let revealButton = NSButton(title: "在访达中显示", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let icon = NSImageView()
        icon.image = Glyph.image("checkmark.circle.fill", pointSize: 11, weight: .semibold)
        icon.contentTintColor = Palette.positive
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        revealButton.bezelStyle = .inline
        revealButton.isBordered = false
        revealButton.contentTintColor = Palette.accent
        revealButton.font = .systemFont(ofSize: 11, weight: .medium)
        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        revealButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        addSubview(revealButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -8),

            revealButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.positive.withAlphaComponent(0.08)
            .cgColor(for: effectiveAppearance)
    }

    func set(summary: CompressionQueue.ExportSummary) {
        label.stringValue = "已导出 \(summary.count) 个文件（\(ByteFormat.string(summary.totalBytes))）到 \(summary.folder.lastPathComponent)"
    }

    @objc private func revealTapped() { onReveal?() }
}

// MARK: - Drag overlay

final class DropOverlay: NSView {
    private let border = DashedBorderView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isHidden = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        border.cornerRadius = 14
        border.strokeColor = Palette.accent
        border.fillColor = Palette.accent.withAlphaComponent(0.06)
        border.lineWidth = 2
        border.dashPattern = [8, 6]
        addSubview(border)

        let icon = NSImageView()
        icon.image = Glyph.image("arrow.down.circle.fill", pointSize: 30)
        icon.contentTintColor = Palette.accent
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UI.label("松手开始压缩", size: 13, weight: .semibold, color: Palette.accent)
        label.alignment = .center

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            border.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            border.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            border.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
