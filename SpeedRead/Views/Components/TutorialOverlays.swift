import SwiftUI

/// Icon + caption hint shown while the tutorial waits for a gesture.
/// Mirrors the visual language of the first-launch speed/peek hints in RSVPView.
struct TutorialHintOverlay: View {
    let icon: String
    let text: String
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
            Text(text)
                .font(.custom("EBGaramond-Regular", size: 14))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(settings.secondaryTextColor)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

/// Full-screen payoff card shown when the tutorial's speed-ramp finale completes.
struct TutorialStatCardView: View {
    let wpm: Int
    let onFinish: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    private var multiplier: String {
        String(format: "%.1f", Double(wpm) / 225.0)
    }

    var body: some View {
        ZStack {
            settings.backgroundColor
                .opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Text("\(wpm)")
                    .font(.custom("EBGaramond-Regular", size: 72))
                    .foregroundColor(settings.accentColor)

                Text("words per minute")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(settings.secondaryTextColor)

                Text("You just read \(multiplier)× faster\nthan the average reader.")
                    .font(.custom("EBGaramond-Regular", size: 17))
                    .foregroundColor(settings.textColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)

                Button(action: onFinish) {
                    Text("Start Reading")
                        .font(.custom("EBGaramond-Regular", size: 17))
                        .foregroundColor(settings.primaryButtonTextColor)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(settings.primaryButtonBackgroundColor))
                }
                .padding(.top, 32)
            }
        }
        .transition(.opacity)
    }
}
