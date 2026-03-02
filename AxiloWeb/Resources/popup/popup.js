// Auto-execute logic to bypass iOS Safari limitations gracefully
(async () => {
    try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        
        if (tab && tab.id) {
            await chrome.tabs.sendMessage(tab.id, { action: "toggle_axilo" });
        }
    } catch (err) {
        console.error("Axilo activation error:", err);
    }
    
    // Immediately close the popup so it feels like a native click
    window.close();
})();
