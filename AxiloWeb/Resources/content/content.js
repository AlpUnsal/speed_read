// Axilo Content Script
(function() {
    if (window.hasAxiloRun) return;
    window.hasAxiloRun = true;

    let overlayRoot = null;
    let shadowDiv = null; // The host element
    let rsvpEngine = null;
    let scrollEngine = null;
    let currentMode = 'RSVP'; // 'RSVP' or 'SCROLL'

    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
        if (request.action === "toggle_axilo") {
            toggleReader();
        }
    });

    function toggleReader() {
        // If overlay exists, just toggle visibility
        if (overlayRoot) {
            const overlay = overlayRoot.querySelector('.axilo-overlay');
            if (overlay) {
                if (overlay.style.display === 'none') {
                    overlay.style.display = 'flex';
                    setTimeout(() => overlay.classList.add('visible'), 10);
                } else {
                    overlay.classList.remove('visible');
                    setTimeout(() => overlay.style.display = 'none', 300);
                    rsvpEngine.pause();
                }
                return;
            }
        }

        // Initialize
        initAxilo();
    }

    function initAxilo() {
        console.log("Axilo: Initializing...");

        // 1. Parse content
        if (typeof Readability === 'undefined') {
            console.error("Readability not found");
            return;
        }
        const documentClone = document.cloneNode(true);
        const article = new Readability(documentClone).parse();

        if (!article) {
            alert("Axilo: Could not extract article content.");
            return;
        }

        // 2. Create UI (Shadow DOM)
        createOverlay(article);

        // 3. Start Engines
        rsvpEngine = new window.AxiloRSVPEngine();
        rsvpEngine.loadText(article.textContent);

        scrollEngine = new window.AxiloScrollEngine();
        // For scroll engine, we need HTML content. Readability gives us `.content` (HTML string)
        // We might want to sanitize or style it.
        const scrollContainer = overlayRoot.getElementById('axilo-scroll-view');
        scrollEngine.attach(scrollContainer);
        scrollEngine.setContent(article.content); // Inject HTML

        
        // Bind RSVP UI updates
        const wordContainer = overlayRoot.getElementById('axilo-word-display');
        const progressText = overlayRoot.getElementById('axilo-progress-text');
        const progressFill = overlayRoot.getElementById('axilo-progress-fill');
        
        rsvpEngine.onWordUpdate = (word, orp) => {
            wordContainer.innerHTML = `
                <span>${orp.left}</span><span class="axilo-rsvp-center">${orp.center}</span><span>${orp.right}</span>
            `;
            
            const current = rsvpEngine.currentIndex + 1;
            const total = rsvpEngine.words.length;
            progressText.textContent = `${current} / ${total}`;
            progressFill.style.width = `${(current / total) * 100}%`;
        };
        
        rsvpEngine.onComplete = () => {
             updatePlayButton(false);
        };
        
        // Initial render
        rsvpEngine.updateDisplay();
    }

    function createOverlay(article) {
        // Host element
        shadowDiv = document.createElement('div');
        shadowDiv.id = 'axilo-shadow-host';
        shadowDiv.style.position = 'fixed';
        shadowDiv.style.zIndex = '2147483647';
        shadowDiv.style.top = '0';
        shadowDiv.style.left = '0';
        document.body.appendChild(shadowDiv);

        // Shadow Root
        const shadow = shadowDiv.attachShadow({ mode: 'open' });
        overlayRoot = shadow;

        // Inject Styles
        const styleLink = document.createElement('link');
        styleLink.rel = 'stylesheet';
        styleLink.href = chrome.runtime.getURL('content/styles.css');
        shadow.appendChild(styleLink);

        // Icons
        const icons = {
            close: `<svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>`,
            restart: `<svg viewBox="0 0 24 24"><path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>`,
            play: `<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`,
            pause: `<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`,
            skipBack: `<svg viewBox="0 0 24 24"><path d="M11 18V6l-8.5 6 8.5 6zm.5-6l8.5 6V6l-8.5 6z"/></svg>`,
            skipFwd: `<svg viewBox="0 0 24 24"><path d="M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z"/></svg>`,
            modeSwitch: `<svg viewBox="0 0 24 24"><path d="M3 5h18v2H3V5zm0 6h18v2H3v-2zm0 6h18v2H3v-2z"/></svg>` // List icon for Scroll mode
        };

        // Build HTML
        const wrapper = document.createElement('div');
        wrapper.className = 'axilo-overlay visible'; 
        
        wrapper.innerHTML = `
            <!-- Top Bar -->
            <div class="axilo-top-bar">
                <button class="axilo-icon-btn" id="axilo-close" title="Close">${icons.close}</button>
                <button class="axilo-icon-btn" id="axilo-mode-toggle" title="Switch Mode" style="margin-right: auto; margin-left: 20px;">${icons.modeSwitch}</button>
                <div class="axilo-progress-text" id="axilo-progress-text">0 / 0</div>
                <button class="axilo-icon-btn" id="axilo-restart" title="Restart">${icons.restart}</button>
            </div>
            
            <!-- Main Content: RSVP -->
            <div class="axilo-reader-container" id="axilo-rsvp-container">
                <div class="axilo-rsvp-word" id="axilo-word-display">Ready</div>
            </div>

            <!-- Main Content: Scroll -->
            <div class="axilo-scroll-container" id="axilo-scroll-view"></div>

            <!-- Speed Control -->
            <div class="axilo-speed-control">
                <span class="axilo-wpm-label" id="axilo-wpm-display">300 WPM</span>
                <input type="range" min="100" max="1000" step="10" value="300" id="axilo-wpm-slider">
            </div>

            <!-- Bottom Bar -->
            <div class="axilo-bottom-bar">
                <div class="axilo-controls-row">
                    <button class="axilo-icon-btn" id="axilo-skip-back" title="Back 15">${icons.skipBack}</button>
                    <button class="axilo-icon-btn axilo-play-btn" id="axilo-play-pause" title="Play/Pause">${icons.play}</button>
                    <button class="axilo-icon-btn" id="axilo-skip-fwd" title="Forward 15">${icons.skipFwd}</button>
                </div>
                <div class="axilo-progress-track">
                    <div class="axilo-progress-fill" id="axilo-progress-fill"></div>
                </div>
            </div>
        `;

        shadow.appendChild(wrapper);

        // === Event Listeners ===
        const playBtn = shadow.getElementById('axilo-play-pause');
        const modeBtn = shadow.getElementById('axilo-mode-toggle');
        const rsvpContainer = shadow.getElementById('axilo-rsvp-container');
        const scrollContainer = shadow.getElementById('axilo-scroll-view');

        // Helper to update play button icon
        window.updatePlayButton = (isPlaying) => {
             playBtn.innerHTML = isPlaying ? icons.pause : icons.play;
        };

        // 1. Close
        shadow.getElementById('axilo-close').addEventListener('click', () => {
             wrapper.classList.remove('visible');
             setTimeout(() => {
                 if(shadowDiv) shadowDiv.remove();
                 overlayRoot = null;
                 rsvpEngine.pause();
                 scrollEngine.pause();
             }, 300);
        });

        // 2. Restart
        shadow.getElementById('axilo-restart').addEventListener('click', () => {
             // rsvpEngine handled currentIndex. scrollEngine might need scrollTop = 0
             if(currentMode === 'RSVP') {
                 rsvpEngine.currentIndex = 0;
                 rsvpEngine.updateDisplay();
             } else {
                 scrollContainer.scrollTop = 0;
             }
        });

        // 3. Play/Pause
        playBtn.addEventListener('click', () => {
            const engine = getCurrentEngine();
            const isPlaying = engine.toggle();
            updatePlayButton(isPlaying);
        });

        // 4. Mode Switch
        modeBtn.addEventListener('click', () => {
            // Pause current
            getCurrentEngine().pause();
            updatePlayButton(false);

            if (currentMode === 'RSVP') {
                currentMode = 'SCROLL';
                rsvpContainer.classList.add('hidden'); // logic needed in styles or class
                rsvpContainer.style.display = 'none';
                scrollContainer.classList.add('active');
                modeBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9h-4v4h-2v-4H9V9h4V5h2v4h4v2z"/></svg>`; // Switch to 'Card' or 'Word' icon
            } else {
                currentMode = 'RSVP';
                scrollContainer.classList.remove('active');
                rsvpContainer.style.display = 'flex'; // Restore flex
                modeBtn.innerHTML = icons.modeSwitch;
            }
        });

        // 5. Skip Back (-15)
        shadow.getElementById('axilo-skip-back').addEventListener('click', () => {
             if(currentMode === 'RSVP') rsvpEngine.seek(rsvpEngine.currentIndex - 15);
             // Scroll text back? maybe scrollBy -100px?
             else scrollContainer.scrollTop -= 100;
        });

        // 6. Skip Fwd (+15)
        shadow.getElementById('axilo-skip-fwd').addEventListener('click', () => {
             if(currentMode === 'RSVP') rsvpEngine.seek(rsvpEngine.currentIndex + 15);
             else scrollContainer.scrollTop += 100;
        });

        // 7. WPM Slider
        const wpmSlider = shadow.getElementById('axilo-wpm-slider');
        const wpmDisplay = shadow.getElementById('axilo-wpm-display');
        
        wpmSlider.addEventListener('input', (e) => {
            const val = parseInt(e.target.value);
            rsvpEngine.setWPM(val);
            scrollEngine.setWPM(val);
            wpmDisplay.textContent = `${val} WPM`;
        });

        // Spacebar
        document.addEventListener('keydown', (e) => {
           if (wrapper.parentElement && wrapper.style.display !== 'none' && e.code === 'Space') {
               e.preventDefault();
               const engine = getCurrentEngine();
               const isPlaying = engine.toggle();
               updatePlayButton(isPlaying);
           }
        });
    }
    
    function getCurrentEngine() {
        return currentMode === 'RSVP' ? rsvpEngine : scrollEngine;
    }

})();
