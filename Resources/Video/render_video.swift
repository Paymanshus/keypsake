// Renders docs/keypsake.mp4 (1280x720, 30fps) and docs/keypsake.gif (640x360) in the app's design system.
// Story: a 47-minute Claude Code prompt dies to a connection error, ↑ brings back nothing, "!", ohno.gif, never again, keypsake.
// Run from the repo root:  swiftc -O Resources/Video/render_video.swift -o /tmp/kv && /tmp/kv [poster-frame dir]
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let W = 1280, H = 720, FPS = 30, SECONDS = 35.5
let frames = Int(Double(FPS) * SECONDS)

for f in try FileManager.default.contentsOfDirectory(atPath: "Resources/Fonts") where f.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Resources/Fonts/" + f) as CFURL, .process, nil)
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let ground = hex(0xECEEF2), ink = hex(0x1B1C22), carbon = hex(0x3B3FC4), ghost = hex(0xB8BBD3), cliff = hex(0xD98A2B)
let carbonDark = hex(0x8C90FF), paper = hex(0xF8F9FB)
func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size) }
let mono = font("MartianMono-Regular", 20), term = font("MartianMono-Regular", 21), display = font("Redaction-Regular", 112)
let icon = NSImage(contentsOfFile: "Resources/Icon/AppIcon.svg")!

// Easing + timeline helpers
func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func span(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func pop(_ x: Double) -> Double { let c = 1.70158; return x <= 0 ? 0 : 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }  // back-out overshoot
func bump(_ t: Double, _ a: Double, _ b: Double) -> Double { sin(.pi * span(t, a, b)) }
var cg: CGContext { NSGraphicsContext.current!.cgContext }

let prompt = "context: we're moving off the legacy session store before the 1st. sessions go to redis with no ttl right now, which is why the box fell over in march. read all of this before you start. ok so. refactor the auth flow so sessions survive a server restart. keep old tokens valid for 7 days, then expire them quietly. write the migration and make it reversible. add tests for the edge case where the clock jumps. update the docs but keep them short, nobody reads them. do NOT touch the billing module. i mean it. last time you touched billing we refunded one guy in ohio four times. also rename SessionManagerFactoryImpl to something a human would say out loud. think hard. take your time. this is the one. make no mistakes. pls"
let totalWords = 1240, totalMinutes = 47   // the time-lapse claims ~26 wpm, which is what a careful prompt takes

// Claude Code's dark theme
let termBg = hex(0x1E1E1E), claude = hex(0xD77757), ccText = hex(0xFFFFFF), ccDim = hex(0x999999), ccBorder = hex(0x888888), ccError = hex(0xFF6B80)

let window = NSRect(x: 170, y: 104, width: 940, height: 470)
let fullBox = NSRect(x: 196, y: 164, width: 888, height: 360), lineBox = NSRect(x: 196, y: 474, width: 888, height: 50)
func lerp(_ a: NSRect, _ b: NSRect, _ k: Double) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * k, y: a.minY + (b.minY - a.minY) * k, width: a.width + (b.width - a.width) * k, height: a.height + (b.height - a.height) * k)
}
func commas(_ n: Int) -> String { n >= 1000 ? "\(n / 1000),\(String(format: "%03d", n % 1000))" : "\(n)" }

