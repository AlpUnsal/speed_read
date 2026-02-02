import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case black = "Black" // Previously typical dark mode
    case grey = "Grey"   // Existing dark mode logic
    case light = "Light" // Cream
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .black: return .dark
        case .grey: return .dark
        case .light: return .light
        }
    }
}

enum ReaderMode: String, CaseIterable, Identifiable {
    case rsvp = "Speed"
    case paragraph = "Scroll"
    
    var id: String { rawValue }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("appTheme") var theme: AppTheme = .black // Defaulting to Black
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
    
    private init() {
        // Clamp font size if it exceeds new max
        if fontSizeMultiplier > 1.25 {
            fontSizeMultiplier = 1.25
        }
    }
    
    // MARK: - Color Palette
    
    var backgroundColor: Color {
        switch theme {
        case .black:
            return Color.black // Pure Black
        case .grey:
            return Color(hex: "1A1A1A") // Dark Grey
        case .light:
            return Color(hex: "FAF9F6") // Cream
        }
    }
    
    var textColor: Color {
        switch theme {
        case .black:
            return Color(hex: "E5E5E5") // Light Grey for contrast
        case .grey:
            return Color(hex: "E5E5E5") // Light Grey for contrast
        case .light:
            return Color(hex: "1A1A1A") // Dark Grey for contrast
        }
    }
    
    var secondaryTextColor: Color {
        switch theme {
        case .black:
            return Color(hex: "888888")
        case .grey:
            return Color(hex: "888888")
        case .light:
            return Color(hex: "666666")
        }
    }
    
    var accentColor: Color {
        return Color(hex: "E63946")
    }
    
    var completedColor: Color {
        return Color(hex: "4CAF50")
    }
    
    // MARK: - UI Component Colors
    
    var cardBackgroundColor: Color {
        switch theme {
        case .black:
            return Color(hex: "151515")
        case .grey:
            return Color(hex: "232323")
        case .light:
            return Color(hex: "FFFFFF")
        }
    }
    
    var cardBorderColor: Color {
        switch theme {
        case .black:
            return Color(hex: "2A2A2A")
        case .grey:
            return Color(hex: "333333")
        case .light:
            return Color(hex: "E0E0E0")
        }
    }
    
    var mutedTextColor: Color {
        switch theme {
        case .black:
            return Color(hex: "555555")
        case .grey:
            return Color(hex: "555555")
        case .light:
            return Color(hex: "999999")
        }
    }
    
    var progressBarBackgroundColor: Color {
        switch theme {
        case .black:
            return Color(hex: "2A2A2A")
        case .grey:
            return Color(hex: "2A2A2A")
        case .light:
            return Color(hex: "E5E5E5")
        }
    }
    
    var buttonBackgroundColor: Color {
        switch theme {
        case .black:
            return Color(hex: "1A1A1A")
        case .grey:
            return Color(hex: "2A2A2A")
        case .light:
            return Color(hex: "F5F5F5")
        }
    }
    
    var primaryButtonBackgroundColor: Color {
        switch theme {
        case .black:
            return Color(hex: "E5E5E5")
        case .grey:
            return Color(hex: "E5E5E5")
        case .light:
            return Color(hex: "1A1A1A")
        }
    }
    
    var primaryButtonTextColor: Color {
        switch theme {
        case .black:
            return Color(hex: "1A1A1A")
        case .grey:
            return Color(hex: "1A1A1A")
        case .light:
            return Color(hex: "FFFFFF")
        }
    }
}
