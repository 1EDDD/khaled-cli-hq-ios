// يرسم أيقونة التطبيق: مربع أسود، HQ عريض أبيض، وتحته khaled_cli صغيرة.
// الاستخدام: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset: CGFloat = 100, box = size - inset * 2
NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x15 / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: box, height: box), xRadius: 185, yRadius: 185).fill()

func draw(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let s = NSAttributedString(string: text, attributes: attrs)
    let b = s.size()
    s.draw(at: NSPoint(x: (size - b.width) / 2, y: centerY - b.height / 2))
}
draw("HQ", font: .systemFont(ofSize: 360, weight: .black), color: .white, centerY: 560, kern: -8)
draw("khaled_cli", font: .monospacedSystemFont(ofSize: 74, weight: .medium),
     color: NSColor(srgbRed: 0xB4 / 255, green: 0xB2 / 255, blue: 0xA9 / 255, alpha: 1), centerY: 330)
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