func para(_ m: NSMutableAttributedString) -> NSMutableAttributedString {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 9
    m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length)); return m
}
func promptLine(_ s: String, _ color: NSColor, caret: Bool, alpha: Double = 1) -> NSMutableAttributedString {
    let m = NSMutableAttributedString(string: "> ", attributes: [.font: term, .foregroundColor: ccDim.withAlphaComponent(alpha)])
    m.append(NSAttributedString(string: s, attributes: [.font: term, .foregroundColor: color]))
    if caret { m.append(NSAttributedString(string: "▌", attributes: [.font: term, .foregroundColor: ccText.withAlphaComponent(0.85 * alpha)])) }
    return para(m)
}
// Draws text pinned to the bottom of the box once it overflows, like a terminal scrolling.
func scrolled(_ m: NSAttributedString, in r: NSRect, dx: CGFloat = 0, dy: CGFloat = 0) {
    let h = m.boundingRect(with: NSSize(width: r.width, height: 10_000), options: [.usesLineFragmentOrigin]).height
    cg.saveGState(); NSBezierPath(rect: r.insetBy(dx: -12, dy: 0)).addClip()
    m.draw(with: NSRect(x: r.minX + dx, y: r.minY + min(0, r.height - h) + dy, width: r.width, height: h + 20), options: [.usesLineFragmentOrigin])
    // fade out the line that scrolls off the top
    NSGradient(starting: termBg, ending: termBg.withAlphaComponent(0))!.draw(in: NSRect(x: r.minX - 12, y: r.minY, width: r.width + 24, height: 26), angle: 90)
    cg.restoreGState()
}
func text(_ s: String, _ f: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .kern: kern])
}
func runs(_ parts: [(String, NSColor)], _ f: NSFont = term) -> NSAttributedString {
    let m = NSMutableAttributedString(); for (s, c) in parts { m.append(text(s, f, c)) }; return m
}
func label(_ s: String, _ color: NSColor, alpha: Double) {
    guard alpha > 0 else { return }
    text(s, mono, color.withAlphaComponent(color.alphaComponent * alpha), kern: 0.6).draw(at: NSPoint(x: 170, y: 62))
}
func keycap(_ s: String, alpha: Double, press: Double) {
    guard alpha > 0 else { return }
    let t = text(s, font("MartianMono-Medium", 20), ink.withAlphaComponent(0.8 * alpha), kern: 1)
    let w = max(76, t.size().width + 48), x = (CGFloat(W) - w) / 2, y: CGFloat = 600, d = 5 * press
    ink.withAlphaComponent(0.22 * alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y + 6, width: w, height: 58), xRadius: 12, yRadius: 12).fill()
    let face = NSBezierPath(roundedRect: NSRect(x: x, y: y + d, width: w, height: 58), xRadius: 12, yRadius: 12)
    paper.withAlphaComponent(alpha).setFill(); face.fill()
    ink.withAlphaComponent(0.14 * alpha).setStroke(); face.lineWidth = 1.5; face.stroke()
    t.draw(at: NSPoint(x: x + (w - t.size().width) / 2, y: y + d + (58 - t.size().height) / 2))
}
func centered(_ a: NSAttributedString, y: CGFloat) { a.draw(at: NSPoint(x: (CGFloat(W) - a.size().width) / 2, y: y)) }

// After the fix, swipe up through other places people type: it's not just terminals
let swipes = [26.2, 28.1, 30.0]
func scrollPos(_ t: Double) -> Double { swipes.reduce(0) { $0 + ease(span(t, $1, $1 + 0.6)) } }
let ui = font("MartianGrotesk-Regular", 22), uiSmall = font("MartianGrotesk-Regular", 16)

func appWindow(_ r: NSRect, title: String) {
    let sh = NSShadow(); sh.shadowColor = ink.withAlphaComponent(0.12); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10)
    cg.saveGState(); sh.set(); paper.setFill(); NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill(); cg.restoreGState()
    for (i, c) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 20 + CGFloat(i) * 20, y: r.minY + 15, width: 12, height: 12)).fill()
    }
    let tt = text(title, font("MartianMono-Regular", 14), ink.withAlphaComponent(0.45))
    tt.draw(at: NSPoint(x: r.midX - tt.size().width / 2, y: r.minY + 12))
    ink.withAlphaComponent(0.07).setFill(); NSRect(x: r.minX, y: r.minY + 40, width: r.width, height: 1).fill()
}
func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 12, _ a: CGFloat = 0.1) {
    ink.withAlphaComponent(a).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}
