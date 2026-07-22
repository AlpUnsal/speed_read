import SwiftUI

struct ExploreView: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var searchService = BookSearchService()
    @ObservedObject var libraryManager = LibraryManager.shared
    @State private var searchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var pagerLocked = false
    @State private var pagerUnlockWork: DispatchWorkItem?

    let genres = ["Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror"]

    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    ORPStyledTitle(text: "Explore")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(settings.mutedTextColor)

                    TextField("Search books, authors...", text: $searchText, onCommit: {
                        debounceTask?.cancel()
                        performSearch()
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(settings.textColor)
                    .font(.custom("EBGaramond-Regular", size: 16))

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            performSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(settings.mutedTextColor)
                        }
                    }
                }
                .padding(12)
                .background(settings.cardBackgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Results Area
                ZStack {
                    if isSearchMode {
                        // Search mode: vertical list
                        if searchService.isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                                .scaleEffect(1.5)
                        } else if let errorMessage = searchService.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        } else if searchService.searchResults.isEmpty {
                            Text("No results found.")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(settings.mutedTextColor)
                        } else {
                            ScrollView {
                                searchResultsView
                            }
                        }
                    } else if searchService.genreBooks.isEmpty {
                        // Initial load — no genres fetched yet
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                                .scaleEffect(1.2)
                            Text("Loading books, this may take a moment...")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(settings.mutedTextColor)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Browse mode: Netflix-style genre rows
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(genres, id: \.self) { genre in
                                    genreRow(genre)
                                }

                                Color.clear.frame(height: 100)
                            }
                            .padding(.top, 4)
                        }
                        // While the list is coasting, a touch is intercepted
                        // by this scroll view and never reaches the carousels
                        // (UIScrollView deceleration catch) — the tab pager
                        // then claims any horizontal motion and slides the
                        // page. Lock the pager whenever content moves with no
                        // finger down, and keep it locked through the catch
                        // touch (.tracking/.interacting preserve the lock)
                        // until the gesture fully settles at .idle.
                        .onScrollPhaseChange { _, newPhase in
                            switch newPhase {
                            case .decelerating, .animating:
                                pagerUnlockWork?.cancel()
                                setPagerLock(true)
                            case .idle:
                                // A catch-touch reports .idle the instant it
                                // stops the coast — before any horizontal
                                // movement — so an immediate unlock hands the
                                // swipe to the pager anyway. Hold the lock
                                // briefly; a genuinely settled list unlocks
                                // 0.6s later, unnoticeable for tab swipes.
                                pagerUnlockWork?.cancel()
                                let work = DispatchWorkItem { setPagerLock(false) }
                                pagerUnlockWork = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                            default:
                                // .tracking/.interacting — a finger is down;
                                // never unlock underneath it.
                                pagerUnlockWork?.cancel()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if searchService.searchResults.isEmpty && !searchService.isSearching {
                searchService.fetchPopularBooks()
            }
        }
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            if newValue.isEmpty {
                performSearch()
            } else {
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard !Task.isCancelled else { return }
                    performSearch()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetExploreView"))) { _ in
            searchText = ""
            searchService.clearSearch()
        }
    }

    // MARK: - Computed

    private var isSearchMode: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Genre Row

    private func genreRow(_ genre: String) -> some View {
        let books = searchService.genreBooks[genre] ?? []

        return VStack(alignment: .leading, spacing: 14) {
            Text(genre)
                .font(.custom("EBGaramond-Regular", size: 22))
                .foregroundColor(settings.textColor)
                .padding(.horizontal, 24)

            if books.isEmpty {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                    Text("Loading...")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(settings.mutedTextColor)
                }
                .padding(.horizontal, 24)
                .frame(height: 195)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(books) { book in
                            let isDownloaded = libraryManager.documents.contains(where: { $0.name == book.title || $0.originalName == book.title })
                            NetflixBookCard(book: book, isDownloaded: isDownloaded) {
                                downloadAndParse(book)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .background(ScrollViewLeftEdgePassThrough())
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchService.searchResults) { book in
                let isDownloaded = libraryManager.documents.contains(where: { $0.name == book.title || $0.originalName == book.title })
                ExploreBookRow(book: book, isDownloaded: isDownloaded, onDownload: {
                    downloadAndParse(book)
                })
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
    }

    // MARK: - Actions

    private func setPagerLock(_ locked: Bool) {
        guard locked != pagerLocked else { return }
        pagerLocked = locked
        NotificationCenter.default.post(
            name: NSNotification.Name("ExplorePagerLock"),
            object: nil,
            userInfo: ["locked": locked]
        )
    }

    private func performSearch() {
        if isSearchMode {
            searchService.search(query: searchText)
        }
    }

    private func downloadAndParse(_ book: GutenbergBook) {
        guard let url = book.bestDownloadURL else {
            print("No readable format found for book")
            return
        }

        let ext = book.epubURL != nil ? "epub" : "txt"

        var userInfo: [String: Any] = ["url": url, "title": book.title, "ext": ext]
        if let coverURL = book.coverURL {
            userInfo["coverURL"] = coverURL
        }
        NotificationCenter.default.post(name: NSNotification.Name("DownloadAndReadBook"), object: nil, userInfo: userInfo)
    }
}

// MARK: - Scroll Edge Pass-Through
/// Runs a pan gesture recognizer simultaneously with horizontal ScrollViews.
/// Detects when the user drags a horizontal scroll view past its left edge
/// and programmatically switches to the Home tab.
///
/// Uses the scroll view's own rubber-band bounce: when contentOffset.x goes
/// below a negative threshold while the user is actively dragging, we know
/// they're trying to swipe past the edge. This avoids all gesture-recognizer
/// priority conflicts because we never add a competing gesture — we just
/// observe the scroll view's native behavior.
struct ScrollViewLeftEdgePassThrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = Self.findHorizontalScrollView(from: uiView) else { return }
            if context.coordinator.attachedScrollView !== scrollView {
                context.coordinator.attach(to: scrollView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func findHorizontalScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let parent = current?.superview {
            if let scrollView = parent as? UIScrollView,
               scrollView.contentSize.width > 0 {
                return scrollView
            }
            current = parent
        }
        return nil
    }

    class Coordinator: NSObject {
        weak var attachedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var didTrigger = false

        func attach(to scrollView: UIScrollView) {
            observation?.invalidate()
            attachedScrollView = scrollView

            // Bounces MUST be on — we use the rubber-band overshoot as our signal
            scrollView.bounces = true
            scrollView.alwaysBounceHorizontal = true

            observation = scrollView.observe(\.contentOffset, options: [.new]) {
                [weak self] sv, _ in
                self?.handleScroll(sv)
            }
        }

        private func handleScroll(_ scrollView: UIScrollView) {
            guard !didTrigger else { return }

            // Only act when the user is actively dragging (finger on screen).
            // This ignores deceleration overshoots — e.g. flicking the books
            // back to the start won't accidentally trigger a tab switch.
            guard scrollView.isDragging else { return }

            // Rubber-band damping stiffens fast — the old -80 threshold
            // needed nearly a full screen of finger travel. Trigger on a
            // modest overscroll while the finger is still actively pulling
            // right (velocity filters out drags that merely end at the
            // edge), or on a deep overscroll regardless of speed.
            let overscroll = scrollView.contentOffset.x
            let rightwardVelocity = scrollView.panGestureRecognizer.velocity(in: scrollView).x
            if overscroll < -35 && rightwardVelocity > 250 || overscroll < -70 {
                didTrigger = true

                // Kill the bounce so the books snap back to their resting spot
                scrollView.isScrollEnabled = false
                scrollView.setContentOffset(.zero, animated: false)
                scrollView.isScrollEnabled = true

                NotificationCenter.default.post(
                    name: NSNotification.Name("SwitchToHomeTab"), object: nil)

                // Cooldown — prevent re-triggering while the tab animates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    [weak self] in
                    self?.didTrigger = false
                }
            }
        }
    }
}

// MARK: - Netflix Book Card

struct NetflixBookCard: View {
    let book: GutenbergBook
    let isDownloaded: Bool
    let onDownload: () -> Void
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack(alignment: .topTrailing) {
                if let coverURL = book.coverURL {
                    AsyncImage(url: coverURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 130, height: 195)
                                .clipped()
                        } else if phase.error != nil {
                            fallbackCover
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.cardBackgroundColor)
                                ProgressView()
                            }
                        }
                    }
                    .frame(width: 130, height: 195)
                    .cornerRadius(8)
                } else {
                    fallbackCover
                }

                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .padding(6)
                }
            }
            .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(settings.textColor)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .topLeading)

                Text(book.primaryAuthorName)
                    .font(.custom("EBGaramond-Regular", size: 12))
                    .foregroundColor(settings.secondaryTextColor)
                    .lineLimit(1)

                if let genre = book.primaryGenre {
                    Text(genre.uppercased())
                        .font(.custom("EBGaramond-Regular", size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(settings.cardBorderColor.opacity(0.15))
                        .foregroundColor(settings.secondaryTextColor)
                        .cornerRadius(4)
                        .padding(.top, 2)
                }
            }
            .frame(width: 130)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDownload)
    }

    private var fallbackCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                )

            VStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 24))
                    .foregroundColor(settings.mutedTextColor.opacity(0.7))

                if let firstLetter = book.title.first {
                    Text(String(firstLetter))
                        .font(.custom("EBGaramond-Regular", size: 36))
                        .foregroundColor(settings.mutedTextColor)
                }
            }
        }
        .frame(width: 130, height: 195)
    }
}

