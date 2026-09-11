import AppKit
import MarkletCore

@MainActor
final class DemoSurface: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

@MainActor
final class Demo: NSObject, NSTextViewDelegate, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    let source = NSTextView()
    let preview = NSTextView()
    let colors = NSSegmentedControl(labels: ["System", "Warm", "Dark"], trackingMode: .selectOne,
                                    target: nil, action: nil)

    override init() {
        super.init()
        window.title = "Marklet Core Demo"
        window.delegate = self
        window.minSize = NSSize(width: 840, height: 560)
        window.appearance = NSAppearance(named: .aqua)
        let root = DemoSurface()
        root.orientation = .vertical
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        window.contentView = root
        let title = NSTextField(labelWithString: "Markdown, rendered natively.")
        title.font = .boldSystemFont(ofSize: 26)
        let subtitle = NSTextField(labelWithString: "Edit the source. Change the text palette. Built with the public Marklet core.")
        subtitle.textColor = .secondaryLabelColor
        colors.selectedSegment = 1
        colors.target = self
        colors.action = #selector(updatePreview)
        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(colors)
        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.distribution = .fillEqually
        columns.spacing = 20
        for (label, text) in [("MARKDOWN SOURCE", source), ("NATIVE ATTRIBUTED TEXT", preview)] {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 10
            let caption = NSTextField(labelWithString: label)
            caption.font = .systemFont(ofSize: 11, weight: .semibold)
            caption.textColor = .secondaryLabelColor
            column.addArrangedSubview(caption)
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.documentView = text
            text.isRichText = false
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width: 20, height: 20)
            column.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            columns.addArrangedSubview(column)
        }
        root.addArrangedSubview(columns)
        columns.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        source.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        source.isAutomaticQuoteSubstitutionEnabled = false
        source.isAutomaticDashSubstitutionEnabled = false
        source.string = """
        # A little room to think

        Keep an idea **clear**, a detail *gentle*,
        and something important ***unmistakable***.

        ## From syntax to text

        A small `let idea = 42` belongs in monospace.

        ```swift
        let note = "Made for macOS"
        print(note)
        ```

        Follow [Marklet](https://getmarklet.com).
        """
        source.delegate = self
        preview.isEditable = false
        preview.isRichText = true
        updatePreview()
    }

    func textDidChange(_ notification: Notification) { updatePreview() }
    func windowWillClose(_ notification: Notification) { NSApplication.shared.terminate(nil) }

    @objc func updatePreview() {
        var style = MarkdownTextStyle()
        style.bodyFont = .systemFont(ofSize: 17)
        window.appearance = NSAppearance(named: colors.selectedSegment == 2 ? .darkAqua : .aqua)
        if colors.selectedSegment == 1 {
            style.bodyColor = NSColor(srgbRed: 0.24, green: 0.19, blue: 0.15, alpha: 1)
            style.headingColor = NSColor(srgbRed: 0.43, green: 0.29, blue: 0.13, alpha: 1)
            style.boldColor = .systemPurple
            style.italicColor = .systemTeal
            style.boldItalicColor = .systemPink
        }
        preview.linkTextAttributes = [.foregroundColor: style.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        do {
            preview.textStorage?.setAttributedString(try MarkdownTextRenderer(style: style).render(source.string))
        } catch {
            preview.string = "Could not render this input: \(error.localizedDescription)"
        }
    }

    func snapshot(to url: URL) throws {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var clean = png.prefix(8)
        var offset = 8
        let allowed = ["IHDR", "PLTE", "tRNS", "IDAT", "IEND"]
        while offset + 12 <= png.count {
            let length = png[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            let end = offset + length + 12
            guard end <= png.count else { throw CocoaError(.fileWriteUnknown) }
            let type = String(decoding: png[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if allowed.contains(type) { clean.append(png[offset..<end]) }
            offset = end
        }
        try clean.write(to: url)
    }
}

@main
struct CoreDemo {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let demo = Demo()
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--snapshot" {
            try demo.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        demo.window.center()
        demo.window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(demo) { app.run() }
    }
}