func typedText(_ s: String, _ t: Double, _ a: Double, _ dur: Double) -> String { String(s.prefix(Int(Double(s.count) * span(t, a, a + dur)))) }
func wrap(_ s: String, _ f: NSFont, _ color: NSColor, caret: Bool, in r: NSRect) {
    let m = NSMutableAttributedString(attributedString: text(s, f, color))
    if caret { m.append(text("|", f, carbon)) }
    scrolledLight(para(m), in: r)
}
func scrolledLight(_ m: NSAttributedString, in r: NSRect) {
    let h = m.boundingRect(with: NSSize(width: r.width, height: 10_000), options: [.usesLineFragmentOrigin]).height
    cg.saveGState(); NSBezierPath(rect: r.insetBy(dx: -4, dy: 0)).addClip()
    m.draw(with: NSRect(x: r.minX, y: r.minY + min(0, r.height - h), width: r.width, height: h + 20), options: [.usesLineFragmentOrigin])
    cg.restoreGState()
}
// keypsake's little receipt: icon + "kept"
func keptChip(at p: NSPoint, _ k: Double) {
    guard k > 0 else { return }
    cg.saveGState(); cg.translateBy(x: p.x, y: p.y); cg.scaleBy(x: k, y: k)
    let r = NSRect(x: -58, y: -18, width: 116, height: 36)
    let pill = NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18)
    paper.setFill(); pill.fill(); carbon.setStroke(); pill.lineWidth = 1.5; pill.stroke()
    icon.draw(in: NSRect(x: r.minX + 8, y: r.minY + 6, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    text("kept", font("MartianMono-Medium", 16), carbon).draw(at: NSPoint(x: r.minX + 42, y: r.minY + 8))
    cg.restoreGState()
}

func montage(_ t: Double, _ scroll: Double) {
    let win = NSRect(x: 170, y: 104, width: 940, height: 470)
    for k in 1...3 {
        let dy = (CGFloat(k) - CGFloat(scroll)) * CGFloat(H)
        guard abs(dy) < CGFloat(H) else { continue }
        let arrive = swipes[k - 1] + 0.5, blink = Int(t * 2.4) % 2 == 0
        cg.saveGState(); cg.translateBy(x: 0, y: dy)
        let chip = pop(span(t, arrive + 1.15, arrive + 1.4))
        switch k {
        case 1: // chat: the message you went back to edit
            label("THE CHAT MESSAGE YOU WENT BACK TO EDIT.", ink.withAlphaComponent(0.5), alpha: 1)
            appWindow(win, title: "chat")
            ink.withAlphaComponent(0.04).setFill(); NSRect(x: win.minX, y: win.minY + 41, width: 200, height: win.height - 41).fill()
            for i in 0..<5 { bar(win.minX + 24, win.minY + 70 + CGFloat(i) * 34, [120, 90, 140, 100, 70][i], 12, i == 1 ? 0.3 : 0.1) }
            for (i, y) in [win.minY + 70, win.minY + 160].enumerated() {
                ghost.setFill(); NSBezierPath(ovalIn: NSRect(x: win.minX + 230, y: y, width: 40, height: 40)).fill()
                if i == 0 { bar(win.minX + 286, y + 4, 240, 12, 0.14); bar(win.minX + 286, y + 26, 400, 12, 0.08) }
                else { text("can someone write up the plan before tomorrow?", ui, ink.withAlphaComponent(0.85)).draw(at: NSPoint(x: win.minX + 286, y: y + 6)) }
            }
            let box = NSRect(x: win.minX + 230, y: win.maxY - 176, width: win.width - 260, height: 152)
            let bp = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12); ink.withAlphaComponent(0.18).setStroke(); bp.lineWidth = 1.5; bp.stroke()
            let msg = "on it. first we move the beta invite to the 14th so support gets a week with the docs, then the pricing page, then"
            wrap(typedText(msg, t, arrive - 0.3, 1.2), ui, ink, caret: blink || t < arrive + 0.9, in: box.insetBy(dx: 18, dy: 14))
            keptChip(at: NSPoint(x: box.maxX - 70, y: box.minY - 22), chip)
        case 2: // video search you'd run after this one
            label("THE SEARCH YOU'D RUN AFTER THIS VIDEO.", ink.withAlphaComponent(0.5), alpha: 1)
            appWindow(win, title: "videos")
            let field = NSRect(x: win.minX + 90, y: win.minY + 80, width: win.width - 180, height: 64)
            let fp = NSBezierPath(roundedRect: field, xRadius: 32, yRadius: 32); ink.withAlphaComponent(0.2).setStroke(); fp.lineWidth = 1.5; fp.stroke()
            let g = NSBezierPath(ovalIn: NSRect(x: field.minX + 24, y: field.minY + 20, width: 18, height: 18)); g.move(to: NSPoint(x: field.minX + 39, y: field.minY + 36)); g.line(to: NSPoint(x: field.minX + 47, y: field.minY + 44))
            ink.withAlphaComponent(0.45).setStroke(); g.lineWidth = 2.5; g.stroke()
            let q = "that video where a guy rebuilds a synth from scrap"
            let qs = NSMutableAttributedString(attributedString: text(typedText(q, t, arrive - 0.3, 1.1), ui, ink))
            if blink || t < arrive + 0.8 { qs.append(text("|", ui, carbon)) }
            qs.draw(at: NSPoint(x: field.minX + 64, y: field.minY + 19))
            for i in 0..<3 {
                let x = win.minX + 90 + CGFloat(i) * 260, y = win.minY + 190
                ink.withAlphaComponent(0.07).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 240, height: 135), xRadius: 10, yRadius: 10).fill()
                bar(x, y + 150, 200, 12, 0.12); bar(x, y + 172, 130, 12, 0.07)
            }
            keptChip(at: NSPoint(x: field.maxX - 70, y: field.maxY + 22), chip)
        default: // the form that times out
            label("THE FORM THAT TIMED OUT.", ink.withAlphaComponent(0.5), alpha: 1)
            appWindow(win, title: "careers · application")
            text("Why do you want this role?", font("MartianGrotesk-Medium", 26), ink).draw(at: NSPoint(x: win.minX + 60, y: win.minY + 70))
            text("required · 300 words max", uiSmall, ink.withAlphaComponent(0.45)).draw(at: NSPoint(x: win.minX + 60, y: win.minY + 110))
            let area = NSRect(x: win.minX + 60, y: win.minY + 146, width: win.width - 120, height: 200)
            let ap = NSBezierPath(roundedRect: area, xRadius: 10, yRadius: 10); ink.withAlphaComponent(0.18).setStroke(); ap.lineWidth = 1.5; ap.stroke()
            let essay = "I've used your product every day for three years and I keep a list of things I'd fix. The first one is the export screen, which"
            wrap(typedText(essay, t, arrive - 0.3, 1.2), ui, ink, caret: blink || t < arrive + 0.9, in: area.insetBy(dx: 18, dy: 16))
            let btn = NSRect(x: area.maxX - 130, y: area.maxY + 24, width: 130, height: 44)
            ink.setFill(); NSBezierPath(roundedRect: btn, xRadius: 10, yRadius: 10).fill()
            text("Submit", font("MartianGrotesk-Medium", 18), paper).draw(at: NSPoint(x: btn.minX + 32, y: btn.minY + 11))
            keptChip(at: NSPoint(x: area.minX + 58, y: area.maxY + 46), chip)
        }
        cg.restoreGState()
    }
}

