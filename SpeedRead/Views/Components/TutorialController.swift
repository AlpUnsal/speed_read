import SwiftUI
import Combine

/// Drives the gated first-run tutorial inside the RSVP reader.
///
/// Playback auto-pauses at checkpoint words (via `RSVPViewModel.shouldAdvance`)
/// and stays paused until the user performs the required gesture. After the
/// gesture, a short grace period lets them keep experimenting before the
/// stream resumes. Inert unless `attach(viewModel:)` is called — normal
/// documents never activate it.
final class TutorialController: ObservableObject {

    enum Step: Int {
        case start
        case speed
        case peek
        case dictionary
        case finished
    }

    enum HintPosition {
        case center
        case rightEdge
        case leftEdge
    }

    struct Checkpoint {
        let step: Step
        /// Token that stays on screen while gated; nil for the gate-less start step.
        let anchor: String?
        let hintIcon: String
        let hintText: String
        let hintPosition: HintPosition
        var gateIndex: Int? = nil
    }

    static let totalSteps = 4

    @Published private(set) var isActive = false
    @Published private(set) var activeHint: Checkpoint?
    @Published private(set) var isGracePeriod = false
    @Published private(set) var showStatCard = false
    @Published private(set) var finalWPMAchieved = 0
    @Published private(set) var currentStep: Step = .start

    /// Supplied by the view so resume can respect view-level state
    /// (peek overlay open, dictionary sheet presented).
    var requestResume: (() -> Void)?

    private weak var viewModel: RSVPViewModel?
    private var checkpoints: [Checkpoint] = []
    private var completedSteps: Set<Step> = []
    private var graceTimer: Timer?
    private var dictionarySheetPending = false

    // Speed-ramp finale
    private var rampRange: ClosedRange<Int>?
    private var rampStartWPM: Double?
    private let rampTargetWPM: Double = 450

    var currentStepNumber: Int {
        min(currentStep.rawValue + 1, Self.totalSteps)
    }

    /// True while a gated checkpoint is waiting for its gesture — the center
    /// tap must not be allowed to resume playback past the gate.
    var blocksPlayback: Bool {
        guard isActive, let hint = activeHint else { return false }
        return hint.step != .start
    }

    // MARK: - Setup

    /// Resolves checkpoint word indexes against the tokenized document and arms
    /// the tutorial. Anchor words are searched rather than hardcoded so edits to
    /// the tutorial script can't silently break the checkpoints.
    func attach(viewModel: RSVPViewModel) {
        self.viewModel = viewModel
        let words = viewModel.words

        func indexOfToken(prefixed prefix: String) -> Int? {
            words.firstIndex { $0.hasPrefix(prefix) }
        }

        var resolved: [Checkpoint] = [
            Checkpoint(step: .start, anchor: nil,
                       hintIcon: "hand.tap",
                       hintText: "Tap to begin",
                       hintPosition: .center)
        ]
        let gated: [Checkpoint] = [
            Checkpoint(step: .speed, anchor: "speed.",
                       hintIcon: "arrow.up.and.down",
                       hintText: "Swipe the right side\nto change speed",
                       hintPosition: .rightEdge),
            Checkpoint(step: .peek, anchor: "context.",
                       hintIcon: "arrow.up.and.down",
                       hintText: "Swipe the left side\nto peek back",
                       hintPosition: .leftEdge),
            Checkpoint(step: .dictionary, anchor: "Perspicacity",
                       hintIcon: "character.book.closed",
                       hintText: "Press and hold the word\nto look it up",
                       hintPosition: .center)
        ]
        for var checkpoint in gated {
            guard let anchor = checkpoint.anchor,
                  let anchorIndex = indexOfToken(prefixed: anchor) else { continue }
            // The playback loop increments currentIndex before consulting the
            // gate, while the anchor word is still on screen — so the gate sits
            // one past the anchor to pause with the anchor word visible.
            checkpoint.gateIndex = anchorIndex + 1
            resolved.append(checkpoint)
        }
        checkpoints = resolved

        if let rampAnchor = indexOfToken(prefixed: "watch"), rampAnchor + 1 < words.count {
            rampRange = rampAnchor...(words.count - 1)
        }

        completedSteps = []
        rampStartWPM = nil
        dictionarySheetPending = false
        currentStep = .start
        isActive = true
        activeHint = resolved.first
    }

