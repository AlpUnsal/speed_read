import SwiftUI

struct RSVPView: View {
    let text: String
    let documentId: UUID?
    let startIndex: Int
    let initialWPM: Double
    let onExit: () -> Void
    
    @StateObject private var viewModel = RSVPViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var showControls = true
    @State private var showSpeedHint = true
    @State private var currentWPMDisplay: Double? = nil
    @State private var hideWPMTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Background
            settings.backgroundColor
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.togglePlayPause()
                }
            
            // Reader Content
            if settings.readerMode == .paragraph {
                ParagraphView(
                    viewModel: viewModel,
                    onTap: {
                        viewModel.togglePlayPause()
                    }
                )
                .padding(.top, 60)
                .padding(.bottom, 100)
            } else {
                // Word Display (centered with ORP anchor)
                WordDisplayView(
                    word: viewModel.currentWord,
                    fontSize: WordDisplayView.fontSize(for: viewModel.currentWord) * settings.fontSizeMultiplier,
                    fontName: settings.fontName,
                    theme: settings.theme
                )
            }
            
            // UI Overlay
            VStack {
                // Top bar with exit button, restart, and progress
                HStack {
                    Button(action: { saveProgressAndExit() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .padding(12)
                    }
                    
                    Spacer()
                    
                    // Progress indicator
                    Text("\(viewModel.currentIndex + 1) / \(viewModel.totalWords)")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(Color(hex: "555555"))
                    
                    Spacer()
                    
                    // Restart button
                    Button(action: { viewModel.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .padding(12)
                    }
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Bottom controls - skip backward, play/pause, skip forward
                HStack(spacing: 48) {
                    // Skip backward 15 words
                    Button(action: { viewModel.skipBackward(by: 15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Play/Pause
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause" : "play.fill")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(Color(hex: "777777"))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Skip forward 15 words
                    Button(action: { viewModel.skipForward(by: 15) }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.bottom, 50)
            }
            
            // Speed control zone - invisible swipe area on right side
            GeometryReader { geo in
                // Swipe zone covers right third of screen, bottom half
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * 0.35, height: geo.size.height * 0.6)
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.65)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Swipe up = faster, swipe down = slower
                                let sensitivity: Double = 1.5
                                let delta = -value.translation.height * sensitivity / 100
                                let newWPM = viewModel.wordsPerMinute + delta
                                viewModel.wordsPerMinute = min(max(newWPM, viewModel.minWPM), viewModel.maxWPM)
                                
                                // Show WPM feedback
                                currentWPMDisplay = viewModel.wordsPerMinute
                                hideWPMTimer?.invalidate()
                                
                                // Hide the initial hint after first use
                                if showSpeedHint {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        showSpeedHint = false
                                    }
                                }
                            }
                            .onEnded { _ in
                                // Hide WPM display after a delay
                                hideWPMTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        currentWPMDisplay = nil
                                    }
                                }
                            }
                    )
                
                // WPM feedback display (shows during/after swipe)
                if let wpm = currentWPMDisplay {
                    Text("\(Int(wpm)) WPM")
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(Color(hex: "888888"))
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.45)
                        .transition(.opacity)
                }
                
                // Initial hint (fades away after first swipe)
                if showSpeedHint {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 24))
                        Text("Swipe to\nadjust speed")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(Color(hex: "555555"))
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.55)
                    .transition(.opacity)
                }
            }
            
            // Progress bar at bottom
            VStack {
                Spacer()
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(hex: "2A2A2A"))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(Color(hex: "E63946"))
                            .frame(width: geometry.size.width * viewModel.progress, height: 2)
                    }
                }
                .frame(height: 2)
            }
        }
        .onAppear {
            viewModel.loadText(text, startingAt: startIndex)
            viewModel.wordsPerMinute = initialWPM
        }
        .onDisappear {
            saveProgress()
        }
        .statusBarHidden(true)
    }
    
    private func saveProgress() {
        if let docId = documentId {
            LibraryManager.shared.updateProgress(
                for: docId,
                wordIndex: viewModel.currentIndex,
                wpm: viewModel.wordsPerMinute
            )
        }
    }
    
    private func saveProgressAndExit() {
        saveProgress()
        onExit()
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    RSVPView(
        text: "This is a sample text for testing the RSVP speed reading functionality.",
        documentId: nil,
        startIndex: 0,
        initialWPM: 300,
        onExit: {}
    )
}