// Timeline (seconds)
let typeFrom = 2.9, typeTo = 7.7, submit = 8.3, errorAt = 9.7, escAt = 13.05, upAt = 14.25, bangAt = 14.6
let ohnoAt = 16.4, neverAt = 18.9, backAt = 21.3, keyAt = 22.65, restoreAt = 22.8, outroAt = 32.0, endAt = 32.4

func frame(_ t: Double) {
    ground.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    let scroll = scrollPos(t)
    cg.saveGState(); cg.translateBy(x: 0, y: -CGFloat(scroll) * CGFloat(H))
    let blink = Int(t * 2.4) % 2 == 0

    // 0. Title card
    let tIn = out(span(t, 0.2, 1.0)), tOut = ease(span(t, 2.2, 2.7))
    if tIn > 0 && tOut < 1 {
        let a = tIn * (1 - tOut), f = font("Redaction-Regular", 78)
        centered(text("A prompt so perfect", f, ink.withAlphaComponent(a), kern: -1), y: 238 + 10 * (1 - tIn))
        let dots = String(repeating: ".", count: Int(3 * span(t, 1.15, 1.9) + 0.999))
        let line2 = text("had never been written", f, ink.withAlphaComponent(a), kern: -1)
        let full = text("had never been written...", f, ink, kern: -1)
        let x = (CGFloat(W) - full.size().width) / 2
        line2.draw(at: NSPoint(x: x, y: 330 + 10 * (1 - tIn)))
        text(dots, f, carbon.withAlphaComponent(a)).draw(at: NSPoint(x: x + line2.size().width, y: 330 + 10 * (1 - tIn)))
    }

    // Terminal enters, dims under ohno + never again, comes back for the fix
    let enter = out(span(t, 2.45, 3.1))
    let shake = (t > bangAt + 0.05 && t < bangAt + 0.55) ? 7 * sin(t * 75) * (1 - span(t, bangAt + 0.05, bangAt + 0.55)) : 0
    cg.saveGState(); cg.setAlpha(enter); cg.translateBy(x: shake, y: 18 * (1 - enter))
    if enter > 0 {
        let win = NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14)
        termBg.setFill(); win.fill()
        for (i, c) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: window.minX + 20 + CGFloat(i) * 20, y: window.minY + 15, width: 12, height: 12)).fill()
        }
        let title = text("claude — ~/app", font("MartianMono-Regular", 14), ccDim)
        title.draw(at: NSPoint(x: window.midX - title.size().width / 2, y: window.minY + 12))
        ccText.withAlphaComponent(0.06).setFill(); NSRect(x: window.minX, y: window.minY + 40, width: window.width, height: 1).fill()


        // Input box: full while writing, one line after submit, full again when keypsake restores it
        let shrink = ease(span(t, submit + 0.05, submit + 0.55)), grow = ease(span(t, restoreAt, restoreAt + 0.6))
        let box = lerp(fullBox, lineBox, shrink * (1 - grow))
        let bp = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10); ccBorder.withAlphaComponent(0.7).setStroke(); bp.lineWidth = 1.5; bp.stroke()
        let inner = NSRect(x: box.minX + 16, y: box.minY + 12, width: box.width - 32, height: box.height - 26)
        let foot = font("MartianMono-Regular", 14)
        text("? for shortcuts", foot, ccDim.withAlphaComponent(0.8)).draw(at: NSPoint(x: fullBox.minX + 16, y: fullBox.maxY + 12))

        if t < restoreAt {
            if t < submit + 0.35 {
                // 1. Writing it: 47 minutes, time-lapsed, with keypsake's carbon impression trailing behind
                let p = 0.04 + 0.96 * span(t, typeFrom, typeTo)
                let typed = String(prompt.prefix(Int(Double(prompt.count) * p)))
                let gone = ease(span(t, submit, submit + 0.3))
                scrolled(promptLine(typed, carbonDark.withAlphaComponent(0.2 * (1 - gone)), caret: true, alpha: 0), in: inner, dx: 6, dy: 6 - 30 * gone)
                scrolled(promptLine(typed, ccText.withAlphaComponent(1 - gone), caret: t < submit && (t < typeTo || blink), alpha: 1 - gone), in: inner, dy: -30 * gone)
                let c = text("▶▶ \(commas(Int(Double(totalWords) * p))) words · \(Int(Double(totalMinutes) * p)) min", foot, ccDim.withAlphaComponent(1 - gone))
                c.draw(at: NSPoint(x: fullBox.maxX - 16 - c.size().width, y: fullBox.maxY + 12))
            } else {
                promptLine("", ccText, caret: blink).draw(at: NSPoint(x: inner.minX, y: lineBox.minY + 12))
            }
            if t >= submit {
                // 2. Thinking, then the connection drops, retries, esc, and the prompt is just gone
                let hist = 1 - span(t, restoreAt - 0.3, restoreAt)
                let spin = ["·", "✢", "✳", "✶", "✻", "✽"][Int(t * 8) % 6]
                if t < escAt {
                    runs([(spin + " Thinking… ", claude.withAlphaComponent(hist)), ("(esc to interrupt)", ccDim.withAlphaComponent(hist))]).draw(at: NSPoint(x: fullBox.minX + 4, y: 172))
                }
                if t >= errorAt {
                    runs([("⎿  ", ccDim.withAlphaComponent(hist)), ("Connection error.", ccError.withAlphaComponent(hist))]).draw(at: NSPoint(x: fullBox.minX + 4, y: 212))
                    let n = t < errorAt + 0.8 ? "1" : t < errorAt + 1.6 ? "2" : t < errorAt + 2.4 ? "3" : "forever"
                    text(t < escAt ? "   Retrying \(n) of 3…" : "   Interrupted by user", term, ccDim.withAlphaComponent(hist)).draw(at: NSPoint(x: fullBox.minX + 4, y: 248))
                }
            }
        } else {
            // 6. The fix: the impression slides back and becomes text again
            let back = ease(span(t, restoreAt + 0.6, restoreAt + 1.8)), ghostIn = span(t, restoreAt + 0.3, restoreAt + 0.6)
            let c = carbonDark.withAlphaComponent(0.4 * ghostIn).blended(withFraction: back, of: ccText)!
            scrolled(promptLine(prompt, c, caret: false, alpha: max(back, 0.001)), in: inner, dx: 7 * (1 - back), dy: 7 * (1 - back))
            let r = text("\(commas(totalWords)) words · \(totalMinutes) min · restored", foot, carbonDark.withAlphaComponent(back))
            r.draw(at: NSPoint(x: fullBox.maxX - 16 - r.size().width, y: fullBox.maxY + 12))
        }
    }

    // 3. The "!" pops over the empty prompt and stays long enough to sink in
    let bang = pop(span(t, bangAt, bangAt + 0.25)) * (1 - ease(span(t, ohnoAt - 0.4, ohnoAt - 0.1)))
    if bang > 0 {
        cg.saveGState(); cg.translateBy(x: lineBox.minX + 46, y: lineBox.minY - 4); cg.scaleBy(x: bang, y: bang)
        let bubble = NSBezierPath(roundedRect: NSRect(x: -34, y: -96, width: 68, height: 80), xRadius: 18, yRadius: 18)
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: -11, y: -22)); tail.line(to: NSPoint(x: 0, y: 0)); tail.line(to: NSPoint(x: 11, y: -22)); tail.close()
        paper.setFill(); bubble.fill(); tail.fill()
        let mark = text("!", font("Redaction-Regular", 66), cliff)
        mark.draw(at: NSPoint(x: -mark.size().width / 2, y: -56 - mark.size().height / 2))
        cliff.withAlphaComponent(bump(t, bangAt + 0.05, bangAt + 0.6)).setStroke()
        for a in [-150.0, -90.0, -30.0] {
            let r = a * .pi / 180, p = NSBezierPath()
            p.move(to: NSPoint(x: 54 * cos(r), y: -56 + 54 * sin(r))); p.line(to: NSPoint(x: 72 * cos(r), y: -56 + 72 * sin(r)))
            p.lineWidth = 4; p.lineCapStyle = .round; p.stroke()
        }
        cg.restoreGState()
    }
    cg.restoreGState()

    // Labels + keys
    let fadeAll = 1 - ease(span(t, outroAt, outroAt + 0.5))
    label("FINE. ↑ TO GET IT BACK.", ink.withAlphaComponent(0.5), alpha: span(t, 13.4, 13.7) * (1 - span(t, 14.1, 14.25)))
    label("↑ GIVES YOU NOTHING.", cliff, alpha: span(t, 14.3, 14.5) * (1 - span(t, ohnoAt - 0.4, ohnoAt - 0.1)))
    label("ONE SHORTCUT LATER", ink.withAlphaComponent(0.5), alpha: span(t, backAt + 0.4, backAt + 0.7) * (1 - span(t, restoreAt + 0.4, restoreAt + 0.6)))
    label("KEPT. ALL 47 MINUTES OF IT.", carbon, alpha: span(t, restoreAt + 1.6, restoreAt + 2.0) * fadeAll)
    keycap("return", alpha: span(t, 7.4, 7.6) * (1 - span(t, 8.8, 9.1)), press: bump(t, 8.05, submit))
    keycap("esc", alpha: span(t, 12.4, 12.6) * (1 - span(t, 13.4, 13.65)), press: bump(t, 12.8, escAt))
    keycap("↑", alpha: span(t, 13.7, 13.9) * (1 - span(t, 14.8, 15.1)), press: bump(t, 14.0, upAt))
    keycap("⌃ ⌥ K", alpha: span(t, backAt + 0.6, backAt + 0.8) * (1 - span(t, restoreAt + 1.0, restoreAt + 1.3)), press: bump(t, keyAt - 0.25, keyAt))

    // Ribbon: one bar per version, the last one before the loss in amber
    for i in 0..<14 {
        let grow = out(span(t, restoreAt + 1.8 + Double(i) * 0.05, restoreAt + 2.3 + Double(i) * 0.05)) * fadeAll
        guard grow > 0 else { continue }
        let h = 34 * (0.2 + 0.8 * Double(i + 1) / 14) * grow
        (i == 13 ? cliff : ghost).withAlphaComponent(fadeAll).setFill()
        NSBezierPath(roundedRect: NSRect(x: window.maxX - 14 * 13 + CGFloat(i) * 13, y: 90 - h, width: 7, height: h), xRadius: 2, yRadius: 2).fill()
    }

    // 4. ohno.gif over a fully dimmed terminal
    let dim = span(t, ohnoAt - 0.3, ohnoAt) * (1 - span(t, backAt, backAt + 0.5))
    if dim > 0 { ground.withAlphaComponent(dim).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill() }
    let cardIn = pop(span(t, ohnoAt, ohnoAt + 0.35)), cardOut = ease(span(t, neverAt - 0.4, neverAt - 0.05))
    if cardIn > 0 && cardOut < 1 {
        cg.saveGState(); cg.setAlpha(1 - cardOut)
        cg.translateBy(x: 640, y: 320); let s = 1.25 * cardIn * (1 - 0.08 * cardOut); cg.scaleBy(x: s, y: s)
        let card = NSRect(x: -190, y: -150, width: 380, height: 300)
        let sh = NSShadow(); sh.shadowColor = ink.withAlphaComponent(0.18); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10)
        cg.saveGState(); sh.set(); paper.setFill(); NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill(); cg.restoreGState()
        text("ohno.gif", font("MartianMono-Medium", 19), ink.withAlphaComponent(0.75)).draw(at: NSPoint(x: card.minX + 20, y: card.minY + 16))
        // The face: eyes go wide, mouth drops, a bead of sweat loops
        let shock = out(span(t, ohnoAt + 0.15, ohnoAt + 0.35)), jit = 1.6 * sin(t * 95) * shock
        ink.setStroke(); ink.setFill()
        for side in [-1.0, 1.0] {
            let r = 13 + 9 * shock, c = NSPoint(x: 48 * side + jit, y: -2)
            let eye = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); eye.lineWidth = 3.5; eye.stroke()
            let p = 6 - 2.5 * shock
            NSBezierPath(ovalIn: NSRect(x: c.x - p, y: c.y - p, width: 2 * p, height: 2 * p)).fill()
        }
        let mw = 18 + 8 * shock, mh = 8 + 24 * shock
        NSBezierPath(ovalIn: NSRect(x: -mw / 2 - jit, y: 62 - mh / 2, width: mw, height: mh)).fill()
        if t > ohnoAt + 0.25 {
            let drip = (t - ohnoAt - 0.25).truncatingRemainder(dividingBy: 0.9) / 0.9
            carbon.withAlphaComponent(1 - pow(drip, 3)).setFill()
            let d = NSPoint(x: 104, y: -46 + 46 * drip), drop = NSBezierPath(ovalIn: NSRect(x: d.x - 7, y: d.y - 7, width: 14, height: 14))
            drop.move(to: NSPoint(x: d.x - 6, y: d.y - 3)); drop.line(to: NSPoint(x: d.x, y: d.y - 16)); drop.line(to: NSPoint(x: d.x + 6, y: d.y - 3)); drop.close()
            drop.fill()
        }
        cg.restoreGState()
        centered(text("and there goes 47 minutes.", font("MartianMono-Regular", 22), ink.withAlphaComponent(0.7 * span(t, ohnoAt + 0.4, ohnoAt + 0.7) * (1 - cardOut))), y: 530)
    }

    // 5. never again. Holds, with a slow underline
    let nIn = out(span(t, neverAt, neverAt + 0.6)), nOut = ease(span(t, backAt - 0.3, backAt + 0.1))
    if nIn > 0 && nOut < 1 {
        let n = text("never again.", font("Redaction-Regular", 120), ink.withAlphaComponent(nIn * (1 - nOut)), kern: -1.5)
        centered(n, y: 250 + 12 * (1 - nIn))
        let lw = 260 * ease(span(t, neverAt + 0.4, neverAt + 1.9))
        carbon.withAlphaComponent(1 - nOut).setFill(); NSRect(x: (CGFloat(W) - lw) / 2, y: 250 + n.size().height + 14, width: lw, height: 3).fill()
    }

    cg.restoreGState()
    montage(t, scroll)

    if fadeAll < 1 { ground.withAlphaComponent(1 - fadeAll).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill() }

    // 7. Wordmark
    let end = out(span(t, endAt, endAt + 0.9))
    if end > 0 {
        let word = text("keypsake", display, ink.withAlphaComponent(end), kern: -1.5)
        let ws = word.size()
        let iconSize: CGFloat = 104, gap: CGFloat = 28
        let x0 = (CGFloat(W) - iconSize - gap - ws.width) / 2, y0 = CGFloat(H) / 2 - 70 + 14 * (1 - end)
        icon.draw(in: NSRect(x: x0, y: y0 + (ws.height - iconSize) / 2 + 6, width: iconSize, height: iconSize),
                  from: .zero, operation: .sourceOver, fraction: end, respectFlipped: true, hints: nil)
        word.draw(at: NSPoint(x: x0 + iconSize + gap, y: y0))
        centered(text("typed it? keyp it.", font("MartianMono-Regular", 26), ink.withAlphaComponent(0.7 * out(span(t, endAt + 0.5, endAt + 1.3))), kern: 0.8), y: y0 + ws.height + 26)
        let lw = 120 * ease(span(t, endAt + 0.8, endAt + 2.0))
        carbon.setFill(); NSRect(x: (CGFloat(W) - lw) / 2, y: y0 + ws.height + 80, width: lw, height: 2).fill()
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
        let delay = (i >= frames - 2) ? 1.2 : 2.0 / Double(FPS)
        CGImageDestinationAddImage(gif, small.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
CGImageDestinationFinalize(gif)
// Poster frames for review
for (name, t) in [("p1-typing", 5.5), ("p2-retry", 11.0), ("p6b-kept", 25.5), ("p8-swipe", 26.5), ("p9-chat", 28.0), ("p10-search", 29.9), ("p11-form", 31.8), ("p12-end", 34.5)] {
    let rep = NSBitmapImageRep(cgImage: render(t))
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? "\(CommandLine.arguments[1])/\(name).png" : "/dev/null"))
}
print("wrote docs/keypsake.mp4 and docs/keypsake.gif, status \(writer.status.rawValue)")
