# SpeedRead

I don't like using social media much and sometimes my brain is too fatigued to open up a book and start reading. I built this app to reduce the friction of reading so I can spend more time reading and less time scrolling.

The technique used is called Rapid Serial Visual Presentation (RSVP). If you're interested in learning more about RSVP you can check out [this paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC2696395/).

## Features
- **Supported Formats**: Read .txt, .pdf, .docx, and .epub files.
- **RSVP Technology**: Display words one at a time to increase reading speed.
- **Adjustable Speed**: Control Words Per Minute (WPM) with a simple slider.
- **Clean Interface**: Distraction-free reading environment.

## Installation (Build from Source)

This app is designed to be built and installed via Xcode on macOS (too broke to buy the developer license...).

### Prerequisites
- A Mac running macOS.
- [Xcode](https://developer.apple.com/xcode/) installed.

### Steps

1. **Clone the Repository**
   Clone this repository to your local machine:
   ```bash
   git clone https://github.com/AlpUnsal/speed_read.git
   cd speed_read
   ```
   *(Or download the ZIP file and extract it)*

2. **Open in Xcode**
   Double-click the `SpeedRead.xcodeproj` file to open the project in Xcode.

3. **Configure Signing**
   - In Xcode, select the **SpeedRead** project in the left navigation pane.
   - Select the **SpeedRead** target in the main view.
   - Go to the **Signing & Capabilities** tab.
   - Under the "Signing" section, select your **Team**.
     - If you don't have a team, select "Add an Account..." in the dropdown or go to **Xcode > Settings > Accounts** to add your Apple ID.
   - Ensure a "Bundle Identifier" is set (you may need to change it if it conflicts, e.g., `com.yourname.speedread`).

4. **Build and Run**
   - Connect your iPhone to your Mac via USB (or select a Simulator from the top bar).
   - If using a physical device, trust the developer certificate on your iPhone:
     - Go to **Settings > General > VPN & Device Management**, tap your Apple ID, and tap **Trust**.
   - Press **Cmd + R** or click the **Play** button in the top-left corner of Xcode to build and run the app.
