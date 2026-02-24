/**
 * Content script for the Canopy Debugger extension
 *
 * This script runs in the context of web pages and bridges communication
 * between the page's Canopy runtime and the extension.
 */

// Connect to background script
let backgroundPort: chrome.runtime.Port | null = null;

function connectToBackground(): void {
  backgroundPort = chrome.runtime.connect({ name: 'canopy-content' });

  backgroundPort.onMessage.addListener((message) => {
    // Forward messages to the page
    window.postMessage({ source: 'canopy-debugger-extension', ...message }, '*');
  });

  backgroundPort.onDisconnect.addListener(() => {
    backgroundPort = null;
    // Try to reconnect after a delay
    setTimeout(connectToBackground, 1000);
  });
}

connectToBackground();

/**
 * Inject the debugger hook script into the page
 */
function injectScript(): void {
  const script = document.createElement('script');
  script.src = chrome.runtime.getURL('dist/injected.js');
  script.onload = function () {
    (this as HTMLScriptElement).remove();
  };
  (document.head || document.documentElement).appendChild(script);
}

// Inject early
injectScript();

/**
 * Listen for messages from the page
 */
window.addEventListener('message', (event) => {
  // Only accept messages from the same window
  if (event.source !== window) {
    return;
  }

  // Only accept messages from our injected script
  if (event.data?.source !== 'canopy-debugger-page') {
    return;
  }

  const message = event.data;

  // Forward to background script
  if (backgroundPort) {
    backgroundPort.postMessage(message);
  } else {
    // Fallback to one-time message
    chrome.runtime.sendMessage(message).catch(() => {
      // Extension might not be active
    });
  }
});

/**
 * Listen for messages from the extension
 */
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'checkCanopy') {
    // Check if Canopy runtime is present
    window.postMessage({ source: 'canopy-debugger-extension', type: 'checkCanopy' }, '*');
    sendResponse({ received: true });
  }

  return true;
});

/**
 * Detect Canopy presence
 */
function detectCanopy(): void {
  // Check for Canopy runtime globals
  const hasCanopy =
    '__CANOPY_DEBUGGER__' in window ||
    '__CANOPY_APP__' in window ||
    'Elm' in window;

  if (hasCanopy) {
    chrome.runtime.sendMessage({ type: 'canopyDetected' }).catch(() => {
      // Extension might not be active
    });
  }
}

// Check on load
if (document.readyState === 'complete') {
  detectCanopy();
} else {
  window.addEventListener('load', detectCanopy);
}

// Also check after a delay (for dynamically loaded apps)
setTimeout(detectCanopy, 2000);

console.log('[Canopy Debugger] Content script loaded');
