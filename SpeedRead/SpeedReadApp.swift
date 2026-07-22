import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.orientationLock
    }
}

@main
struct AxiloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    LibraryManager.shared.processSharedInbox()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                LibraryManager.shared.forceSave()
            }
        }
    }
}
