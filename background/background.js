// Axilo Background Script

// Listen for the extension icon click
chrome.action.onClicked.addListener((tab) => {
  if (!tab.url.startsWith('http')) {
    return; // Only runs on web pages
  }

  // Inject content script if not already present (or just send message)
  // Since we registered content scripts in manifest, they are auto-injected.
  // We just need to send a message to toggle the reader.
  
  chrome.tabs.sendMessage(tab.id, { action: "toggle_axilo" })
    .catch(err => {
      // If content script isn't ready or failed to load
      console.warn("Axilo content script not ready:", err);
      
      // Fallback: Programmatically execute script if needed
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ['content/readability.js', 'content/content.js']
      });
    });
});
