import SwiftUI

class OrientationManager: ObservableObject {
    static let shared = OrientationManager()
    
    // Default to portrait only
    static var orientationLock = UIInterfaceOrientationMask.portrait {
        didSet {
            // Attempt to rotate to a valid orientation when the lock changes
            // specific safe check for App Extensions where UIApplication.shared is unavailable
            let selector = NSSelectorFromString("sharedApplication")
            guard UIApplication.responds(to: selector),
                  let sharedApp = UIApplication.perform(selector)?.takeUnretainedValue() as? UIApplication else {
                return
            }
            
            if let windowScene = sharedApp.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock)) { error in
                    print("Error requesting geometry update: \(error.localizedDescription)")
                }
            }
            
            // For good measure, force existing UI view controllers to update
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
