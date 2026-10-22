// Renders docs/keypsake.mp4 (1280x720, 30fps) and docs/keypsake.gif (640x360) in the app's design system.
// Run from the repo root:  swiftc -O Resources/Video/render_video.swift -o /tmp/kv && /tmp/kv
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let W = 1280, H = 720, FPS = 30, SECONDS = 11.5
let frames = Int(Double(FPS) * SECONDS)

for f in try FileManager.default.contentsOfDirectory(atPath: "Resources/Fonts") where f.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Resources/Fonts/" + f) as CFURL, .process, nil)
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let ground = hex(0xECEEF2), ink = hex(0x1B1C22), carbon = hex(0x3B3FC4), ghost = hex(0xB8BBD3), cliff = hex(0xD98A2B)
func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size) }
let body = font("MartianGrotesk-Regular", 34), mono = font("MartianMono-Regular", 17), display = font("Redaction-Regular", 112)
let icon = NSImage(contentsOfFile: "Resources/Icon/AppIcon.svg")!

// Easing + timeline helpers
func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func span(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

let message = "Hi Priya, a few thoughts before Thursday: let's move the beta invite to the 14th so support has a full week with the new docs."
let textRect = NSRect(x: 190, y: 250, width: 900, height: 240)

func draw(_ s: String, _ attrs: [NSAttributedString.Key: Any], in r: NSRect) {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 10
    var a = attrs; a[.paragraphStyle] = p
    NSAttributedString(string: s, attributes: a).draw(with: r, options: [.usesLineFragmentOrigin])
}
func label(_ s: String, _ color: NSColor, at pt: NSPoint, alpha: Double) {
    guard alpha > 0 else { return }
    NSAttributedString(string: s, attributes: [.font: mono, .foregroundColor: color.withAlphaComponent(alpha), .kern: 0.6]).draw(at: pt)
}

func frame(_ t: Double) {
    ground.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

    // 1. Key press (0 - 1.8s)
    let iconIn = out(span(t, 0, 0.6)), press = sin(.pi * span(t, 0.75, 1.05)), iconOut = ease(span(t, 1.5, 2.0))
    if iconOut < 1 {
        let size = 220 * (0.92 + 0.08 * iconIn) * (1 - 0.05 * press)
        let r = NSRect(x: Double(W) / 2 - size / 2, y: Double(H) / 2 - size / 2 + 8 * press - 140 * iconOut, width: size, height: size)
        icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: iconIn * (1 - iconOut), respectFlipped: true, hints: nil)
    }

    // 2. Typing with a carbon-copy impression trailing behind (1.9 - 5.0s)
    let typed = Int(Double(message.count) * span(t, 1.9, 4.8))
    let wiped = ease(span(t, 5.5, 5.9))       // 3. selection sweeps, then the box is cleared
    let restore = ease(span(t, 6.9, 7.9))      // 4. the impression slides back and becomes ink
    let shown = String(message.prefix(typed))
    if typed > 0 {
        let offset = 7 * (1 - restore)
        let gr = textRect.offsetBy(dx: offset, dy: offset)
        let ghostAlpha = 0.55 * (1 - restore) + restore
        let ghostColor = restore > 0 ? ink.blended(withFraction: 1 - restore, of: carbon.withAlphaComponent(0.35))! : carbon.withAlphaComponent(0.35)
        draw(shown, [.font: body, .foregroundColor: ghostColor.withAlphaComponent(ghostColor.alphaComponent * ghostAlpha)], in: gr)
        if wiped < 1 {
            let sweep = span(t, 5.0, 5.45)
            let sel = Int(Double(shown.count) * sweep)
            let m = NSMutableAttributedString(string: shown, attributes: [.font: body, .foregroundColor: ink.withAlphaComponent(1 - wiped)])
            if sel > 0 { m.addAttribute(.backgroundColor, value: carbon.withAlphaComponent(0.2 * (1 - wiped)), range: NSRange(location: 0, length: sel)) }
            let blink = t < 4.9 || Int(t * 2.4) % 2 == 0
            if t < 5.0 && blink { m.append(NSAttributedString(string: "|", attributes: [.font: font("MartianGrotesk-Medium", 34), .foregroundColor: carbon])) }
            let p = NSMutableParagraphStyle(); p.lineSpacing = 10
            m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
            m.draw(with: textRect, options: [.usesLineFragmentOrigin])
        }
    }

    // Labels in Martian Mono
    let fadeAll = 1 - ease(span(t, 8.6, 9.1))
    label("TYPING IN MAIL", ink.withAlphaComponent(0.42), at: NSPoint(x: 190, y: 200), alpha: span(t, 2.0, 2.4) * (1 - span(t, 5.4, 5.7)))
    label("BOX CLEARED", cliff, at: NSPoint(x: 190, y: 200), alpha: span(t, 5.7, 6.0) * (1 - span(t, 6.9, 7.2)))
    label("KEPT. VERSION 3 OF 3", carbon, at: NSPoint(x: 190, y: 200), alpha: span(t, 7.3, 7.7) * fadeAll)

    // Ribbon: text length per version, the last one (right before the loss) in amber
    let bars: [(CGFloat, NSColor)] = [(0.3, ghost), (0.62, ghost), (1.0, cliff)]
    for (i, b) in bars.enumerated() {
        let grow = out(span(t, 6.1 + Double(i) * 0.15, 6.6 + Double(i) * 0.15)) * fadeAll
        guard grow > 0 else { continue }
        let h = 46 * b.0 * grow
        b.1.withAlphaComponent(fadeAll).setFill()
        NSBezierPath(roundedRect: NSRect(x: 190 + CGFloat(i) * 16, y: 560 - h, width: 9, height: h), xRadius: 2, yRadius: 2).fill()
    }

    // Ending carbon wipes the copy away
    if t > 8.6 { ink.withAlphaComponent(0).set() }
    if fadeAll < 1 {
        ground.withAlphaComponent(1 - fadeAll).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    }

    // 5. Wordmark
    let end = out(span(t, 9.0, 9.8))
    if end > 0 {
        let word = NSAttributedString(string: "keypsake", attributes: [.font: display, .foregroundColor: ink.withAlphaComponent(end), .kern: -1.5])
        let ws = word.size()
        let iconSize: CGFloat = 104, gap: CGFloat = 28
        let total = iconSize + gap + ws.width
        let x0 = (CGFloat(W) - total) / 2, y0 = CGFloat(H) / 2 - 70 + 14 * (1 - end)
        icon.draw(in: NSRect(x: x0, y: y0 + (ws.height - iconSize) / 2 + 6, width: iconSize, height: iconSize),
                  from: .zero, operation: .sourceOver, fraction: end, respectFlipped: true, hints: nil)
        word.draw(at: NSPoint(x: x0 + iconSize + gap, y: y0))
        let tag = NSAttributedString(string: "everything you type, kept.", attributes: [
            .font: font("MartianMono-Regular", 22), .foregroundColor: ink.withAlphaComponent(0.62 * out(span(t, 9.5, 10.2))), .kern: 0.8])
        tag.draw(at: NSPoint(x: (CGFloat(W) - tag.size().width) / 2, y: y0 + ws.height + 26))
        carbon.withAlphaComponent(out(span(t, 9.7, 10.4))).setFill()
        let lw = 120 * out(span(t, 9.7, 10.4))
        NSRect(x: (CGFloat(W) - lw) / 2, y: y0 + ws.height + 74, width: lw, height: 2).fill()
    }
}

