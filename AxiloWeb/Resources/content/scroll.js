class AxiloScrollEngine {
    constructor() {
        this.container = null;
        this.wpm = 300;
        this.isPlaying = false;
        this.animationFrame = null;
        this.lastTime = 0;
        this.scrollAccumulator = 0;
    }

    attach(containerElement) {
        this.container = containerElement;
    }

    setContent(htmlContent) {
        if (this.container) {
            this.container.innerHTML = htmlContent;
        }
    }

    play() {
        if (this.isPlaying) return;
        this.isPlaying = true;
        this.lastTime = performance.now();
        this.frameLoop();
    }

    pause() {
        this.isPlaying = false;
        if (this.animationFrame) cancelAnimationFrame(this.animationFrame);
    }

    toggle() {
        this.isPlaying ? this.pause() : this.play();
        return this.isPlaying;
    }

    setWPM(wpm) {
        this.wpm = wpm;
    }

    frameLoop() {
        if (!this.isPlaying || !this.container) return;

        const now = performance.now();
        const deltaTime = (now - this.lastTime) / 1000; // seconds
        this.lastTime = now;

        // Calculate pixels to scroll
        // WPM to Pixels/sec? 
        // Heuristic: Average line height ~ 30px. Average words per line ~ 10-12.
        // so 300 WPM = 30 lines/min = 0.5 lines/sec = 15px/sec? 
        // Let's make it adjustable.
        // A better approximation might be: speedFactor * (WPM / 60)
        
        const speedFactor = 5; // pixels per word?
        const pixelsPerSecond = (this.wpm / 60) * 20; // Rough guess: 20px per second for 60 WPM

        this.scrollAccumulator += pixelsPerSecond * deltaTime;

        if (this.scrollAccumulator >= 1) {
            const pixels = Math.floor(this.scrollAccumulator);
            this.container.scrollTop += pixels;
            this.scrollAccumulator -= pixels;
        }

        // Check if bottom reached
        if (this.container.scrollTop + this.container.clientHeight >= this.container.scrollHeight) {
            this.pause();
            // onComplete callback?
        }

        this.animationFrame = requestAnimationFrame(() => this.frameLoop());
    }
}

window.AxiloScrollEngine = AxiloScrollEngine;
