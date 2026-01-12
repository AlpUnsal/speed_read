import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum ReaderMode: String, CaseIterable, Identifiable {
    case rsvp = "Speed Reader"
    case paragraph = "Paragraph"
    
    var id: String { rawValue }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("appTheme") var theme: AppTheme = .dark // Defaulting to dark as per original design
    @AppStorage("readerMode") var readerMode: ReaderMode = .rsvp
    @AppStorage("fontName") var fontName: String = "EBGaramond-Regular"
    @AppStorage("fontSizeMultiplier") var fontSizeMultiplier: Double = 1.0
    
    // Available fonts - strictly curating to high quality reading fonts
    let availableFonts = [
        "EBGaramond-Regular",
        "NewYork-Regular",
        "TimesNewRomanPSMT",
        "Georgia",
        "AvenirNext-Regular",
        "HelveticaNeue-Light"
    ]
    
    private init() {}
    
    // MARK: - Color Palette
    
    var backgroundColor: Color {
        switch theme {
        case .dark:
            return Color(hex: "1A1A1A")
        case .light:
            return Color(hex: "FAF9F6") // Cream
        case .system:
            return Color("BackgroundColor") // Fallback to asset catalog or dynamic color
        }
    }
    
    var textColor: Color {
        switch theme {
        case .dark:
            return Color(hex: "E5E5E5")
        case .light:
            return Color(hex: "1A1A1A")
        case .system:
            return Color("TextColor")
        }
    }
    
    var secondaryTextColor: Color {
        switch theme {
        case .dark:
            return Color(hex: "888888")
        case .light:
            return Color(hex: "666666")
        case .system:
            return Color.secondary
        }
    }
    
    var accentColor: Color {
        return Color(hex: "E63946")
    }
}
