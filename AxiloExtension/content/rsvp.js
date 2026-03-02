class AxiloRSVPEngine {
    constructor() {
        this.words = [];
        this.currentIndex = 0;
        this.wpm = 300;
        this.isPlaying = false;
        this.timer = null;
        this.onWordUpdate = () => {};
        this.onComplete = () => {};
    }

    loadText(text) {
        this.words = this.tokenize(text);
        this.currentIndex = 0;
    }

    tokenize(text) {
        let components = text.trim().split(/\s+/);
        let words = [];
        for (let i = 0; i < components.length; i++) {
            let component = components[i].trim();
            if (!component) continue;
            let parts = this.splitOnPunctuation(component);
            words.push(...parts);
        }
        return words;
    }

    splitOnPunctuation(text) {
        if (text.length < 2) return [text];
        
        let result = [];
        let currentToken = "";
        let i = 0;
        
        while (i < text.length) {
            let char = text[i];
            
            if (char === "-" && i + 1 < text.length && text[i+1] === "-") {
                currentToken += "--";
                result.push(currentToken);
                currentToken = "";
                i += 2;
                continue;
            }
            
            if (char === "." && i + 2 < text.length && text[i+1] === "." && text[i+2] === ".") {
                currentToken += "...";
                result.push(currentToken);
                currentToken = "";
                i += 3;
                continue;
            }
            
            if (char === "\u2014" || char === "\u2013" || char === "\u2026") {
                currentToken += char;
                result.push(currentToken);
                currentToken = "";
                i += 1;
                continue;
            }
            
            currentToken += char;
            i += 1;
        }
        
        if (currentToken.length > 0) {
            result.push(currentToken);
        }
        
        return result.filter(w => w.length > 0);
    }

    getPauseMultiplier(word) {
        const closingPunctuation = new Set(["\"", "\u201D", "\u2019", "'", ")", "]", "}", "\u201C", "\u2018"]);
        let meaningfulChar = null;
        
        for (let i = word.length - 1; i >= 0; i--) {
            if (!closingPunctuation.has(word[i])) {
                meaningfulChar = word[i];
                break;
            }
        }
        
        const speedFactor = Math.min(1.5, Math.max(0.3, 300 / this.wpm));
        
        if (meaningfulChar) {
            if ([".", "!", "?"].includes(meaningfulChar)) {
                return 1.0 + (0.65 * speedFactor);
            }
            if ([",", ";", ":"].includes(meaningfulChar)) {
                return 1.0 + (0.50 * speedFactor);
            }
            if (["\u2014", "\u2013"].includes(meaningfulChar)) {
                return 1.0 + (0.55 * speedFactor);
            }
            if (word.includes("/")) {
                return 1.0 + (0.50 * speedFactor);
            }
            return 1.0;
        }
        
        if (word.includes("/")) {
            return 1.0 + (0.50 * speedFactor);
        }
        
        return 1.0;
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

        const baseDelayMs = (60 / this.wpm) * 1000;
        const currentWord = this.words[this.currentIndex] || "";
        const multiplier = this.getPauseMultiplier(currentWord);
        const nextDelayMs = baseDelayMs * multiplier;

        this.timer = setTimeout(() => {
            this.currentIndex++;
            this.scheduleNextWord();
        }, nextDelayMs);
    }

    updateDisplay() {
        const word = this.words[this.currentIndex] || "";
        const orp = this.calculateORP(word);
        this.onWordUpdate(word, orp);
    }

    calculateORP(word) {
        const length = word.length;
        let index = 0;
        
        if (length > 1) {
            index = 1; // Always highlight the second letter
        }

        return {
            left: word.substring(0, index),
            center: word.substring(index, index + 1),
            right: word.substring(index + 1)
        };
    }
}
