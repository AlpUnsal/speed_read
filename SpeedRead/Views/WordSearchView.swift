import SwiftUI

/// Search interface overlay for finding words in documents
struct WordSearchView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject private var settings = SettingsManager.shared
    
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            settings.backgroundColor
                .opacity(0.98)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSearch()
                }
            
            VStack(spacing: 20) {
                // Header with search field
                HStack(spacing: 12) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(secondaryTextColor)
                            .font(.system(size: 14))
                        
                        TextField("Search...", text: $searchText)
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(settings.textColor)
                            .focused($isSearchFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: searchText) { _, newValue in
                                viewModel.search(query: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(secondaryTextColor)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(cardBackgroundColor)
                    .cornerRadius(10)
                    
                    // Close button
                    Button(action: { dismissSearch() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(mutedTextColor)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                // Results count
                if !searchText.isEmpty {
                    HStack {
                        Text(resultsLabel)
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(secondaryTextColor)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                
                // Results list
                if viewModel.searchResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    Text("No matches found")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, result in
                                SearchResultRow(
                                    result: result,
                                    searchQuery: searchText,
                                    isCurrentResult: index == viewModel.currentSearchIndex,
                                    onTap: {
                                        jumpToResult(at: index)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
                
                // Navigation buttons (only show if results exist)
                if !viewModel.searchResults.isEmpty {
                    HStack(spacing: 40) {
                        Button(action: { viewModel.jumpToPreviousSearchResult() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(mutedTextColor)
                                .frame(width: 44, height: 44)
                        }
                        
                        if let currentIndex = viewModel.currentSearchIndex {
                            Text("\(currentIndex + 1) / \(viewModel.searchResults.count)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(secondaryTextColor)
                        }
                        
                        Button(action: { viewModel.jumpToNextSearchResult() }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(mutedTextColor)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
    
    private var resultsLabel: String {
        let count = viewModel.searchResults.count
        if count == 0 {
            return "No matches"
        } else if count == 1 {
            return "1 match"
        } else {
            return "\(count) matches"
        }
    }
    
    private func dismissSearch() {
        viewModel.clearSearch()
        isPresented = false
    }
    
    private func jumpToResult(at index: Int) {
        viewModel.jumpToSearchResult(at: index)
        isPresented = false
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
    
    private var cardBackgroundColor: Color {
        switch settings.theme {
        case .black: return Color(hex: "1A1A1A")
        case .grey: return Color(hex: "2A2A2A")
        case .cream, .white: return Color(hex: "F0F0F0")
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let searchQuery: String
    let isCurrentResult: Bool
    let onTap: () -> Void
    
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Context snippet with highlighted match
                highlightedText
                    .font(.custom("EBGaramond-Regular", size: 15))
                    .lineLimit(2)
                
                Spacer()
                
                // Current indicator
                if isCurrentResult {
                    Circle()
                        .fill(Color(hex: "E63946"))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isCurrentResult ? currentResultBackground : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var highlightedText: Text {
        let snippet = result.contextSnippet
        let query = searchQuery.lowercased()
        
        // Find the match in context
        if let range = snippet.lowercased().range(of: query) {
            let before = String(snippet[..<range.lowerBound])
            let match = String(snippet[range])
            let after = String(snippet[range.upperBound...])
            
            return Text(before)
                .foregroundColor(secondaryTextColor) +
            Text(match)
                .foregroundColor(Color(hex: "E63946"))
                .fontWeight(.medium) +
            Text(after)
                .foregroundColor(secondaryTextColor)
        }
        
        return Text(snippet).foregroundColor(secondaryTextColor)
    }
    
    private var secondaryTextColor: Color {
        switch settings.theme {
        case .cream, .white: return Color(hex: "666666")
        default: return Color(hex: "AAAAAA")
        }
    }
    
    private var currentResultBackground: Color {
        switch settings.theme {
        case .black: return Color(hex: "1A1A1A")
        case .grey: return Color(hex: "2A2A2A")
        case .cream, .white: return Color(hex: "EEEEEE")
        }
    }
}

#Preview {
    WordSearchView(
        viewModel: RSVPViewModel(),
        isPresented: .constant(true)
    )
}
