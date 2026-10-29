import SwiftUI

@main
struct KhaledHQApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
