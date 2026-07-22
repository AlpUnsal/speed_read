import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showDocumentPicker: Bool
    var onTabSelected: (() -> Void)? = nil
    @ObservedObject var settings = SettingsManager.shared
    
    // SF Symbols mapped to tabs
    let icons = ["books.vertical.fill", "house.fill", "magnifyingglass"]
    let titles = ["Library", "Home", "Explore"]
    
    var body: some View {
        HStack(spacing: 12) {
            // Main Pill
            HStack(spacing: 0) {
                ForEach(0..<icons.count, id: \.self) { index in
                    Button(action: {
                        onTabSelected?()
                        if index == 2 && selectedTab == 2 {
                            NotificationCenter.default.post(name: NSNotification.Name("ResetExploreView"), object: nil)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = index
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: icons[index])
                                .font(.system(size: 20, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundColor(selectedTab == index ? settings.accentColor : settings.mutedTextColor)
                                .scaleEffect(selectedTab == index ? 1.05 : 1.0)
                                
                            Text(titles[index])
                                .font(.custom("EBGaramond-Regular", size: 9))
                                .foregroundColor(selectedTab == index ? settings.textColor : settings.mutedTextColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                // Liquid Glass Effect
                Group {
                    if #available(iOS 15.0, *) {
                        settings.cardBackgroundColor.opacity(0.15)
                            .background(.ultraThinMaterial)
                    } else {
                        settings.cardBackgroundColor.opacity(0.95)
                    }
                }
            )
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .overlay(
                Capsule()
                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 0.5)
            )
            
            // Import Button
            Button(action: {
                showDocumentPicker = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(settings.textColor)
                    .frame(width: 48, height: 48)
            }
            .background(
                Group {
                    if #available(iOS 15.0, *) {
                        settings.cardBackgroundColor.opacity(0.15)
                            .background(.ultraThinMaterial)
                    } else {
                        settings.cardBackgroundColor.opacity(0.95)
                    }
                }
            )
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .overlay(
                Circle()
                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12) // Adjust based on safe area if necessary
    }
}
