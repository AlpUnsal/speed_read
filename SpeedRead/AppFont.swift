import SwiftUI

/// Centralized font declarations for Axilo.
/// All UI text uses EB Garamond. System font is reserved only for SF Symbol icons
/// (via `Image(systemName:)`), where it controls symbol size/weight, not typeface.
///
/// Weight philosophy: prefer `.regular` everywhere for a light, editorial feel.
/// Use `.medium` only for the most prominent headings.
enum AppFont {
    // MARK: - Primary text styles
    /// Default text — use for body, labels, captions, metadata
    static func regular(_ size: CGFloat) -> Font {
        .custom("EBGaramond-Regular", size: size)
    }

    /// Slightly heavier — use for main title headings only (e.g. "Axilo", "Library")
    static func medium(_ size: CGFloat) -> Font {
        .custom("EBGaramond-Medium", size: size)
    }

    /// Avoid unless absolutely necessary — not aligned with the light aesthetic
    static func semiBold(_ size: CGFloat) -> Font {
        .custom("EBGaramond-SemiBold", size: size)
    }

    /// For image captions and editorial italics
    static func italic(_ size: CGFloat) -> Font {
        .custom("EBGaramond-Italic", size: size)
    }
}
