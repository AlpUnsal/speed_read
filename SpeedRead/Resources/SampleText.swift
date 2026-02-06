import Foundation

/// Sample text for testing the app without importing a file
struct SampleText {
    static let content = """
    Speed reading is an incredible skill that allows you to consume information at a much faster rate than traditional reading. The average person reads at about 200 to 250 words per minute, but with practice, you can dramatically increase this speed.
    
    The technique used in this app is called Rapid Serial Visual Presentation, or RSVP. It works by displaying one word at a time at a fixed point on the screen. This eliminates the need for your eyes to move across the page, which is one of the main bottlenecks in reading speed.
    
    Each word is anchored at the optimal recognition point, which is typically around the second or third letter. This is where your brain most efficiently processes the word. The red highlighted letter shows you this anchor point.
    
    Research has shown that with practice, readers can comfortably reach speeds of 400 to 600 words per minute while maintaining good comprehension. Some trained speed readers can even reach 1000 words per minute or more.
    
    To get started, try setting the speed slider to around 300 words per minute. As you become more comfortable, gradually increase the speed. You may be surprised at how quickly your brain adapts to processing information at higher speeds.
    
    The key to successful speed reading is relaxation and trust. Trust that your brain will pick up the meaning even at higher speeds. Avoid the urge to mentally pronounce each word, a habit called subvocalization, which can slow you down.
    
    With regular practice, you will find that you can read books, articles, and documents in a fraction of the time it used to take. This can be transformative for students, professionals, and anyone who wants to stay informed in our information-rich world.
    
    Now go ahead and try adjusting the speed with the slider on the right side of the screen. Find a pace that challenges you but still allows for comprehension. Happy speed reading!
    
    Test Cases for Pausing:
    "Hello," he said.
    "Wait!" she cried.
    "Is it true?" asked John.
    (This is a parenthetical statement.)
    It was the end."
    
    Tokenizer Tests:
    Word—connected (Em dash)
    Word–connected (En dash)
    Word--connected (Double hyphen)
    Word...connected (Ellipsis dots)
    Word…connected (Ellipsis char)
    Either/Or (Slash - should stay connected)
    """
}
