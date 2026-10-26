//
//  Controls.swift
//  PicPress
//
//  Small reusable pieces of chrome.
//

import AppKit

enum UI {
    static func label(_ text: String,
                      size: CGFloat = 12,
                      weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func digits(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: label.font?.pointSize ?? 11,
                                               weight: .regular)
    }

    static func monospacedDigits(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// Gives a button the accent "primary action" look on every supported system.
    static func applyPrimaryTint(to button: NSButton) {
        if #available(macOS 26.0, *) {
            button.tintProminence = .primary
        } else {
            button.bezelColor = Palette.accent
            button.contentTintColor = .white
        }
    }
}

final class HairlineView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.hairline.cgColor(for: effectiveAppearance)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A rounded, tinted badge used for the "-87%" chips.
final class PillLabel: NSView {
    private let label = UI.label("", size: 10.5, weight: .semibold)

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet { label.textColor = textColor }
    }

    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        label.font = UI.monospacedDigits(10.5, weight: .semibold)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 17)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = fillColor.cgColor(for: effectiveAppearance)
    }
}

/// Rounded dashed outline, used for the empty state and the drag overlay.
final class DashedBorderView: NSView {
    private let shape = CAShapeLayer()

    var cornerRadius: CGFloat = 16
    var inset: CGFloat = 1
    var lineWidth: CGFloat = 1.5
    var dashPattern: [NSNumber] = [7, 6]
    var strokeColor: NSColor = .secondaryLabelColor
    var fillColor: NSColor = .clear

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(shape)
        shape.fillColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shape.frame = bounds
        let rect = bounds.insetBy(dx: inset + lineWidth / 2, dy: inset + lineWidth / 2)
        shape.path = CGPath(roundedRect: rect,
                            cornerWidth: cornerRadius,
                            cornerHeight: cornerRadius,
                            transform: nil)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        needsLayout = true
    }

    private func updateColors() {
        shape.strokeColor = strokeColor.cgColor(for: effectiveAppearance)
        shape.lineWidth = lineWidth
        shape.lineDashPattern = dashPattern
        shape.fillColor = fillColor.cgColor(for: effectiveAppearance)
    }
}

/// The colourful rounded-square app mark, drawn in code so there is no asset dependency.
enum BrandIcon {
    static func image(size: CGFloat, cornerRadius: CGFloat? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = cornerRadius ?? size * 0.226
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()
        Palette.brandGradient.draw(in: path, angle: -50)

        guard let symbol = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left",
                                   accessibilityDescription: nil) else { return image }
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.50, weight: .bold)
        guard let configured = symbol.withSymbolConfiguration(configuration) else { return image }

        let symbolSize = configured.size
        let tinted = NSImage(size: symbolSize)
        tinted.lockFocus()
        configured.draw(in: NSRect(origin: .zero, size: symbolSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let target = NSRect(x: (size - symbolSize.width) / 2,
                            y: (size - symbolSize.height) / 2,
                            width: symbolSize.width,
                            height: symbolSize.height)
        tinted.draw(in: target)
        return image
    }
}
