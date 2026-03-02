import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case black = "Black" // Previously typical dark mode
    case grey = "Grey"   // Existing dark mode logic
    case cream = "Cream"
    case white = "White"
    case sage = "Sage"
    case iceBlue = "Ice Blue"
    case cherry = "Cherry"
    case lilac = "Lilac"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .black, .grey: return .dark
        case .cream, .white, .sage, .iceBlue, .cherry, .lilac: return .light
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
    
    @AppStorage("theme") var theme: AppTheme = .cream // Defaulting to Cream
    @AppStorage("readerMode") var readerMode: ReaderMode = .rsvp
    @AppStorage("fontName") var fontName: String = "EBGaramond-Regular"
    @AppStorage("fontSizeMultiplier") var fontSizeMultiplier: Double = 1.0
    @AppStorage("showORPEmphasisLines") var showORPEmphasisLines: Bool = false
    
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
        case .sage:
            return Color(hex: "E8F0E8") // Very pale grey-green
        case .iceBlue:
            return Color(hex: "E3EDF2") // Very pale grey-blue
        case .cherry:
            return Color(hex: "F9EBED") // Very pale pink
        case .lilac:
            return Color(hex: "F2EBFA") // Very pale purple
        }
    }
    
    var textColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "E5E5E5") // Light Grey for contrast
        case .sage:
            return Color(hex: "758B7D") // Even lighter, softer green-grey
        case .iceBlue:
            return Color(hex: "6A8294") // Even lighter, softer blue-grey
        case .cherry:
            return Color(hex: "9E747A") // Even lighter, softer red-grey
        case .lilac:
            return Color(hex: "816B99") // Even lighter, softer purple-grey
        case .cream, .white:
            return Color(hex: "1A1A1A") // Dark Grey for contrast
        }
    }
    
    var secondaryTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "888888")
        case .sage:
            return Color(hex: "95A89B") // Very light muted green-grey
        case .iceBlue:
            return Color(hex: "8E9FA8") // Very light muted blue-grey
        case .cherry:
            return Color(hex: "BFA0A4") // Very light muted red-grey
        case .lilac:
            return Color(hex: "A391B5") // Very light muted purple-grey
        case .cream, .white:
            return Color(hex: "666666")
        }
    }
    
    var accentColor: Color {
        switch theme {
        case .sage:
            return Color(hex: "1A4D2E") // Very dark, deep green
        case .iceBlue:
            return Color(hex: "134B6E") // Very dark, deep blue
        case .cherry:
            return Color(hex: "8A2533") // Very dark, deep red
        case .lilac:
            return Color(hex: "4E1D7B") // Very dark, deep purple
        default:
            return Color(hex: "E63946") // Default red
        }
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
        case .sage:
            return Color(hex: "F2F7F2")
        case .iceBlue:
            return Color(hex: "EEF4F7")
        case .cherry:
            return Color(hex: "FDF4F5")
        case .lilac:
            return Color(hex: "F7F4FA")
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
        case .sage:
            return Color(hex: "D1E2D4")
        case .iceBlue:
            return Color(hex: "CFE2EA")
        case .cherry:
            return Color(hex: "EDDDE0")
        case .lilac:
            return Color(hex: "E1D8EA")
        }
    }
    
    var mutedTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "555555")
        case .cream, .white, .sage, .iceBlue, .cherry, .lilac:
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
        case .sage:
            return Color(hex: "D1E2D4")
        case .iceBlue:
            return Color(hex: "CFE2EA")
        case .cherry:
            return Color(hex: "EDDDE0")
        case .lilac:
            return Color(hex: "E1D8EA")
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
        case .sage:
            return Color(hex: "DFEADF")
        case .iceBlue:
            return Color(hex: "DFEBF2")
        case .cherry:
            return Color(hex: "F4E4E6")
        case .lilac:
            return Color(hex: "EBEOFO")
        }
    }
    
    var primaryButtonBackgroundColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "E5E5E5")
        case .cream, .white, .sage, .iceBlue, .cherry, .lilac:
            return Color(hex: "1A1A1A")
        }
    }
    
    var primaryButtonTextColor: Color {
        switch theme {
        case .black, .grey:
            return Color(hex: "1A1A1A")
        case .cream, .white, .sage, .iceBlue, .cherry, .lilac:
            return Color(hex: "FFFFFF")
        }
    }
}
