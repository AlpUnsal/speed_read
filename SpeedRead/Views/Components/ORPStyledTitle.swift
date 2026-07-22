import SwiftUI

struct ORPStyledTitle: View {
    let text: String
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                let isORP = (index == 1)
                Text(String(character))
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .foregroundColor(isORP ? settings.accentColor : settings.textColor)
            }
        }
    }
}

#Preview {
    VStack {
        ORPStyledTitle(text: "Axilo")
        ORPStyledTitle(text: "Library")
        ORPStyledTitle(text: "Explore")
    }
    .padding()
    .background(Color.black)
}