func render(_ t: Double) -> CGImage {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    frame(t)
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

// MP4
let mp4 = URL(fileURLWithPath: "docs/keypsake.mp4")
try? FileManager.default.removeItem(at: mp4)
let writer = try AVAssetWriter(outputURL: mp4, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// GIF (half size, 15fps)
let gifURL = URL(fileURLWithPath: "docs/keypsake.gif") as CFURL
let gif = CGImageDestinationCreateWithURL(gifURL, UTType.gif.identifier as CFString, (frames + 1) / 2, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

for i in 0..<frames {
    let img = render(Double(i) / Double(FPS))
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let c = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(FPS)))

    if i % 2 == 0 {
        let small = CGContext(data: nil, width: W / 2, height: H / 2, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        small.interpolationQuality = .high
        small.draw(img, in: CGRect(x: 0, y: 0, width: W / 2, height: H / 2))
        let delay = (i >= frames - 2) ? 2.0 : 2.0 / Double(FPS)
        CGImageDestinationAddImage(gif, small.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
CGImageDestinationFinalize(gif)
// Poster frames for review
for (name, t) in [("frame-typing", 3.6), ("frame-restore", 7.6), ("frame-end", 11.0)] {
    let rep = NSBitmapImageRep(cgImage: render(t))
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? "\(CommandLine.arguments[1])/\(name).png" : "/dev/null"))
}
print("wrote docs/keypsake.mp4 and docs/keypsake.gif, status \(writer.status.rawValue)")