    func deactivate() {
        graceTimer?.invalidate()
        graceTimer = nil
        isActive = false
        activeHint = nil
        isGracePeriod = false
    }

    // MARK: - Playback gate

    /// Wired into `RSVPViewModel.shouldAdvance`. Returning false pauses playback
    /// with the checkpoint's anchor word still displayed. Checkpoints are
    /// one-shot: unlike figures, they never re-arm on backward navigation.
    func shouldAdvance(pastIndex index: Int) -> Bool {
        guard isActive, !showStatCard else { return true }
        guard let checkpoint = checkpoints.first(where: { $0.gateIndex == index }),
              !completedSteps.contains(checkpoint.step) else { return true }
        currentStep = checkpoint.step
        withAnimation(.easeIn(duration: 0.4)) {
            activeHint = checkpoint
        }
        return false
    }

    // MARK: - Gesture reports (called from RSVPView)

    func reportCenterTap() {
        guard isActive else { return }
        if let hint = activeHint, hint.step == .start {
            completedSteps.insert(.start)
            withAnimation(.easeOut(duration: 0.3)) { activeHint = nil }
            advanceStepPointer()
        } else if isGracePeriod {
            // Manual resume during grace — the tap's own play/pause toggle takes over.
            graceTimer?.invalidate()
            graceTimer = nil
            isGracePeriod = false
            advanceStepPointer()
        }
    }

    func reportSpeedGestureActive() {
        guard isActive else { return }
        if let hint = activeHint, hint.step == .speed {
            completedSteps.insert(.speed)
            withAnimation(.easeOut(duration: 0.3)) { activeHint = nil }
            armGrace()
        } else if isGracePeriod, currentStep == .speed {
            // Still experimenting — every movement restarts the countdown.
            armGrace()
        }
    }

    func reportPeekDismissed() {
        guard isActive, let hint = activeHint, hint.step == .peek else { return }
        completedSteps.insert(.peek)
        withAnimation(.easeOut(duration: 0.3)) { activeHint = nil }
        armGrace()
    }

    func reportLongPressStarted() {
        guard isActive, let hint = activeHint, hint.step == .dictionary else { return }
        completedSteps.insert(.dictionary)
        withAnimation(.easeOut(duration: 0.3)) { activeHint = nil }
        dictionarySheetPending = true
    }

    func reportDictionarySheetDismissed() {
        guard isActive, dictionarySheetPending else { return }
        dictionarySheetPending = false
        armGrace()
    }

    // MARK: - Speed-ramp finale

    /// Interpolates WPM from the user's speed at ramp entry up to the target
    /// across the final passage. Only ever raises WPM — a user already reading
    /// faster than the ramp is never slowed down.
    func applyRampIfNeeded(currentIndex: Int) {
        guard isActive, let range = rampRange, let vm = viewModel,
              range.contains(currentIndex) else { return }
        if rampStartWPM == nil {
            rampStartWPM = vm.wordsPerMinute
        }
        guard let start = rampStartWPM else { return }
        let progress = Double(currentIndex - range.lowerBound) / Double(max(range.count - 1, 1))
        let target = start + (rampTargetWPM - start) * progress
        if target > vm.wordsPerMinute {
            vm.wordsPerMinute = min(target, vm.maxWPM)
        }
    }

    func documentDidFinish() {
        guard isActive, !showStatCard, let vm = viewModel else { return }
        finalWPMAchieved = Int(vm.wordsPerMinute.rounded())
        withAnimation(.easeIn(duration: 0.4)) { showStatCard = true }
    }

    // MARK: - Grace period

    /// Debounced: repeated gesture activity keeps pushing resume back, so the
    /// stream only restarts once the user has settled for the full duration.
    private func armGrace(_ duration: TimeInterval = 2.0) {
        if !isGracePeriod {
            withAnimation(.easeIn(duration: 0.3)) { isGracePeriod = true }
        }
        graceTimer?.invalidate()
        graceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.isGracePeriod = false }
            self.advanceStepPointer()
            self.requestResume?()
        }
    }

    private func advanceStepPointer() {
        let ordered: [Step] = [.start, .speed, .peek, .dictionary]
        currentStep = ordered.first { !completedSteps.contains($0) } ?? .finished
    }
}
