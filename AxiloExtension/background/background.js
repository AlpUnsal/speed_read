// Axilo Background Script

chrome.action.onClicked.addListener((tab) => {
    if (tab && tab.id) {
        chrome.tabs.sendMessage(tab.id, { action: "toggle_axilo" }).catch((e) => {
            // If the content script isn't running yet, we could manually inject it here
            // but manifest.json already sets content_scripts to run on <all_urls>
            console.log("Axilo injection failed or already running:", e);
            
            // Fallback programmatic injection for stubborn sites
            chrome.scripting.executeScript({
                target: { tabId: tab.id },
                files: ["readability.js", "rsvp.js", "scroll.js", "content.js"]
            }).then(() => {
                chrome.tabs.sendMessage(tab.id, { action: "toggle_axilo" });
            });
        });
    }
});
