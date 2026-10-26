//
//  EmptyStateView.swift
//  PicPress
//

import AppKit

final class EmptyStateView: NSView {
    var onChoose: (() -> Void)?

    private let border = DashedBorderView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        border.cornerRadius = 16
        border.strokeColor = .secondaryLabelColor
        border.fillColor = NSColor.labelColor.withAlphaComponent(0.015)
        addSubview(border)

        let circle = NSView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 33
        circle.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.11).cgColor

        let symbol = NSImageView()
        symbol.image = Glyph.image("photo.stack", pointSize: 26)
        symbol.contentTintColor = Palette.accent
        symbol.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(symbol)

        let title = UI.label("把图片拖到这里", size: 15, weight: .semibold)
        title.alignment = .center

        let subtitle = UI.label("支持 JPG · PNG · HEIC · TIFF · GIF · WebP · BMP", size: 11.5, color: .secondaryLabelColor)
        subtitle.alignment = .center

        let button = NSButton(title: "选择图片…", target: self, action: #selector(chooseTapped))
        button.bezelStyle = .rounded
        button.controlSize = .large
        UI.applyPrimaryTint(to: button)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let hint = UI.label("默认 80% 质量输出 WebP，可随时调整", size: 10.5, color: .tertiaryLabelColor)
        hint.alignment = .center

        let stack = NSStackView(views: [circle, title, subtitle, button, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: circle)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(12, after: button)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            border.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            border.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            border.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            circle.widthAnchor.constraint(equalToConstant: 66),
            circle.heightAnchor.constraint(equalToConstant: 66),
            symbol.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: circle.centerYAnchor),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40)
        ])
    }

    @objc private func chooseTapped() {
        onChoose?()
    }
}
