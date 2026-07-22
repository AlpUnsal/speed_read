import SwiftUI
import UIKit

// MARK: - Paragraph Data Model

struct ParagraphData: Identifiable {
    let id: Int
    let text: String
    let wordStartIndex: Int
    let wordCount: Int
    let isEmpty: Bool
    let headingLevel: Int?          // nil = body text, 1-6 = heading level
    let headingType: NavigationType? // .chapter, .heading, .section, or nil
    /// True when `text` is tokens re-joined with single spaces (long-paragraph
    /// chunks) — word ranges then come from a plain space split, since running
    /// the hyphenation-aware tokenizer on re-joined text could merge across
    /// token boundaries and skew local indices.
    let isTokenJoined: Bool
    /// True for every chunk of a split long paragraph except the last —
    /// such chunks render with line spacing below instead of a paragraph gap,
    /// so the split paragraph reads as one continuous block.
    let joinsToNext: Bool
}

// MARK: - Normal Reading View

struct NormalReadingView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings: SettingsManager
    var onTap: () -> Void
    var onWordLongPress: ((String) -> Void)?

    // Word picker (reading -> RSVP handoff), owned by RSVPView.
    var isWordPickerActive: Bool = false
    var pickerSelectedWordIndex: Int? = nil
    var onWordPicked: ((Int) -> Void)? = nil

    /// All paragraphs (used for word-index mapping even when not rendered).
    /// Derived from viewModel.paragraphs — never re-tokenized here.
    @State private var allParagraphs: [ParagraphData] = []
    /// Windowed subset currently rendered — keeps content height manageable
    @State private var windowStart: Int = 0
    @State private var windowEnd: Int = 0
    @State private var topVisibleParagraphID: Int?

    // Position-contract state: position only moves on user scrolls.
    @State private var scrollPhase: ScrollPhase = .idle
    /// True while the scroll view rests at the very top of its content — the
    /// only place upward window growth is allowed (see maintainWindowAtRest).
    @State private var isPinnedAtTop = false
    /// False until the entry back-buffer has been grown and re-anchored;
    /// content stays invisible (and untouchable) until then, so the first
    /// upward drag already has runway and the re-anchor frame never shows.
    @State private var isPrimed = false
    /// Set before any programmatic scroll; tracking is suppressed until the
    /// top-visible paragraph reaches this ID (replaces the old timers).
    @State private var programmaticScrollTargetID: Int? = nil
    /// Word index at the start of the current user scroll session — compared
    /// against the landing index to record a jump-departure snapshot.
    @State private var jumpDepartureIndex: Int? = nil

    // Arrival highlight: marks the exact current word when entering the view,
    // fades after a short delay or on first user scroll.
    @State private var arrivalHighlightWordIndex: Int? = nil
    @State private var arrivalHighlightGeneration = 0

    /// Max paragraphs to render at once. Keeps backing layer under iOS limits.
    private let maxWindowSize = 200

    private var windowedParagraphs: ArraySlice<ParagraphData> {
        guard !allParagraphs.isEmpty else { return [] }
        let s = max(0, min(windowStart, allParagraphs.count))
        let e = max(s, min(windowEnd, allParagraphs.count))
        return allParagraphs[s..<e]
    }

    var body: some View {
        GeometryReader { geo in
        let textWidth = max(0, geo.size.width - horizontalPadding * 2)
        Group {
            if allParagraphs.isEmpty {
                // Scroll content mounts only after the initial position is
                // known, so the first visible frame is already at the
                // reader's spot — never a stale offset that a stray user
                // scroll could commit into currentIndex.
                settings.backgroundColor
            } else {
                readerScrollView(textWidth: textWidth)
            }
        }
        .onAppear {
            if !viewModel.paragraphs.isEmpty && allParagraphs.isEmpty {
                setupInitialPosition()
            }
        }
        .onDisappear {
            // Force-save current position when leaving
            viewModel.updateIndexForReading(viewModel.currentIndex, forceSave: true)
        }
        .onChange(of: viewModel.paragraphs) { _, newParagraphs in
            // Text loads async — build paragraphs when tokenization arrives
            guard !newParagraphs.isEmpty, allParagraphs.isEmpty else { return }
            setupInitialPosition()
        }
        .onChange(of: viewModel.scrollResetID) { _, _ in
            // Triggered by chapter navigation or restart
            scrollToCurrentIndexAfterWindowShift()
        }
        .onChange(of: viewModel.externalNavigationID) { _, _ in
            // Triggered by goToIndex (chapter select, search, scrub)
            scrollToCurrentIndexAfterWindowShift()
        }
        }
    }

    /// The scroll content. All programmatic positioning writes the
    /// scrollPosition binding (never ScrollViewReader.scrollTo, which moves
    /// content without updating the binding — the stale binding then yanks
    /// the view back to the old offset on a later layout pass, e.g. when the
    /// HUD toggles).
    @ViewBuilder
    private func readerScrollView(textWidth: CGFloat) -> some View {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(windowedParagraphs) { paragraph in
                        if paragraph.isEmpty {
                            Spacer().frame(height: emptyLineSpacing)
                                .id(paragraph.id)
                        } else if let level = paragraph.headingLevel {
                            // Heading paragraph
                            let heading = headingFontComponents(level: level)
                            let headingLineSpacing = baseFontSize * settings.fontSizeMultiplier * 0.35
                            ParagraphTextKitView(
                                text: paragraph.text,
                                fontName: heading.name,
                                fontSize: heading.size,
                                textColor: UIColor(settings.textColor),
                                tracking: level <= 2 ? 0.4 : 0.3,
                                lineSpacing: headingLineSpacing,
                                alignment: level == 1 ? .center : .natural,
                                availableWidth: textWidth,
                                isTokenJoined: paragraph.isTokenJoined,
                                highlightedTokenIndex: localHighlightIndex(for: paragraph),
                                highlightColor: highlightUIColor,
                                onWordTapped: { local in handleWordTap(paragraph: paragraph, localIndex: local) },
                                onWordLongPressed: { local in handleWordLongPress(paragraph: paragraph, localIndex: local) }
                            )
                            .frame(
                                width: textWidth,
                                height: ParagraphTextKitView.preferredHeight(
                                    text: paragraph.text,
                                    fontName: heading.name,
                                    fontSize: heading.size,
                                    tracking: level <= 2 ? 0.4 : 0.3,
                                    lineSpacing: headingLineSpacing,
                                    alignment: level == 1 ? .center : .natural,
                                    width: textWidth
                                ),
                                alignment: .topLeading
                            )
                            .id(paragraph.id)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, headingTopSpacing(level: level))
                            .padding(.bottom, headingBottomSpacing(level: level))
                            .onAppear { extendWindowIfNeeded(visibleID: paragraph.id) }
                        } else {
                            // Body paragraph
                            let bodySize = baseFontSize * settings.fontSizeMultiplier
                            ParagraphTextKitView(
                                text: paragraph.text,
                                fontName: settings.fontName,
                                fontSize: bodySize,
                                textColor: UIColor(settings.textColor),
                                tracking: 0.2,
                                lineSpacing: bodySize * 0.45,
                                alignment: .natural,
                                availableWidth: textWidth,
                                isTokenJoined: paragraph.isTokenJoined,
                                highlightedTokenIndex: localHighlightIndex(for: paragraph),
                                highlightColor: highlightUIColor,
                                onWordTapped: { local in handleWordTap(paragraph: paragraph, localIndex: local) },
                                onWordLongPressed: { local in handleWordLongPress(paragraph: paragraph, localIndex: local) }
                            )
                            .frame(
                                width: textWidth,
                                height: ParagraphTextKitView.preferredHeight(
                                    text: paragraph.text,
                                    fontName: settings.fontName,
                                    fontSize: bodySize,
                                    tracking: 0.2,
                                    lineSpacing: bodySize * 0.45,
                                    alignment: .natural,
                                    width: textWidth
                                ),
                                alignment: .topLeading
                            )
                            .id(paragraph.id)
                            .padding(.horizontal, horizontalPadding)
                            // Continuation chunks of one split paragraph get
                            // line spacing, not a paragraph gap, so the split
                            // is invisible (preferredHeight adds no trailing
                            // line spacing — zero here would butt lines).
                            .padding(.bottom, paragraph.joinsToNext ? bodySize * 0.45 : paragraphSpacing)
                            .onAppear { extendWindowIfNeeded(visibleID: paragraph.id) }
                        }
                    }

                }
                // Required for scrollPosition(id:) to track user scrolls —
                // without a target layout the binding only supports writes.
                .scrollTargetLayout()
            }
            // Insets live in content margins, not spacer rows, so that
            // scrollPosition anchoring and the natural content top agree — a
            // re-anchored top row lands exactly where resting at the top puts
            // it. Top clears the top bar overlay; bottom the controls.
            .contentMargins(.top, 56, for: .scrollContent)
            .contentMargins(.bottom, 100, for: .scrollContent)
            .scrollPosition(id: $topVisibleParagraphID, anchor: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, pinned in
                isPinnedAtTop = pinned
                // The offset leaving the hard top is the arrival signal for
                // the entry priming re-anchor — reveal the content.
                if !pinned && !isPrimed {
                    isPrimed = true
                }
            }
            .onScrollPhaseChange { _, newPhase in
                scrollPhase = newPhase
                switch newPhase {
                case .interacting, .decelerating:
                    // User is driving — any pending programmatic target is moot
                    // (also covers no-op programmatic scrolls that never fired
                    // an onChange to clear the target).
                    programmaticScrollTargetID = nil
                    if jumpDepartureIndex == nil {
                        jumpDepartureIndex = viewModel.currentIndex
                    }
                    cancelArrivalHighlight()
                case .idle:
                    // Scroll session ended — record a breadcrumb for big jumps.
                    if let departure = jumpDepartureIndex {
                        if abs(viewModel.currentIndex - departure) > viewModel.jumpSnapshotThreshold {
                            viewModel.recordReadingJumpSnapshot(departureIndex: departure)
                        }
                        jumpDepartureIndex = nil
                    }
                    // Upward growth and window trimming happen only at rest,
                    // each followed by a manual re-anchor — the automatic
                    // scrollPosition re-anchor never fires on this OS.
                    maintainWindowAtRest()
                default:
                    break
                }
            }
            .onChange(of: topVisibleParagraphID) { _, newID in
                guard let paragraphID = newID,
                      paragraphID >= 0,
                      paragraphID < allParagraphs.count else { return }
                // Suppress until the programmatic scroll actually arrives.
                if let target = programmaticScrollTargetID {
                    if paragraphID == target {
                        programmaticScrollTargetID = nil
                    }
                    return
                }
                // Core of the position contract: only user-driven phases move
                // the position — layout settles and window shifts fire this
                // onChange too, but outside .interacting/.decelerating.
                guard scrollPhase == .interacting || scrollPhase == .decelerating else { return }

                let paragraph = allParagraphs[paragraphID]
                if !paragraph.isEmpty {
                    viewModel.updateIndexForReading(paragraph.wordStartIndex)
                } else {
                    // Empty paragraph — find nearest non-empty one after it
                    if let next = allParagraphs[paragraphID...].first(where: { !$0.isEmpty }) {
                        viewModel.updateIndexForReading(next.wordStartIndex)
                    }
                }
            }
            .opacity(isPrimed ? 1 : 0)
            .allowsHitTesting(isPrimed)
            // Single tap anywhere toggles the reader UI — margins, paragraph
            // gaps, and content-margin bands included; the scroll view would
            // otherwise swallow taps that miss a text frame. Simultaneous so
            // it coexists with the per-paragraph UIKit recognizers (which
            // handle picker taps and long-press dictionary only).
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard !isWordPickerActive else { return }
                    onTap()
                }
            )
            .onAppear { primeUpwardBuffer() }
    }

    /// Runs one hidden grow-and-re-anchor cycle right after the content
    /// mounts: the entry window starts exactly at the reader's paragraph, so
    /// without this the first upward drag rubber-bands (nothing above) and
    /// the growth on release flickers. Priming does the same growth while
    /// the content is still invisible; the geometry callback reveals it the
    /// moment the re-anchor lands, with a timeout as safety net.
    private func primeUpwardBuffer() {
        guard !isPrimed else { return }
        guard windowStart > 0, let anchorID = topVisibleParagraphID else {
            // Already at the true start of the book — nothing to buffer.
            isPrimed = true
            return
        }
        // One layout pass with the unbuffered window first, so the re-anchor
        // write applies to mounted content.
        DispatchQueue.main.async {
            windowStart = max(0, windowStart - 100)
            forceReanchor(to: anchorID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isPrimed = true
            }
        }
    }

    // MARK: - Typography Constants

    private var baseFontSize: CGFloat { 18 }
    private var paragraphSpacing: CGFloat { 20 }
    private var emptyLineSpacing: CGFloat { 16 }
    private var horizontalPadding: CGFloat { 28 }

    private func headingTopSpacing(level: Int) -> CGFloat {
        switch level {
        case 1: return 48
        case 2: return 36
        case 3: return 28
        default: return 24
        }
    }

    private func headingBottomSpacing(level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 18
        default: return 16
        }
    }

    private func headingFontSizeMultiplier(level: Int) -> CGFloat {
        switch level {
        case 1: return 1.45
        case 2: return 1.28
        case 3: return 1.15
        default: return 1.08
        }
    }

    private func headingFontComponents(level: Int) -> (name: String, size: CGFloat) {
        let size = baseFontSize * settings.fontSizeMultiplier * headingFontSizeMultiplier(level: level)
        let fontName = settings.fontName

        // For level 1-2 headings, try a heavier weight variant
        if level <= 2 {
            let mediumName = fontName
                .replacingOccurrences(of: "-Regular", with: "-Medium")
                .replacingOccurrences(of: "-Light", with: "-Regular")
            if mediumName != fontName, UIFont(name: mediumName, size: size) != nil {
                return (mediumName, size)
            }
        }

        return (fontName, size)
    }

    // MARK: - Word Interaction

    private var highlightUIColor: UIColor {
        UIColor(settings.accentColor).withAlphaComponent(0.25)
    }

    /// The word to highlight, if it falls inside this paragraph — the picker
    /// selection while picking, otherwise the arrival highlight.
    private func localHighlightIndex(for paragraph: ParagraphData) -> Int? {
        let globalIndex = isWordPickerActive ? pickerSelectedWordIndex : arrivalHighlightWordIndex
        guard let global = globalIndex,
              global >= paragraph.wordStartIndex,
              global < paragraph.wordStartIndex + paragraph.wordCount else { return nil }
        return global - paragraph.wordStartIndex
    }

    private func handleWordTap(paragraph: ParagraphData, localIndex: Int) {
        // Picker mode only — plain taps are handled by the scroll-level
        // TapGesture (simultaneous with this recognizer, so acting here too
        // would toggle the UI twice and cancel out).
        guard isWordPickerActive else { return }
        let clamped = min(max(0, localIndex), max(0, paragraph.wordCount - 1))
        onWordPicked?(paragraph.wordStartIndex + clamped)
    }

    private func handleWordLongPress(paragraph: ParagraphData, localIndex: Int) {
        guard !isWordPickerActive else { return }
        let globalIndex = paragraph.wordStartIndex + localIndex
        guard globalIndex >= 0, globalIndex < viewModel.words.count else { return }
        let clean = viewModel.words[globalIndex]
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        onWordLongPress?(clean)
    }

    // MARK: - Paragraph Building

    /// Assigns navigation points to source paragraphs for heading styling.
    /// Parser-side word counting can drift from the reader's tokenization, so
    /// exact index equality is never required: each nav point snaps to the
    /// nearest paragraph start within a small tolerance, and only sticks when
    /// the paragraph's opening text plausibly matches the nav title. Styling
    /// only — viewModel.navigationPoints is never mutated; the chapter list
    /// and progress tracking stay range-based and tolerate imprecision.
    private func computeHeadingAssignments() -> [Int: NavigationPoint] {
        let paragraphs = viewModel.paragraphs
        guard !paragraphs.isEmpty else { return [:] }

        // Ascending starts of non-empty source paragraphs.
        var starts: [(start: Int, sourceIdx: Int)] = []
        starts.reserveCapacity(paragraphs.count)
        for (idx, para) in paragraphs.enumerated() where !para.isEmpty {
            starts.append((para.wordStartIndex, idx))
        }
        guard !starts.isEmpty else { return [:] }

        let tolerance = 10
        let navs = viewModel.navigationPoints
            .filter { $0.type != .page }
            .sorted { $0.wordStartIndex < $1.wordStartIndex }

        var assignments: [Int: NavigationPoint] = [:]

        for nav in navs {
            // Binary search for the first paragraph start within tolerance.
            let lower = nav.wordStartIndex - tolerance
            var lo = 0, hi = starts.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if starts[mid].start < lower { lo = mid + 1 } else { hi = mid }
            }

            // Nearest verified candidate wins; ties break to the earlier
            // paragraph (visited first in ascending order). A paragraph
            // already claimed by an earlier nav point stays claimed.
            var best: (sourceIdx: Int, distance: Int)? = nil
            var i = lo
            while i < starts.count && starts[i].start <= nav.wordStartIndex + tolerance {
                let candidate = starts[i]
                i += 1
                if assignments[candidate.sourceIdx] != nil { continue }
                let paragraphPrefix = String(
                    paragraphs[candidate.sourceIdx].paragraphText.prefix(nav.title.count + 16)
                )
                guard HeadingMatcher.paragraphStartMatchesTitle(
                    paragraphPrefix: paragraphPrefix,
                    title: nav.title
                ) else { continue }
                let distance = abs(candidate.start - nav.wordStartIndex)
                if best == nil || distance < best!.distance {
                    best = (candidate.sourceIdx, distance)
                }
            }

            if let best {
                assignments[best.sourceIdx] = nav
            }
        }

        return assignments
    }

    /// Maps viewModel.paragraphs to render-level ParagraphData. Cheap — no
    /// tokenization happens here; word counts come from the same pass that
    /// produced viewModel.words, so indices can never drift between modes.
    private func buildRenderParagraphs() -> [ParagraphData] {
        let headingBySourceIndex = computeHeadingAssignments()

        var result: [ParagraphData] = []
        result.reserveCapacity(viewModel.paragraphs.count)
        var globalID = 0

        for (sourceIdx, para) in viewModel.paragraphs.enumerated() {
            if para.isEmpty {
                result.append(ParagraphData(
                    id: globalID,
                    text: "",
                    wordStartIndex: para.wordStartIndex,
                    wordCount: 0,
                    isEmpty: true,
                    headingLevel: nil,
                    headingType: nil,
                    isTokenJoined: false,
                    joinsToNext: false
                ))
                globalID += 1
                continue
            }

            // Heading styling comes from the verified snap assignments, never
            // from raw index equality.
            let navPoint = headingBySourceIndex[sourceIdx]
            let headingLevel = navPoint.map { np -> Int in
                if let level = np.level { return level }
                return np.type == .chapter ? 1 : 2
            }
            let headingType = navPoint?.type

            if para.wordCount > 300 {
                // Split very long paragraphs into chunks to prevent huge Text
                // views. Chunk by slicing the global words array — never
                // re-tokenize, so chunk indices stay exact.
                var chunkStart = para.wordStartIndex
                let paraEnd = para.wordStartIndex + para.wordCount
                var isFirstChunk = true
                while chunkStart < paraEnd {
                    let hardEnd = min(chunkStart + 200, paraEnd)
                    var chunkEnd = hardEnd
                    if hardEnd < paraEnd {
                        // Prefer cutting just after a sentence end so the
                        // visual seam between chunks is least noticeable.
                        let minEnd = chunkStart + 120
                        var j = hardEnd - 1
                        while j >= minEnd {
                            if TextTokenizer.endsSentence(viewModel.words[j]) {
                                chunkEnd = j + 1
                                break
                            }
                            j -= 1
                        }
                    }
                    let chunkText = viewModel.words[chunkStart..<chunkEnd].joined(separator: " ")
                    result.append(ParagraphData(
                        id: globalID,
                        text: chunkText,
                        wordStartIndex: chunkStart,
                        wordCount: chunkEnd - chunkStart,
                        isEmpty: false,
                        headingLevel: isFirstChunk ? headingLevel : nil,
                        headingType: isFirstChunk ? headingType : nil,
                        isTokenJoined: true,
                        joinsToNext: chunkEnd < paraEnd
                    ))
                    globalID += 1
                    chunkStart = chunkEnd
                    isFirstChunk = false
                }
            } else {
                result.append(ParagraphData(
                    id: globalID,
                    text: para.paragraphText,
                    wordStartIndex: para.wordStartIndex,
                    wordCount: para.wordCount,
                    isEmpty: false,
                    headingLevel: headingLevel,
                    headingType: headingType,
                    isTokenJoined: false,
                    joinsToNext: false
                ))
                globalID += 1
            }
        }

        return result
    }

    // MARK: - Initial Position

    /// Builds render paragraphs and anchors the current word's paragraph to
    /// the top, with the arrival highlight on the exact word.
    private func setupInitialPosition() {
        allParagraphs = buildRenderParagraphs()
        guard !allParagraphs.isEmpty else { return }
        // The window STARTS at the current paragraph, so the first rendered
        // frame is the reader's spot by construction — no initial scroll is
        // needed. (An initial scrollPosition value silently no-ops on lazy
        // content that isn't laid out yet, and a binding value that never
        // changes never retries.) Earlier paragraphs stream in at scroll
        // rest through maintainWindowAtRest.
        setWindowStarting(paragraphForWordIndex: viewModel.currentIndex)
        let target = paragraphIDForWordIndex(viewModel.currentIndex)
        programmaticScrollTargetID = target
        topVisibleParagraphID = target
        triggerArrivalHighlight(at: viewModel.currentIndex)
    }

    // MARK: - Arrival Highlight

    private func triggerArrivalHighlight(at wordIndex: Int) {
        arrivalHighlightGeneration += 1
        let generation = arrivalHighlightGeneration
        withAnimation(.easeIn(duration: 0.15)) {
            arrivalHighlightWordIndex = wordIndex
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if arrivalHighlightGeneration == generation {
                withAnimation(.easeOut(duration: 0.3)) {
                    arrivalHighlightWordIndex = nil
                }
            }
        }
    }

    private func cancelArrivalHighlight() {
        guard arrivalHighlightWordIndex != nil else { return }
        arrivalHighlightGeneration += 1
        withAnimation(.easeOut(duration: 0.25)) {
            arrivalHighlightWordIndex = nil
        }
    }

    // MARK: - Paragraph Window

    /// Centers the render window around the paragraph containing `wordIndex`.
    /// Used for programmatic jumps, where an animated scroll follows and
    /// needs runway on both sides.
    private func setWindowAround(paragraphForWordIndex wordIndex: Int) {
        guard !allParagraphs.isEmpty else { return }

        let targetIdx = allParagraphs.lastIndex(where: { $0.wordStartIndex <= wordIndex }) ?? 0
        let half = maxWindowSize / 2
        let newStart = max(0, targetIdx - half)
        let newEnd = min(allParagraphs.count, newStart + maxWindowSize)

        windowStart = newStart
        windowEnd = newEnd
    }

    /// Starts the render window exactly at the paragraph containing
    /// `wordIndex` — used on entry so the first frame shows the current
    /// position with no scrolling at all.
    private func setWindowStarting(paragraphForWordIndex wordIndex: Int) {
        guard !allParagraphs.isEmpty else { return }

        let targetIdx = allParagraphs.lastIndex(where: { $0.wordStartIndex <= wordIndex }) ?? 0
        windowStart = targetIdx
        windowEnd = min(allParagraphs.count, targetIdx + maxWindowSize)
    }

    /// Extends the window downward when the user scrolls near its bottom
    /// edge. Appending below the viewport never moves on-screen content, so
    /// this is safe in any scroll phase. Upward growth and trimming DO shift
    /// on-screen content and happen only at rest (maintainWindowAtRest).
    private func extendWindowIfNeeded(visibleID: Int) {
        let margin = 20
        if visibleID >= windowEnd - margin && windowEnd < allParagraphs.count {
            windowEnd = min(allParagraphs.count, windowEnd + 100)
        }
    }

    /// Window maintenance at scroll rest. Any mutation that shifts content
    /// relative to the viewport (inserting above, trimming above) ends with
    /// a forced re-anchor of the current top row — the automatic
    /// scrollPosition re-anchoring never fires in this configuration, so the
    /// raw offset would otherwise point ~100 paragraphs into the past.
    private func maintainWindowAtRest() {
        guard let topID = topVisibleParagraphID else { return }
        var needsReanchor = false

        // Pinned at the hard top with more content above — grow upward. The
        // top row rests flush against the top content margin here, so the
        // re-anchor is pixel-exact.
        if isPinnedAtTop && windowStart > 0 {
            windowStart = max(0, windowStart - 100)
            needsReanchor = true
        }

        // Keep the window bounded after long reads. Trimming below the
        // viewport is invisible; trimming above shifts content and costs at
        // most a small settle of the top row to the margin edge.
        if windowEnd - windowStart > maxWindowSize * 2 {
            let newEnd = min(allParagraphs.count, topID + maxWindowSize)
            if newEnd < windowEnd { windowEnd = newEnd }
            let newStart = max(0, topID - maxWindowSize / 2)
            if newStart > windowStart {
                windowStart = newStart
                needsReanchor = true
            }
        }

        if needsReanchor {
            forceReanchor(to: topID)
        }
    }

    /// Re-applies the scrollPosition binding for `rowID`. Writing the value
    /// it already holds is a no-op, so the write goes nil → rowID across two
    /// runloop turns; index tracking stays suppressed throughout via
    /// programmaticScrollTargetID.
    private func forceReanchor(to rowID: Int) {
        programmaticScrollTargetID = rowID
        topVisibleParagraphID = nil
        DispatchQueue.main.async {
            // If a touch landed in the gap, the user owns the scroll now.
            guard scrollPhase == .idle else { return }
            topVisibleParagraphID = rowID
        }
    }

    // MARK: - Navigation Helpers

    /// Find the paragraph ID that contains the given word index.
    private func paragraphIDForWordIndex(_ wordIndex: Int) -> Int? {
        guard !allParagraphs.isEmpty else { return nil }
        let target = allParagraphs.last(where: { $0.wordStartIndex <= wordIndex }) ?? allParagraphs.first!
        return target.id
    }

    // MARK: - Scroll Helpers

    /// Programmatic navigation (chapter select, search, restart): re-center
    /// the render window, then scroll. The small delay lets the window
    /// mutation lay out before the scroll targets an ID inside it; tracking
    /// stays suppressed the whole time via programmaticScrollTargetID.
    private func scrollToCurrentIndexAfterWindowShift() {
        guard !allParagraphs.isEmpty else { return }
        setWindowAround(paragraphForWordIndex: viewModel.currentIndex)
        programmaticScrollTargetID = paragraphIDForWordIndex(viewModel.currentIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToWordIndex(viewModel.currentIndex, animated: true)
        }
    }

    /// Scrolls by writing the scrollPosition binding, which keeps binding and
    /// content offset in sync — ScrollViewReader.scrollTo must never be used
    /// here (it bypasses the binding, leaving it stale).
    private func scrollToWordIndex(_ wordIndex: Int, animated: Bool = true) {
        guard !allParagraphs.isEmpty else { return }

        let targetParagraph = allParagraphs.last(where: { $0.wordStartIndex <= wordIndex }) ?? allParagraphs.first!
        programmaticScrollTargetID = targetParagraph.id

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                topVisibleParagraphID = targetParagraph.id
            }
        } else {
            topVisibleParagraphID = targetParagraph.id
        }
    }
}

