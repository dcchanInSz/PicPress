//
//  FileListView.swift
//  PicPress
//

import AppKit

final class FileListView: NSView {
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let stack = NSStackView()
    private var rows: [UUID: FileRowView] = [:]

    private weak var queue: CompressionQueue?

    private let topInset: CGFloat = 8
    private let bottomInset: CGFloat = 10
    private let rowSpacing: CGFloat = 1

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        documentView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.documentView = documentView

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = true
        documentView.addSubview(stack)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds

        let width = max(1, scrollView.contentView.bounds.width)
        let contentHeight = CGFloat(rows.count) * FileRowView.height
            + CGFloat(max(0, rows.count - 1)) * rowSpacing
        stack.frame = NSRect(x: 0, y: topInset, width: width, height: contentHeight)
        documentView.frame = NSRect(x: 0,
                                    y: 0,
                                    width: width,
                                    height: max(contentHeight + topInset + bottomInset,
                                                scrollView.contentView.bounds.height))
        stack.layoutSubtreeIfNeeded()
    }

    // MARK: - Updating

    func update(items: [CompressionQueue.Item], queue: CompressionQueue) {
        self.queue = queue
        let ids = Set(items.map(\.id))

        for (id, row) in rows where !ids.contains(id) {
            row.removeFromSuperview()
            rows.removeValue(forKey: id)
        }

        for item in items {
            let row: FileRowView
            if let existing = rows[item.id] {
                row = existing
            } else {
                row = FileRowView()
                row.queue = queue
                rows[item.id] = row
            }
            row.configure(with: item, isRunning: queue.isRunning)
        }

        let currentOrder = stack.arrangedSubviews.compactMap { ($0 as? FileRowView)?.item?.id }
        if currentOrder != items.map(\.id) {
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
            }
            for item in items {
                if let row = rows[item.id] {
                    stack.addArrangedSubview(row)
                }
            }
        }

        needsLayout = true
    }
}
