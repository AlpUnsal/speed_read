import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case black = "Black" // Previously typical dark mode
    case grey = "Grey"   // Existing dark mode logic
    case cream = "Cream"
    case white = "White"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .black: return .dark
        case .grey: return .dark
        case .cream: return .light
        case .white: return .light
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
    
    @AppStorage("appTheme") var theme: AppTheme = .grey // Defaulting to Grey
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
        case .cream:
            return Color(hex: "FDFBD4") // Cream (User requested)
        case .white:
            return Color(hex: "FFFFFF") // Pure White
        }
    }
    
    var textColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "E5E5E5") // Light Grey for contrast
        case .cream, .white:
            return Color(hex: "1A1A1A") // Dark Grey for contrast
        }
    }
    
    var secondaryTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "888888")
        case .cream, .white:
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
        case .cream:
            return Color(hex: "FFFCE2") // Lighter warm cream that blends better
        case .white:
            return Color(hex: "F9F9F9") // Slightly off-white cards on white background
        }
    }
    
    var cardBorderColor: Color {
        switch theme {
        case .black:
            return Color(hex: "2A2A2A")
        case .grey:
            return Color(hex: "333333")
        case .cream:
            return Color(hex: "EAE8BD") // Muted warm border
        case .white:
            return Color(hex: "E0E0E0")
        }
    }
    
    var mutedTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "555555")
        case .cream, .white:
            return Color(hex: "999999")
        }
    }
    
    var progressBarBackgroundColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "2A2A2A")
        case .cream:
            return Color(hex: "EAE8BD") // Muted warm track
        case .white:
            return Color(hex: "E5E5E5")
        }
    }
    
    var buttonBackgroundColor: Color {
        switch theme {
        case .black:
            return Color(hex: "1A1A1A")
        case .grey:
            return Color(hex: "2A2A2A")
        case .cream:
            return Color(hex: "F4F1C9") // Slightly darker cream button
        case .white:
            return Color(hex: "F5F5F5")
        }
    }
    
    var primaryButtonBackgroundColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "E5E5E5")
        case .cream, .white:
            return Color(hex: "1A1A1A")
        }
    }
    
    var primaryButtonTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "1A1A1A")
        case .cream, .white:
            return Color(hex: "FFFFFF")
        }
    }
}