// MARK: - Explore Book Row (Search Results)

struct ExploreBookRow: View {
    let book: GutenbergBook
    let isDownloaded: Bool
    let onDownload: () -> Void
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 14) {
            // Cover Art
            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 75)
                            .clipped()
                    } else if phase.error != nil {
                        fallbackCover
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.cardBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 1)
                                )
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .frame(width: 50, height: 75)
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            } else {
                fallbackCover
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.custom("EBGaramond-Regular", size: 17))
                    .foregroundColor(settings.textColor)
                    .lineLimit(2)

                Text(book.primaryAuthorName)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(settings.secondaryTextColor)
                    .lineLimit(1)

                if let genre = book.primaryGenre {
                    Text(genre.uppercased())
                        .font(.custom("EBGaramond-Regular", size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(settings.cardBorderColor.opacity(0.15))
                        .foregroundColor(settings.secondaryTextColor)
                        .cornerRadius(6)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .padding(8)
            }
        }
        .padding(14)
        .background(settings.cardBackgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDownload)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var fallbackCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(settings.cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                )

            VStack(spacing: 4) {
                Image(systemName: "book.pages")
                    .font(.system(size: 14))
                    .foregroundColor(settings.mutedTextColor.opacity(0.7))

                if let firstLetter = book.title.first {
                    Text(String(firstLetter))
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(settings.mutedTextColor)
                }
            }
        }
        .frame(width: 50, height: 75)
    }
}
