import Cocoa
import CoreText

final class StatusItemView: NSView {
    var stats = Stats() { didSet { updateWidth(); needsDisplay = true } }

    private var oswaldFont: NSFont!
    private var iconCPU: NSImage!
    private var iconGPU: NSImage!
    private var iconDownK: NSImage!
    private var iconDownM: NSImage!
    private var iconUpK: NSImage!
    private var iconUpM: NSImage!

    // Layout constants (points)
    // Each block: icon on top (y=1, h=7), number on bottom (y=8)
    // Block height=18, min width=16, gap between blocks=8
    private let blockH: CGFloat = 18
    private let iconY: CGFloat = 1
    private let iconH: CGFloat = 7
    private let numberY: CGFloat = 8
    private let minBlockW: CGFloat = 16
    private let blockGap: CGFloat = 8
    private let fontSize: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        loadResources()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadResources()
    }

    private func loadResources() {
        if let fontURL = Bundle.main.url(forResource: "Oswald-Light", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        oswaldFont = NSFont(name: "Oswald", size: fontSize)
            ?? NSFont(name: "Oswald-Light", size: fontSize)
            ?? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)

        iconCPU = loadIcon("cpu")
        iconGPU = loadIcon("gpu")
        iconDownK = loadIcon("download-k")
        iconDownM = loadIcon("download-m")
        iconUpK = loadIcon("upload-k")
        iconUpM = loadIcon("upload-m")
    }

    private func loadIcon(_ name: String) -> NSImage {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = NSImage(contentsOfFile: path) else {
            return NSImage()
        }
        // Scale to exactly 7pt tall (14px @2x), preserve aspect ratio
        let scale = iconH / (img.size.height / 2)
        img.size = NSSize(width: (img.size.width / 2) * scale, height: iconH)
        img.isTemplate = true
        return img
    }

    private func textWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: oswaldFont!]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private func blockWidth(icon: NSImage, text: String) -> CGFloat {
        let tw = textWidth(text)
        return max(minBlockW, max(icon.size.width, tw))
    }

    private func blocks() -> [(icon: NSImage, text: String)] {
        let dl = stats.downloadDisplay
        let ul = stats.uploadDisplay
        return [
            (iconCPU, "\(stats.cpuLoad)"),
            (iconGPU, "\(stats.gpuLoad)"),
            (dl.isMega ? iconDownM : iconDownK, "\(dl.value)"),
            (ul.isMega ? iconUpM : iconUpK, "\(ul.value)"),
        ]
    }

    private func totalWidth() -> CGFloat {
        var w: CGFloat = 0
        for (i, b) in blocks().enumerated() {
            w += blockWidth(icon: b.icon, text: b.text)
            if i < 3 { w += blockGap }
        }
        return w
    }

    func updateWidth() {
        let w = totalWidth()
        if abs(frame.width - w) > 0.5 {
            setFrameSize(NSSize(width: w, height: frame.height))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let allBlocks = blocks()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: oswaldFont!,
            .foregroundColor: NSColor.controlTextColor,
        ]

        let topOffset = (bounds.height - blockH) / 2
        var x: CGFloat = 0

        for (i, block) in allBlocks.enumerated() {
            let bw = blockWidth(icon: block.icon, text: block.text)
            let iw = block.icon.size.width

            // Icon: centered horizontally, top-down y=1, height=7
            let iconX = x + (bw - iw) / 2
            let iconDrawY = bounds.height - topOffset - iconY - iconH
            drawTinted(block.icon, in: NSRect(x: iconX, y: iconDrawY, width: iw, height: iconH))

            // Number: left-aligned, top-down y=8
            let textSize = (block.text as NSString).size(withAttributes: attrs)
            let textX = x
            let textDrawY = bounds.height - topOffset - numberY - textSize.height
            (block.text as NSString).draw(at: NSPoint(x: textX, y: textDrawY), withAttributes: attrs)

            x += bw
            if i < allBlocks.count - 1 { x += blockGap }
        }
    }

    private func drawTinted(_ image: NSImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSColor.controlTextColor.setFill()
        ctx.fill(rect)
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
