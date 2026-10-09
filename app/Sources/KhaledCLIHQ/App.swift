import AppKit
import SwiftUI

@main
struct KhaledCLIHQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("khaled_cli HQ", id: "main") {
            ContentView()
                .environmentObject(delegate.runner)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runner = Runner()

    // سحب المقطع على أيقونة التطبيق في الـ Dock
    func application(_ sender: NSApplication, open urls: [URL]) {
        runner.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        runner.cancel()
    }
}

/// ألوان «بطاقة الاختبار»، نفس هوية فيديو الشرح
enum Theme {
    static let bg = Color(hex: 0x161615)
    static let panel = Color(hex: 0x1F1F1D)
    static let line = Color(hex: 0x2C2C2A)
    static let text = Color(hex: 0xF1EFE8)
    static let muted = Color(hex: 0xB4B2A9)
    static let dim = Color(hex: 0x888780)
    static let amber = Color(hex: 0xEF9F27)
    static let green = Color(hex: 0x97C459)
    static let red = Color(hex: 0xE24B4A)
    static let bars: [Color] = [0xD3D1C7, 0xEF9F27, 0x5DCAA5, 0x639922, 0xD4537E, 0xE24B4A, 0x378ADD].map { Color(hex: $0) }

    /// العناوين بخط النظام (سيرف عريض)
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .serif) }

    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
