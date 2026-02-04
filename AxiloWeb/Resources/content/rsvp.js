class AxiloRSVPEngine {
    constructor() {
        this.words = [];
        this.currentIndex = 0;
        this.wpm = 300;
        this.isPlaying = false;
        this.timer = null;
        this.onWordUpdate = () => {}; // Callback for UI
        this.onComplete = () => {};
    }

    loadText(text) {
        // Simple splitting for now. Improve later to handle punctuation pauses.
        this.words = text.trim().split(/\s+/);
        this.currentIndex = 0;
    }

    play() {
        if (this.isPlaying) return;
        this.isPlaying = true;
        this.scheduleNextWord();
    }

    pause() {
        this.isPlaying = false;
        if (this.timer) clearTimeout(this.timer);
    }

    toggle() {
        this.isPlaying ? this.pause() : this.play();
        return this.isPlaying;
    }

    seek(index) {
        this.currentIndex = Math.max(0, Math.min(index, this.words.length - 1));
        this.updateDisplay();
    }

    setWPM(wpm) {
        this.wpm = wpm;
    }

    scheduleNextWord() {
        if (!this.isPlaying) return;

        if (this.currentIndex >= this.words.length) {
            this.pause();
            this.onComplete();
            return;
        }

        this.updateDisplay();

        // Calculate delay based on WPM
        // 60 seconds / WPM = seconds per word
        // * 1000 = ms per word
        const msPerWord = (60 / this.wpm) * 1000;
        
        // TODO: Add extra delay for punctuation here

        this.timer = setTimeout(() => {
            this.currentIndex++;
            this.scheduleNextWord();
        }, msPerWord);
    }

    updateDisplay() {
        const word = this.words[this.currentIndex] || "";
        const orp = this.calculateORP(word);
        this.onWordUpdate(word, orp);
    }

    // Optimal Recognition Point Logic
    calculateORP(word) {
        const length = word.length;
        let index = 0;
        
        if (length <= 1) index = 0;
        else if (length <= 5) index = 1;
        else if (length <= 9) index = 2;
        else if (length <= 13) index = 3;
        else index = 4;

        return {
            left: word.substring(0, index),
            center: word.substring(index, index + 1),
            right: word.substring(index + 1)
        };
    }
}

// Attach to window so content.js can find it
window.AxiloRSVPEngine = AxiloRSVPEngine;
