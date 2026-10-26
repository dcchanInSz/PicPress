//
//  HeaderBar.swift
//  PicPress
//

import AppKit

/// Slider that reports when the user lets go, so we only re-compress on commit.
final class CommitSlider: NSSlider {
    var onCommit: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onCommit?()
    }

    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        onCommit?()
    }
}

final class HeaderBar: NSView {
    private let iconView = NSImageView()
    private let titleLabel = UI.label("PicPress", size: 14, weight: .semibold)
    private let subtitleLabel = UI.label("批量压缩为 WebP", size: 11, color: .secondaryLabelColor)
    private let qualityLabel = UI.label("质量", size: 11, color: .secondaryLabelColor)
    private let qualityValue = UI.label("80%", size: 12, weight: .semibold)
    private let edgeLabel = UI.label("长边", size: 11, color: .secondaryLabelColor)
    private let edgePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let separator = NSBox()

    let qualitySlider = CommitSlider()

    var onQualityLive: ((Double) -> Void)?
    var onQualityCommit: ((Double) -> Void)?
    var onEdgeChange: ((Int?) -> Void)?

    private static let edgeOptions: [(title: String, value: Int)] = [
        ("原始", 0), ("4096", 4096), ("2048", 2048), ("1600", 1600), ("1280", 1280), ("800", 800)
    ]

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        iconView.image = BrandIcon.image(size: 32)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 0
        titles.translatesAutoresizingMaskIntoConstraints = false

        qualitySlider.minValue = CompressSettings.qualityRange.lowerBound * 100
        qualitySlider.maxValue = CompressSettings.qualityRange.upperBound * 100
        qualitySlider.doubleValue = CompressSettings.defaultQuality * 100
        qualitySlider.isContinuous = true
        qualitySlider.controlSize = .small
        qualitySlider.target = self
        qualitySlider.action = #selector(sliderMoved)
        qualitySlider.onCommit = { [weak self] in self?.commitQuality() }
        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.trackFillColor = Palette.accent

        qualityValue.alignment = .left
        qualityValue.font = UI.monospacedDigits(12, weight: .semibold)

        edgePopup.removeAllItems()
        for option in Self.edgeOptions {
            edgePopup.addItem(withTitle: option.title)
            edgePopup.lastItem?.tag = option.value
        }
        edgePopup.selectItem(withTag: 0)
        edgePopup.controlSize = .small
        edgePopup.font = .systemFont(ofSize: 11)
        edgePopup.target = self
        edgePopup.action = #selector(edgeChanged)
        edgePopup.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let controls = NSStackView(views: [
            qualityLabel, qualitySlider, qualityValue, separator, edgeLabel, edgePopup
        ])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.setCustomSpacing(12, after: qualityValue)
        controls.setCustomSpacing(12, after: separator)
        controls.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titles)
        addSubview(controls)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titles.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            titles.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -16),

            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            controls.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            controls.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),

            qualitySlider.widthAnchor.constraint(equalToConstant: 124),
            qualityValue.widthAnchor.constraint(equalToConstant: 36),
            separator.heightAnchor.constraint(equalToConstant: 20),
            edgePopup.widthAnchor.constraint(equalToConstant: 84)
        ])

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // MARK: - State

    func setQuality(_ quality: Double, notify: Bool = false) {
        qualitySlider.doubleValue = quality * 100
        qualityValue.stringValue = "\(Int((quality * 100).rounded()))%"
        if notify { onQualityLive?(quality) }
    }

    func setMaxEdge(_ value: Int?) {
        edgePopup.selectItem(withTag: value ?? 0)
    }

    // MARK: - Actions

    @objc private func sliderMoved() {
        let value = qualitySlider.doubleValue / 100
        qualityValue.stringValue = "\(Int(qualitySlider.doubleValue.rounded()))%"
        onQualityLive?(value)
    }

    private func commitQuality() {
        onQualityCommit?(qualitySlider.doubleValue / 100)
    }

    @objc private func edgeChanged() {
        let tag = edgePopup.selectedTag()
        onEdgeChange?(tag == 0 ? nil : tag)
    }
}
