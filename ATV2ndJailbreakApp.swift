import SwiftUI

@main
struct ATV2ndJailbreakApp: App {
    @StateObject private var jailbreakVM = JailbreakViewModel()
    @StateObject private var componentMgr = ComponentManager()
    @StateObject private var usbMonitor = USBMonitor()

    var body: some Scene {
        WindowGroup("ATV2nd Jailbreak") {
            ContentView()
                .environmentObject(jailbreakVM)
                .environmentObject(componentMgr)
                .environmentObject(usbMonitor)
                .frame(minWidth: 720, minHeight: 540)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 800, height: 600)
    }
}
