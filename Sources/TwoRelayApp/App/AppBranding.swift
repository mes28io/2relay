import AppKit
import Foundation

enum AppBranding {
    static let bundledLogoName = "2relay-logo"

    static func loadLogoImage() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: bundledLogoName, withExtension: "png"),
           let bundledImage = NSImage(contentsOf: bundledURL) {
            return bundledImage
        }

        return nil
    }

    static func loadMenuBarTemplateImage() -> NSImage? {
        guard let image = loadLogoImage(),
              let copy = image.copy() as? NSImage else {
            return nil
        }

        copy.isTemplate = true
        copy.size = NSSize(width: 18, height: 18)
        return copy
    }

    static func loadDockWaveformImage() -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "2relay"
        ) else {
            return nil
        }

        let config = NSImage.SymbolConfiguration(pointSize: 220, weight: .regular)
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        image.isTemplate = false
        return renderDockIconImage(from: image)
    }

    static func loadDockLogoImage() -> NSImage? {
        guard let logo = loadLogoImage(),
              let copy = logo.copy() as? NSImage else {
            return nil
        }

        copy.isTemplate = false
        return renderDockIconImage(from: copy)
    }

    @MainActor
    static func applyDockIcon() {
        guard let image = loadDockLogoImage() ?? loadDockWaveformImage() else {
            return
        }

        NSApp.applicationIconImage = image
        NSApp.dockTile.contentView = makeDockTileContentView(with: image)
        NSApp.dockTile.display()
    }

    private static func renderDockIconImage(from source: NSImage) -> NSImage? {
        let targetSize = NSSize(width: 1024, height: 1024)
        let rect = NSRect(origin: .zero, size: targetSize)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        rect.fill()

        let radius = rect.width * 0.215
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        clipPath.addClip()

        source.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        result.isTemplate = false
        return result
    }

    @MainActor
    private static func makeDockTileContentView(with image: NSImage) -> NSView {
        let tileSize = NSSize(width: 128, height: 128)
        let container = NSView(frame: NSRect(origin: .zero, size: tileSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let inset: CGFloat = 11
        let imageView = NSImageView(frame: container.bounds.insetBy(dx: inset, dy: inset))
        imageView.autoresizingMask = [.width, .height]
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = false

        container.addSubview(imageView)
        return container
    }
}
