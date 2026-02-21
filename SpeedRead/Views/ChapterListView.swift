import SwiftUI

/// Modal view showing all navigation points with progress
struct ChapterListView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()
                
                if viewModel.navigationPoints.isEmpty {
                    VStack(spacing: 12) {
                        Text("No chapters available")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(secondaryTextColor)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.navigationPoints.enumerated()), id: \.element.id) { index, point in
                                    ChapterRow(
                                        point: point,
                                        index: index,
                                        isCurrent: point.id == viewModel.currentNavigationPoint?.id,
                                        progressInChapter: viewModel.currentNavigationPoint?.id == point.id 
                                            ? point.progress(at: viewModel.currentIndex) 
                                            : (viewModel.currentIndex >= point.wordEndIndex ? 1.0 : 0.0),
                                        onTap: {
                                            viewModel.jumpToNavigationPoint(point)
                                            isPresented = false
                                        }
                                    )
                                    .id(point.id)
                                    
                                    if index < viewModel.navigationPoints.count - 1 {
                                        Divider()
                                            .background(dividerColor)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            if let current = viewModel.currentNavigationPoint {
                                proxy.scrollTo(current.id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(mutedTextColor)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Theme Colors
    
    private var mutedTextColor: Color {
        switch settings.theme {
        case .cream, .white: return Color(hex: "999999")
        default: return Color(hex: "555555")
        }
    }
    
    private var secondaryTextColor: Color {
        switch settings.theme {
        case .cream, .white: return Color(hex: "666666")
        default: return Color(hex: "888888")
        }
    }
    
    private var dividerColor: Color {
        switch settings.theme {
        case .cream: return Color(hex: "EAE8BD")
        case .white: return Color(hex: "E0E0E0")
        default: return Color(hex: "2A2A2A")
        }
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let point: NavigationPoint
    let index: Int
    let isCurrent: Bool
    let progressInChapter: Double
    let onTap: () -> Void
    
    @ObservedObject private var settings = SettingsManager.shared
    
    /// Indentation based on heading level
    private var indentLevel: CGFloat {
        guard let level = point.level else { return 0 }
        return CGFloat(max(0, level - 1)) * 16
    }
    
    /// Icon for navigation type
    private var typeIcon: String {
        switch point.type {
        case .chapter: return "book"
        case .heading: return "text.alignleft"
        case .section: return "bookmark"
        case .page: return "doc"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Current indicator
                if isCurrent {
                    Circle()
                        .fill(Color(hex: "E63946"))
                        .frame(width: 6, height: 6)
                } else {
                    Spacer().frame(width: 6)
                }
                
                // Indentation spacer
                if indentLevel > 0 {
                    Spacer().frame(width: indentLevel)
                }
                
                // Type icon
                Image(systemName: typeIcon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(tertiaryTextColor)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Title
                    Text(point.title)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(isCurrent ? settings.textColor : secondaryTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(trackColor)
                                .frame(height: 3)
                            
                            Rectangle()
                                .fill(progressColor)
                                .frame(width: geo.size.width * progressInChapter, height: 3)
                        }
                        .cornerRadius(1.5)
                    }
                    .frame(height: 3)
                    
                    // Word count
                    Text("\(point.wordCount) words")
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(tertiaryTextColor)
                }
                
                Spacer()
                
                // Progress percentage
                Text("\(Int(progressInChapter * 100))%")
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(tertiaryTextColor)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isCurrent ? currentBackground : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var secondaryTextColor: Color {
        switch settings.theme {
        case .cream, .white: return Color(hex: "444444")
        default: return Color(hex: "AAAAAA")
        }
    }
    
    private var tertiaryTextColor: Color {
        switch settings.theme {
        case .cream, .white: return Color(hex: "888888")
        default: return Color(hex: "666666")
        }
    }
    
    private var trackColor: Color {
        switch settings.theme {
        case .cream: return Color(hex: "EAE8BD")
        case .white: return Color(hex: "E0E0E0")
        default: return Color(hex: "2A2A2A")
        }
    }
    
    private var progressColor: Color {
        Color(hex: "E63946")
    }
    
    private var currentBackground: Color {
        switch settings.theme {
        case .black: return Color(hex: "1A1A1A")
        case .grey: return Color(hex: "252525")
        case .cream: return Color(hex: "F4F1C9")
        case .white: return Color(hex: "F5F5F5")
        }
    }
}

#Preview {
    ChapterListView(
        viewModel: RSVPViewModel(),
        isPresented: .constant(true)
    )
}
