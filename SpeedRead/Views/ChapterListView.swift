import SwiftUI

/// Modal view showing all navigation points with progress
struct ChapterListView: View {
    enum Tab {
        case sections
        case figures
        case history
    }
    
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var isPresented: Bool
    
    @State private var selectedTab: Tab = .sections
    
    var body: some View {
        NavigationView {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segmented Picker
                    Picker("View", selection: $selectedTab) {
                        Text("Sections").tag(Tab.sections)
                        Text("Figures").tag(Tab.figures)
                        if !viewModel.positionHistory.isEmpty {
                            Text("History").tag(Tab.history)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(settings.backgroundColor)
                    
                    if selectedTab == .sections {
                        if viewModel.navigationPoints.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Text("No chapters available")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(secondaryTextColor)
                            }
                            Spacer()
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
                    } else if selectedTab == .figures {
                        // Figures Tab
                        if viewModel.figureAnnotations.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Text("No figures available")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(secondaryTextColor)
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(viewModel.figureAnnotations.enumerated()), id: \.element.id) { index, figure in
                                        FigureRow(
                                            figure: figure,
                                            onTap: {
                                                viewModel.showKnownFigure(figure)
                                                isPresented = false
                                            }
                                        )
                                        
                                        if index < viewModel.figureAnnotations.count - 1 {
                                            Divider()
                                                .background(dividerColor)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    } else {
                        // History Tab — recent positions the user can jump back to
                        if viewModel.positionHistory.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Text("No history yet")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(secondaryTextColor)
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(viewModel.positionHistory.enumerated()), id: \.element.id) { index, snapshot in
                                        HistoryRow(
                                            snapshot: snapshot,
                                            onTap: {
                                                viewModel.markDepartureForNextJump(viewModel.currentIndex)
                                                viewModel.goToIndex(snapshot.wordIndex)
                                                isPresented = false
                                            }
                                        )

                                        if index < viewModel.positionHistory.count - 1 {
                                            Divider()
                                                .background(dividerColor)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == .sections ? "Sections" : (selectedTab == .figures ? "Figures" : "History"))
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
        case .sage: return Color(hex: "A9D0B3")
        case .iceBlue: return Color(hex: "7AC0CD")
        case .cherry: return Color(hex: "E2908F")
        case .lilac: return Color(hex: "C69CC6")
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
        case .sage: return Color(hex: "A9D0B3")
        case .iceBlue: return Color(hex: "7AC0CD")
        case .cherry: return Color(hex: "E2908F")
        case .lilac: return Color(hex: "C69CC6")
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
        case .sage: return Color(hex: "C2E2C9")
        case .iceBlue: return Color(hex: "99D5E0")
        case .cherry: return Color(hex: "EFAAAA")
        case .lilac: return Color(hex: "D6B0D6")
        }
    }
}

// MARK: - Figure Row

private struct FigureRow: View {
    let figure: FigureAnnotation
    let onTap: () -> Void
    
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Figure icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(secondaryTextColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Extract figure title from caption if possible (e.g. "Figure 1")
                    let titleText = extractFigureTitle(from: figure.caption)
                    
                    Text(titleText)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(settings.textColor)
                    
                    if let caption = figure.caption {
                        Text(caption)
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(tertiaryTextColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Simple heuristic to get "Figure 1" or "Exhibit A" for the title
    private func extractFigureTitle(from caption: String?) -> String {
        guard let text = caption else { return "Figure" }
        let components = text.components(separatedBy: CharacterSet(charactersIn: ":.- "))
        if components.count >= 2 {
            let firstWord = components[0].lowercased()
            if firstWord == "figure" || firstWord == "fig" || firstWord == "exhibit" {
                // Attempt to grab the first two words roughly
                let words = text.split(separator: " ")
                if words.count >= 2 {
                    let secondWord = words[1].trimmingCharacters(in: CharacterSet(charactersIn: ":.-"))
                    return "\(words[0]) \(secondWord)"
                }
            }
        }
        return "Figure" // Fallback
    }
    
    private var iconBackgroundColor: Color {
        switch settings.theme {
        case .cream: return Color(hex: "EAE8BD")
        case .white: return Color(hex: "E0E0E0")
        case .sage: return Color(hex: "A9D0B3")
        case .iceBlue: return Color(hex: "7AC0CD")
        case .cherry: return Color(hex: "E2908F")
        case .lilac: return Color(hex: "C69CC6")
        default: return Color(hex: "2A2A2A")
        }
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
}

// MARK: - History Row

private struct HistoryRow: View {
    let snapshot: PositionSnapshot
    let onTap: () -> Void

    @ObservedObject private var settings = SettingsManager.shared

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: snapshot.date, relativeTo: Date())
    }

    private var kindIcon: String {
        snapshot.kind == .jumpDeparture ? "arrow.uturn.backward" : "bookmark"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: kindIcon)
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(secondaryTextColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let label = snapshot.sectionLabel {
                            Text(label)
                                .font(.custom("EBGaramond-Regular", size: 15))
                                .foregroundColor(settings.textColor)
                        }
                        Text(relativeTime)
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(secondaryTextColor)
                    }

                    if !snapshot.snippet.isEmpty {
                        Text("\u{201C}\(snapshot.snippet)\u{2026}\u{201D}")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(tertiaryTextColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var iconBackgroundColor: Color {
        switch settings.theme {
        case .cream: return Color(hex: "EAE8BD")
        case .white: return Color(hex: "E0E0E0")
        case .sage: return Color(hex: "A9D0B3")
        case .iceBlue: return Color(hex: "7AC0CD")
        case .cherry: return Color(hex: "E2908F")
        case .lilac: return Color(hex: "C69CC6")
        default: return Color(hex: "2A2A2A")
        }
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
}

#Preview {
    ChapterListView(
        viewModel: RSVPViewModel(),
        isPresented: .constant(true)
    )
}
