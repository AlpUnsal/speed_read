import Foundation

/// First-launch tutorial text, played through the RSVP reader with gated
/// checkpoints (see TutorialController). Checkpoint and figure positions are
/// resolved by anchor-word search, so the anchors below must stay unique up to
/// their first occurrence: "speed." / "context." / "Perspicacity" / "needed" /
/// "watch". Instruction bursts are short — the reader shows one word at a time
/// and the overlay hints carry the teaching at each pause.
struct SampleText {
    static let content = """
    Welcome to a faster way to read.
    Most people read at 200 to 250 words per minute, but your brain can go much faster.
    This is RSVP: one word at a time, no eye movement, no wasted motion.
    Good. Let's get you comfortable with the controls.
    First, speed.
    Nice. Find a pace that feels quick but still clear.
    Next, context.
    If you ever lose your place, that's how you look back.
    One more thing.
    5.
    4.
    3.
    2.
    1.
    Perspicacity.
    That means sharp, clear understanding. Fitting.
    You can also turn web articles and saved PDFs into this reader, no copy-pasting needed.
    Stay relaxed. Don't mouth the words. Trust your brain to catch meaning as it flies by.
    Now watch what happens as we speed up. Keep your eyes still. Let the words come to you. Most readers plateau around 250 words per minute their whole lives, never questioning the habit of sounding out every syllable in their heads. But meaning arrives faster than speech. Let go of the urge to re-read. Forward only. Feel the rhythm settle in and trust it. This is what reading feels like when your eyes stop holding you back.
    """
}
