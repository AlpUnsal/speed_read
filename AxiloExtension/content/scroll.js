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
        const deltaTime = (now - this.lastTime) / 1000;
        this.lastTime = now;

        const pixelsPerSecond = (this.wpm / 60) * 20;
        this.scrollAccumulator += pixelsPerSecond * deltaTime;

        if (this.scrollAccumulator >= 1) {
            const pixels = Math.floor(this.scrollAccumulator);
            this.container.scrollTop += pixels;
            this.scrollAccumulator -= pixels;
        }

        if (this.container.scrollTop + this.container.clientHeight >= this.container.scrollHeight) {
            this.pause();
        }

        this.animationFrame = requestAnimationFrame(() => this.frameLoop());
    }
}
