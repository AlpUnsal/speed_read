// Axilo Content Script
(function() {
    if (window.hasAxiloRun) return;
    window.hasAxiloRun = true;

    let overlayRoot = null;
    let shadowDiv = null;
    let rsvpEngine = null;
    let scrollEngine = null;
    let currentMode = 'RSVP';

    // Context peek state
    let peekIndex = 0;
    let peekBaseIndex = 0;
    let wasPlayingBeforePeek = false;
    let showingPeek = false;

    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
        if (request.action === "toggle_axilo") {
            toggleReader();
            sendResponse({ status: "ok" });
        }
    });

    function toggleReader() {
        try {
            if (overlayRoot) {
                const overlay = overlayRoot.querySelector('.axilo-overlay');
                if (overlay) {
                    if (overlay.style.display === 'none') {
                        overlay.style.display = 'flex';
                        setTimeout(() => overlay.classList.add('visible'), 10);
                    } else {
                        overlay.classList.remove('visible');
                        setTimeout(() => overlay.style.display = 'none', 300);
                        if (rsvpEngine) rsvpEngine.pause();
                    }
                    return;
                }
            }
            initAxilo();
        } catch (e) {
            alert("Axilo Error: " + e.message + "\n\n" + e.stack);
        }
    }

    function initAxilo() {
        if (typeof Readability === 'undefined') {
            alert("Axilo: Readability library not loaded.");
            return;
        }

        let article;
        try {
            const documentClone = document.cloneNode(true);
            article = new Readability(documentClone).parse();
        } catch (e) {
            alert("Axilo: Readability parse error: " + e.message);
            return;
        }

        // Clean parsed text to ensure spaces exist between block elements (e.g. headings/paragraphs)
        if (article && article.content) {
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = article.content;
            
            // Insert spaces after block elements to prevent words running together
            const blockElements = tempDiv.querySelectorAll('p, h1, h2, h3, h4, h5, h6, div, li, br');
            blockElements.forEach(el => {
                el.appendChild(document.createTextNode(' '));
            });
            
            article.textContent = tempDiv.textContent;
        }

        if (!article || !article.textContent.trim()) {
            const bodyText = document.body.innerText || document.body.textContent || "";
            if (bodyText.trim().length > 100) {
                article = { textContent: bodyText, content: document.body.innerHTML };
            } else {
                alert("Axilo: Could not extract article content.");
                return;
            }
        }

        createOverlay(article);

        rsvpEngine = new AxiloRSVPEngine();
        rsvpEngine.loadText(article.textContent);

        scrollEngine = new AxiloScrollEngine();
        const scrollContainer = overlayRoot.getElementById('axilo-scroll-view');
        scrollEngine.attach(scrollContainer);
        scrollEngine.setContent(article.content);

        const wordContainer = overlayRoot.getElementById('axilo-word-display');
        const progressText = overlayRoot.getElementById('axilo-progress-text');
        const progressFill = overlayRoot.getElementById('axilo-progress-fill');

        // Canvas for measuring text width
        const measureCanvas = document.createElement('canvas');
        const measureCtx = measureCanvas.getContext('2d');
        const fontStyle = "400 48px Georgia, 'Times New Roman', Times, serif";

        function measureText(text) {
            const fontFamily = window.getComputedStyle(wordContainer).fontFamily || fontStyle;
            const fontSize = window.getComputedStyle(wordContainer).fontSize || "48px";
            measureCtx.font = `400 ${fontSize} ${fontFamily}`;
            return measureCtx.measureText(text).width;
        }

        rsvpEngine.onWordUpdate = (word, orp) => {
            wordContainer.innerHTML = `<span>${orp.left}</span><span class="axilo-rsvp-center">${orp.center}</span><span>${orp.right}</span>`;

            // Position word so ORP letter is fixed at 33% from left to give long words more room
            const container = overlayRoot.getElementById('axilo-rsvp-container');
            if (container) {
                const containerWidth = container.offsetWidth;
                const anchorX = containerWidth * 0.33;

                // Measure width of text before ORP center
                const prefixWidth = measureText(orp.left);
                const orpHalfWidth = measureText(orp.center) / 2;

                // Position: ORP center at anchorX
                const wordLeft = anchorX - prefixWidth - orpHalfWidth;
                wordContainer.style.left = wordLeft + 'px';
                wordContainer.style.top = '50%';
                wordContainer.style.transform = 'translateY(-50%)';
            }

            const pct = Math.round(((rsvpEngine.currentIndex + 1) / rsvpEngine.words.length) * 100);
            progressText.textContent = `Article ${pct}%`;
            progressFill.style.width = `${pct}%`;
        };

        rsvpEngine.onComplete = () => updatePlayButton(false);
        rsvpEngine.updateDisplay();
    }

    // === SVG Icons (thin, stroke-based, matching SF Symbols) ===
    const icons = {
        close: `<svg viewBox="0 0 24 24"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>`,
        settings: `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`,
        restart: `<svg viewBox="0 0 24 24"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>`,
        play: `<svg viewBox="0 0 24 24" class="filled"><path d="M8 5v14l11-7z"/></svg>`,
        pause: `<svg viewBox="0 0 24 24"><line x1="6" y1="4" x2="6" y2="20"/><line x1="18" y1="4" x2="18" y2="20"/></svg>`,
        skipBack: `<svg viewBox="0 0 24 24"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><polyline points="1 4 1 8 5 8" style="stroke-width:1.5"/><text x="12" y="15.5" font-size="7.5" text-anchor="middle" fill="currentColor" stroke="none" font-weight="500">10</text></svg>`,
        skipFwd: `<svg viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><polyline points="23 4 23 8 19 8" style="stroke-width:1.5"/><text x="12" y="15.5" font-size="7.5" text-anchor="middle" fill="currentColor" stroke="none" font-weight="500">10</text></svg>`,
        list: `<svg viewBox="0 0 24 24"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>`,
        search: `<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>`
    };

    function createOverlay(article) {
        shadowDiv = document.createElement('div');
        shadowDiv.id = 'axilo-shadow-host';
        shadowDiv.style.cssText = 'position:fixed;z-index:2147483647;top:0;left:0;width:100vw;height:100vh;';
        document.documentElement.appendChild(shadowDiv);

        const shadow = shadowDiv.attachShadow({ mode: 'open' });
        overlayRoot = shadow;

        const styleLink = document.createElement('link');
        styleLink.rel = 'stylesheet';
        styleLink.href = chrome.runtime.getURL('styles.css');
        shadow.appendChild(styleLink);

        const wrapper = document.createElement('div');
        wrapper.className = 'axilo-overlay visible';

        wrapper.innerHTML = `
            <!-- Top Bar -->
            <div class="axilo-top-bar">
                <button class="axilo-icon-btn" id="axilo-close" title="Close">${icons.close}</button>
                <div class="axilo-progress-text" id="axilo-progress-text">Article 0%</div>
                <div style="display:flex; gap:4px;">
                    <button class="axilo-icon-btn" id="axilo-wpm-toggle" title="Settings">${icons.settings}</button>
                    <button class="axilo-icon-btn" id="axilo-restart" title="Restart">${icons.restart}</button>
                </div>
            </div>

            <!-- Main Reader Area -->
            <div class="axilo-reader-container" id="axilo-rsvp-container">
                <div class="axilo-rsvp-word" id="axilo-word-display">Ready</div>

                <!-- WPM Feedback -->
                <div class="axilo-wpm-feedback" id="axilo-wpm-feedback"></div>

                <!-- Fixed focus lines (anchored at 33% of container, same as ORP) -->
                <div class="axilo-focus-line top"></div>
                <div class="axilo-focus-line bottom"></div>

                <!-- Context Peek (hidden) -->
                <div class="axilo-context-peek" id="axilo-context-peek" style="display:none;"></div>

                <!-- One-time swipe hint -->
                <div class="axilo-hint" id="axilo-swipe-hint" style="display:none;">Swipe up to hide the interface</div>
            </div>

            <!-- Scroll Mode -->
            <div class="axilo-scroll-container" id="axilo-scroll-view"></div>

            <!-- Settings Panel -->
            <div class="axilo-speed-control" id="axilo-speed-panel">
                <!-- Theme -->
                <div class="axilo-setting-row">
                    <span class="axilo-setting-label">Theme</span>
                    <select class="axilo-setting-select" id="axilo-theme-select">
                        <option value="cream">Cream</option>
                        <option value="white">White</option>
                        <option value="grey">Grey</option>
                        <option value="black">Black</option>
                    </select>
                </div>
                <!-- Theme / Focus Lines -->
                <div class="axilo-setting-row-horizontal">
                    <span class="axilo-setting-label">Focus Lines</span>
                    <label class="axilo-switch">
                        <input type="checkbox" id="axilo-focus-lines-toggle">
                        <span class="axilo-slider"></span>
                    </label>
                </div>
                
                <!-- Font Selection -->
                <div class="axilo-setting-row">
                    <span class="axilo-setting-label">Font Family</span>
                    <select class="axilo-setting-select" id="axilo-font-select">
                        <option value="'-apple-system', BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif">Helvetica</option>
                        <option value="'EB Garamond', Georgia, serif">EB Garamond</option>
                        <option value="'Avenir Next', Avenir, sans-serif">Avenir Next</option>
                        <option value="Georgia, serif">Georgia</option>
                    </select>
                </div>
                
                <!-- Font Size -->
                <div class="axilo-setting-row">
                    <div class="axilo-setting-row-horizontal">
                        <span class="axilo-setting-label">Font Size</span>
                        <span class="axilo-setting-label" id="axilo-font-size-label">1.00x</span>
                    </div>
                    <input type="range" class="axilo-setting-slider" id="axilo-font-size-slider" min="50" max="125" step="5" value="100">
                </div>
            </div>

            <!-- Bottom Bar -->
            <div class="axilo-bottom-bar">
                <div class="axilo-progress-track" id="axilo-progress-track">
                    <div class="axilo-progress-bg"></div>
                    <div class="axilo-progress-fill" id="axilo-progress-fill"></div>
                </div>
                <div class="axilo-controls-row">
                    <button class="axilo-icon-btn" id="axilo-list-btn" title="Sections">${icons.list}</button>
                    <button class="axilo-icon-btn" id="axilo-skip-back" title="Back 10s">${icons.skipBack}</button>
                    <button class="axilo-icon-btn axilo-play-btn" id="axilo-play-pause" title="Play">${icons.play}</button>
                    <button class="axilo-icon-btn" id="axilo-skip-fwd" title="Forward 10s">${icons.skipFwd}</button>
                    <button class="axilo-icon-btn" id="axilo-search-btn" title="Search">${icons.search}</button>
                </div>
            </div>

            <!-- Modal Overlay -->
            <div class="axilo-modal-overlay" id="axilo-modal-overlay">
                <!-- Search Modal -->
                <div class="axilo-modal" id="axilo-search-modal" style="display:none;">
                    <div class="axilo-modal-header" style="margin-bottom:0;">Find in Article</div>
                    <input type="text" class="axilo-modal-input" id="axilo-search-input" placeholder="Type a word..." autocomplete="off">
                    <div class="axilo-modal-list" id="axilo-search-results" style="display:none; max-height:200px; margin-top:8px;"></div>
                    <button class="axilo-modal-btn" id="axilo-search-cancel" style="background:transparent; color:var(--axilo-text-main); margin-top:0;">Cancel</button>
                </div>
                <!-- List Modal -->
                <div class="axilo-modal" id="axilo-list-modal" style="display:none;">
                    <div class="axilo-modal-header">Table of Contents</div>
                    <div class="axilo-modal-list" id="axilo-list-content"></div>
                    <button class="axilo-modal-btn" id="axilo-list-cancel" style="background:transparent; color:var(--axilo-text-main); margin-top:0;">Close</button>
                </div>
            </div>
        `;

        shadow.appendChild(wrapper);

        // === Element References ===
        const playBtn = shadow.getElementById('axilo-play-pause');
        const rsvpContainer = shadow.getElementById('axilo-rsvp-container');
        const scrollContainer = shadow.getElementById('axilo-scroll-view');
        const wpmFeedback = shadow.getElementById('axilo-wpm-feedback');
        const contextPeek = shadow.getElementById('axilo-context-peek');

        // === Play/Pause helper ===
        window.updatePlayButton = (isPlaying) => {
            playBtn.innerHTML = isPlaying ? icons.pause : icons.play;
        };

        let lastTapTime = 0;

        function handlePlayPause(e) {
            if (e && e.type === 'click' && (Date.now() - lastTapTime < 500)) {
                return;
            }
            lastTapTime = Date.now();

            if (showingPeek) {
                hidePeek();
                return;
            }
            const engine = getCurrentEngine();
            if (engine) {
                const isPlaying = engine.toggle();
                updatePlayButton(isPlaying);
            }
        }

        // === TAP TO PLAY/PAUSE (center zone) ===
        rsvpContainer.addEventListener('click', (e) => {
            // Don't trigger if clicking on a button
            if (e.target.closest('.axilo-icon-btn') || e.target.closest('.axilo-speed-control')) return;
            if (showingPeek) return;
            handlePlayPause(e);
        });

        // === CENTER SWIPE (Hide/Show UI) ===
        let centerTouchStartY = null;
        let centerLastY = null;
        
        rsvpContainer.addEventListener('touchstart', (e) => {
            const touch = e.touches[0];
            const rect = rsvpContainer.getBoundingClientRect();
            const relX = (touch.clientX - rect.left) / rect.width;

            if (relX >= 0.30 && relX <= 0.70) {
                centerTouchStartY = touch.clientY;
                centerLastY = touch.clientY;
            }
        }, { passive: true });

        rsvpContainer.addEventListener('touchmove', (e) => {
            if (centerTouchStartY !== null) {
                const touch = e.touches[0];
                const deltaY = touch.clientY - centerLastY;
                
                if (Math.abs(touch.clientY - centerTouchStartY) > 15) {
                    if (deltaY < -4) {
                        // Swiping UP hides UI
                        wrapper.classList.add('ui-hidden');
                    } else if (deltaY > 4) {
                        // Swiping DOWN shows UI
                        wrapper.classList.remove('ui-hidden');
                    }
                }
                centerLastY = touch.clientY;
            }
        }, { passive: true });

        rsvpContainer.addEventListener('touchend', () => {
            centerTouchStartY = null;
            centerLastY = null;
        });

        // === RIGHT-SIDE SWIPE: WPM Control ===
        let rightTouchStartY = null;
        let rightLastY = null;
        let wpmFeedbackTimer = null;

        rsvpContainer.addEventListener('touchstart', (e) => {
            const touch = e.touches[0];
            const rect = rsvpContainer.getBoundingClientRect();
            const relX = (touch.clientX - rect.left) / rect.width;

            if (relX > 0.70) {
                // Right zone: WPM swipe
                rightTouchStartY = touch.clientY;
                rightLastY = touch.clientY;
            }
        }, { passive: true });

        rsvpContainer.addEventListener('touchmove', (e) => {
            if (rightTouchStartY !== null) {
                const touch = e.touches[0];
                const deltaY = touch.clientY - rightLastY;
                rightLastY = touch.clientY;

                // Swipe up = faster (negative deltaY), down = slower
                const sensitivity = 1.5;
                const wpmDelta = -deltaY * sensitivity;
                if (rsvpEngine) {
                    rsvpEngine.wpm = Math.max(100, Math.min(1000, rsvpEngine.wpm + wpmDelta));
                    if (scrollEngine) scrollEngine.setWPM(rsvpEngine.wpm);

                    // Show feedback
                    const display = overlayRoot.getElementById('axilo-wpm-display');
                    if (display) display.textContent = `${Math.round(rsvpEngine.wpm)} WPM`;
                    
                    wpmFeedback.textContent = `${Math.round(rsvpEngine.wpm)} WPM`;
                    wpmFeedback.classList.add('visible');
                    clearTimeout(wpmFeedbackTimer);
                }
                e.preventDefault();
            }
        }, { passive: false });

        rsvpContainer.addEventListener('touchend', (e) => {
            if (rightTouchStartY !== null) {
                const totalMove = Math.abs((rightLastY || 0) - rightTouchStartY);
                rightTouchStartY = null;
                rightLastY = null;

                // If barely moved, treat as tap
                if (totalMove < 10) {
                    handlePlayPause();
                }

                // Hide WPM feedback after delay
                wpmFeedbackTimer = setTimeout(() => {
                    wpmFeedback.classList.remove('visible');
                    // Save WPM
                    if (rsvpEngine) chrome.storage.sync.set({ axilo_wpm: Math.round(rsvpEngine.wpm) });
                }, 1500);
            }
        });

        // === LEFT-SIDE SWIPE: Context Peek (Scroll Wheel) ===
        let leftTouchStartY = null;
        let leftLastY = null;
        let leftIsActive = false;

        rsvpContainer.addEventListener('touchstart', (e) => {
            const touch = e.touches[0];
            const rect = rsvpContainer.getBoundingClientRect();
            const relX = (touch.clientX - rect.left) / rect.width;

            if (relX < 0.30) {
                leftTouchStartY = touch.clientY;
                leftLastY = touch.clientY;
                leftIsActive = false;
            }
        }, { passive: true });

        rsvpContainer.addEventListener('touchmove', (e) => {
            if (leftTouchStartY !== null) {
                const touch = e.touches[0];
                const totalMove = Math.abs(touch.clientY - leftTouchStartY);

                // Activate peek after 15px of movement
                if (!leftIsActive && totalMove > 15) {
                    leftIsActive = true;
                    if (!showingPeek) {
                        showingPeek = true;
                        if (rsvpEngine && rsvpEngine.isPlaying) {
                            wasPlayingBeforePeek = true;
                            rsvpEngine.pause();
                            updatePlayButton(false);
                        }
                        peekIndex = rsvpEngine ? rsvpEngine.currentIndex : 0;
                        peekBaseIndex = peekIndex;
                        renderPeek();
                    }
                }

                if (leftIsActive && showingPeek && rsvpEngine) {
                    const deltaY = touch.clientY - leftLastY;
                    leftLastY = touch.clientY;

                    const sensitivity = 30; // px per word
                    const wordDelta = Math.round(-deltaY / sensitivity * 3);
                    peekIndex = Math.max(0, Math.min(rsvpEngine.words.length - 1, peekIndex + wordDelta));
                    renderPeek();
                    e.preventDefault();
                }
            }
        }, { passive: false });

        rsvpContainer.addEventListener('touchend', (e) => {
            if (leftTouchStartY !== null) {
                const totalMove = Math.abs((leftLastY || 0) - leftTouchStartY);
                leftTouchStartY = null;
                leftLastY = null;

                if (!leftIsActive && totalMove < 10) {
                    // Tap — play/pause
                    handlePlayPause();
                }
                leftIsActive = false;
                // Don't auto-dismiss peek — user taps to dismiss
            }
        });

        function renderPeek() {
            if (!rsvpEngine) return;
            contextPeek.style.display = 'flex';

            const halfCount = 4; // Max 4 words above and below
            contextPeek.innerHTML = '';
            
            for (let offset = -halfCount; offset <= halfCount; offset++) {
                const idx = peekIndex + offset;
                if (idx < 0 || idx >= rsvpEngine.words.length) {
                    // Placeholder for spacing integrity
                    const phantom = document.createElement('div');
                    phantom.style.height = '48px'; 
                    contextPeek.appendChild(phantom);
                    continue;
                }
                const word = rsvpEngine.words[idx];

                const wordEl = document.createElement('div');
                if (offset === 0) {
                    const orp = rsvpEngine.calculateORP(word);
                    wordEl.className = 'axilo-peek-word current';
                    wordEl.innerHTML = `<span>${orp.left}</span><span class="axilo-rsvp-center">${orp.center}</span><span>${orp.right}</span>`;
                } else {
                    const opacity = Math.max(0.15, 0.5 - Math.abs(offset) * 0.08); // Adjust opacities to drop off slower over 4 items
                    wordEl.className = 'axilo-peek-word';
                    wordEl.style.opacity = opacity;
                    wordEl.textContent = word;
                }

                // Attach click listener to exact word
                wordEl.onclick = (e) => {
                    e.stopPropagation();
                    if (rsvpEngine) rsvpEngine.seek(idx);
                    rsvpEngine.updateDisplay();
                    wasPlayingBeforePeek = false; // Intentionally cancel resume
                    hidePeek();
                };
                
                contextPeek.appendChild(wordEl);
            }

            // Click empty space inside overlay dismisses without changing word based on last peek scroll
            contextPeek.onclick = (e) => {
                e.stopPropagation();
                if (rsvpEngine) rsvpEngine.seek(peekIndex);
                rsvpEngine.updateDisplay();
                wasPlayingBeforePeek = false;
                hidePeek();
            };
        }

        function hidePeek() {
            showingPeek = false;
            contextPeek.style.display = 'none';
        }

        // === Button Listeners ===

        // Close
        shadow.getElementById('axilo-close').addEventListener('click', () => {
            wrapper.classList.remove('visible');
            setTimeout(() => {
                if (shadowDiv) shadowDiv.remove();
                overlayRoot = null;
                shadowDiv = null;
                if (rsvpEngine) rsvpEngine.pause();
                if (scrollEngine) scrollEngine.pause();
                window.hasAxiloRun = false;
            }, 300);
        });

        // Restart
        shadow.getElementById('axilo-restart').addEventListener('click', () => {
            if (rsvpEngine) {
                rsvpEngine.currentIndex = 0;
                rsvpEngine.updateDisplay();
            }
        });

        // Play/Pause
        playBtn.addEventListener('click', (e) => handlePlayPause(e));

        // Skip Back
        shadow.getElementById('axilo-skip-back').addEventListener('click', () => {
            if (rsvpEngine) {
                const skipCount = Math.max(1, Math.floor((rsvpEngine.wpm / 60) * 10));
                rsvpEngine.seek(rsvpEngine.currentIndex - skipCount);
                rsvpEngine.updateDisplay();
            }
        });

        // Skip Forward
        shadow.getElementById('axilo-skip-fwd').addEventListener('click', () => {
            if (rsvpEngine) {
                const skipCount = Math.max(1, Math.floor((rsvpEngine.wpm / 60) * 10));
                rsvpEngine.seek(rsvpEngine.currentIndex + skipCount);
                rsvpEngine.updateDisplay();
            }
        });

        // === Interactive Progress Bar ===
        const progressTrack = shadow.getElementById('axilo-progress-track');
        let isDraggingProgress = false;

        function updateProgressFromEvent(e) {
            if (!rsvpEngine || !progressTrack) return;
            const rect = progressTrack.getBoundingClientRect();
            // In shadow DOM, event targets can be tricky, use clientX
            let x = e.clientX || (e.touches && e.touches[0].clientX);
            if (x === undefined) return;
            
            let percentage = (x - rect.left) / rect.width;
            percentage = Math.max(0, Math.min(1, percentage));
            
            const targetIndex = Math.floor(percentage * (rsvpEngine.words.length - 1));
            rsvpEngine.seek(targetIndex);
            rsvpEngine.updateDisplay();
        }

        progressTrack.addEventListener('mousedown', (e) => {
            isDraggingProgress = true;
            updateProgressFromEvent(e);
        });
        document.addEventListener('mousemove', (e) => {
            if (isDraggingProgress) updateProgressFromEvent(e);
        });
        document.addEventListener('mouseup', () => {
            isDraggingProgress = false;
        });
        
        // Touch support for progress bar
        progressTrack.addEventListener('touchstart', (e) => {
            isDraggingProgress = true;
            updateProgressFromEvent(e);
        }, { passive: true });
        document.addEventListener('touchmove', (e) => {
            if (isDraggingProgress) updateProgressFromEvent(e);
        }, { passive: true });
        document.addEventListener('touchend', () => {
            isDraggingProgress = false;
        });

        // === Modals (List & Search) ===
        const modalOverlay = shadow.getElementById('axilo-modal-overlay');
        const searchModal = shadow.getElementById('axilo-search-modal');
        const listModal = shadow.getElementById('axilo-list-modal');
        const searchInput = shadow.getElementById('axilo-search-input');
        
        function closeModal() {
            modalOverlay.classList.remove('open');
            setTimeout(() => {
                searchModal.style.display = 'none';
                listModal.style.display = 'none';
            }, 200);
        }

        // List
        shadow.getElementById('axilo-list-btn').addEventListener('click', () => {
            if (rsvpEngine) rsvpEngine.pause();
            updatePlayButton(false);
            
            const listContent = shadow.getElementById('axilo-list-content');
            listContent.innerHTML = '';
            
            if (article && article.content && rsvpEngine) {
                const tempDiv = document.createElement('div');
                tempDiv.innerHTML = article.content;
                const headings = tempDiv.querySelectorAll('h1, h2, h3');
                
                if (headings.length === 0) {
                    listContent.innerHTML = '<div style="text-align:center; padding:20px; color:var(--axilo-text-dim);">No headings found.</div>';
                } else {
                    // Try to map headings to approximate array indices based on position in text
                    const fullText = tempDiv.textContent;
                    
                    headings.forEach((h) => {
                        const hText = h.textContent.trim();
                        if (!hText) return;
                        
                        const item = document.createElement('div');
                        item.className = 'axilo-modal-list-item';
                        item.textContent = hText.substring(0, 60) + (hText.length > 60 ? '...' : '');
                        
                        // Estimate character offset
                        const offset = fullText.indexOf(hText);
                        let targetIndex = 0;
                        if (offset > 0) {
                            const ratio = offset / fullText.length;
                            targetIndex = Math.floor(ratio * rsvpEngine.words.length);
                        }

                        item.onclick = () => {
                            rsvpEngine.seek(targetIndex);
                            rsvpEngine.updateDisplay();
                            closeModal();
                        };
                        listContent.appendChild(item);
                    });
                }
            }
            
            searchModal.style.display = 'none';
            listModal.style.display = 'flex';
            modalOverlay.classList.add('open');
        });
        
        shadow.getElementById('axilo-list-cancel').addEventListener('click', closeModal);

        // Search
        const searchResults = shadow.getElementById('axilo-search-results');
        
        shadow.getElementById('axilo-search-btn').addEventListener('click', () => {
            if (rsvpEngine) rsvpEngine.pause();
            updatePlayButton(false);
            
            listModal.style.display = 'none';
            searchModal.style.display = 'flex';
            modalOverlay.classList.add('open');
            
            searchInput.value = '';
            searchResults.innerHTML = '';
            searchResults.style.display = 'none';
            setTimeout(() => searchInput.focus(), 100);
        });
        
        searchInput.addEventListener('input', () => {
            const query = searchInput.value.trim().toLowerCase();
            searchResults.innerHTML = '';
            
            if (!query || query.length < 2 || !rsvpEngine) {
                searchResults.style.display = 'none';
                return;
            }
            
            let resultsFound = 0;
            const maxResults = 50; // Cap to avoid freezing UI
            
            // Search through words
            for (let i = 0; i < rsvpEngine.words.length; i++) {
                if (rsvpEngine.words[i].toLowerCase().includes(query)) {
                    resultsFound++;
                    
                    // Create context snippet (3 words before, match, 3 words after)
                    const startIdx = Math.max(0, i - 3);
                    const endIdx = Math.min(rsvpEngine.words.length - 1, i + 3);
                    
                    const item = document.createElement('div');
                    item.className = 'axilo-modal-list-item';
                    
                    let snippetHTML = '';
                    for (let j = startIdx; j <= endIdx; j++) {
                        if (j === i) {
                            snippetHTML += `<strong style="color:var(--axilo-red);">${rsvpEngine.words[j]}</strong> `;
                        } else {
                            snippetHTML += `${rsvpEngine.words[j]} `;
                        }
                    }
                    
                    item.innerHTML = snippetHTML.trim();
                    const targetIndex = i; // capture in closure
                    
                    item.onclick = () => {
                        rsvpEngine.seek(targetIndex);
                        rsvpEngine.updateDisplay();
                        closeModal();
                    };
                    
                    searchResults.appendChild(item);
                    
                    if (resultsFound >= maxResults) break;
                }
            }
            
            if (resultsFound > 0) {
                searchResults.style.display = 'flex';
            } else {
                searchResults.style.display = 'flex';
                searchResults.innerHTML = '<div style="text-align:center; padding:10px; color:var(--axilo-text-dim); font-size:14px;">No matches found.</div>';
            }
        });
        
        searchInput.addEventListener('click', (e) => e.stopPropagation()); // Prevent closing modal
        
        // Removed Enter-to-cycle logic in favor of tap-to-select
        
        shadow.getElementById('axilo-search-cancel').addEventListener('click', () => {
            searchInput.value = "";
            closeModal();
        });

        // Settings Panel Toggle
        const wpmPanel = shadow.getElementById('axilo-speed-panel');
        shadow.getElementById('axilo-wpm-toggle').addEventListener('click', (e) => {
            wpmPanel.classList.toggle('open');
            e.stopPropagation();
        });
        
        // Close settings when clicking outside
        rsvpContainer.addEventListener('click', () => {
            wpmPanel.classList.remove('open');
        });

        // Settings Elements
        const focusToggle = shadow.getElementById('axilo-focus-lines-toggle');
        const fontSelect = shadow.getElementById('axilo-font-select');
        const fontSizeSlider = shadow.getElementById('axilo-font-size-slider');
        const fontSizeLabel = shadow.getElementById('axilo-font-size-label');
        const wordDisplayContainer = shadow.getElementById('axilo-word-display');
        const readerContainer = shadow.getElementById('axilo-rsvp-container');

        // Load Settings
        chrome.storage.sync.get(['axilo_wpm', 'axilo_focus_lines', 'axilo_font_family', 'axilo_font_size', 'axilo_theme', 'axilo_hint_seen'], (result) => {
            // Restore WPM (now hidden from UI, managed by swipe only)
            if (result && result.axilo_wpm) {
                const saved = parseInt(result.axilo_wpm);
                if (rsvpEngine) rsvpEngine.setWPM(saved);
                if (scrollEngine) scrollEngine.setWPM(saved);
            }
            
            // Focus Lines
            if (result && result.axilo_focus_lines === true) {
                focusToggle.checked = true;
                readerContainer.classList.add('axilo-focus-lines');
            }
            
            // Font Family
            if (result && result.axilo_font_family) {
                fontSelect.value = result.axilo_font_family;
                wordDisplayContainer.style.fontFamily = result.axilo_font_family;
            }
            
            // Font Size
            if (result && result.axilo_font_size) {
                const sizePct = parseInt(result.axilo_font_size);
                fontSizeSlider.value = sizePct;
                fontSizeLabel.textContent = `${(sizePct / 100).toFixed(2)}x`;
                wordDisplayContainer.style.fontSize = `${(sizePct / 100) * 48}px`; // 48px is base
            }
            
            // Theme
            const themeSelect = shadow.getElementById('axilo-theme-select');
            function applyTheme(themeName) {
                wrapper.classList.remove('axilo-theme-black', 'axilo-theme-grey', 'axilo-theme-white');
                if (themeName !== 'cream') wrapper.classList.add(`axilo-theme-${themeName}`);
            }
            if (result && result.axilo_theme) {
                themeSelect.value = result.axilo_theme;
                applyTheme(result.axilo_theme);
            }
            themeSelect.addEventListener('change', (e) => {
                const t = e.target.value;
                applyTheme(t);
                chrome.storage.sync.set({ axilo_theme: t });
            });
            themeSelect.addEventListener('click', (e) => e.stopPropagation());
            
            // One-time swipe hint
            if (!result || !result.axilo_hint_seen) {
                const hintEl = shadow.getElementById('axilo-swipe-hint');
                if (hintEl) {
                    // Show after a brief delay so the reader is fully visible first
                    setTimeout(() => {
                        hintEl.style.display = 'block';
                        // Fade out after 2.5s, then remove
                        setTimeout(() => {
                            hintEl.classList.add('fade-out');
                            setTimeout(() => hintEl.remove(), 600);
                        }, 2500);
                    }, 800);
                    chrome.storage.sync.set({ axilo_hint_seen: true });
                }
            }
        });

        // Save Settings Listeners
        focusToggle.addEventListener('change', (e) => {
            const isEnabled = e.target.checked;
            if (isEnabled) {
                readerContainer.classList.add('axilo-focus-lines');
            } else {
                readerContainer.classList.remove('axilo-focus-lines');
            }
            chrome.storage.sync.set({ axilo_focus_lines: isEnabled });
        });
        
        fontSelect.addEventListener('change', (e) => {
            const font = e.target.value;
            wordDisplayContainer.style.fontFamily = font;
            if (rsvpEngine) rsvpEngine.updateDisplay(); // trigger reflow for ORP recalculation
            chrome.storage.sync.set({ axilo_font_family: font });
        });
        
        fontSizeSlider.addEventListener('input', (e) => {
            const sizePct = parseInt(e.target.value);
            fontSizeLabel.textContent = `${(sizePct / 100).toFixed(2)}x`;
            wordDisplayContainer.style.fontSize = `${(sizePct / 100) * 48}px`;
            if (rsvpEngine) rsvpEngine.updateDisplay();
            chrome.storage.sync.set({ axilo_font_size: sizePct });
        });
    }

    function getCurrentEngine() {
        return currentMode === 'RSVP' ? rsvpEngine : scrollEngine;
    }

})();
