/**
 * Background service worker for the Canopy Debugger extension
 */

// Track devtools connections
const devtoolsConnections = new Map<number, chrome.runtime.Port>();

// Track content script connections
const contentConnections = new Map<number, chrome.runtime.Port>();

/**
 * Handle connections from devtools and content scripts
 */
chrome.runtime.onConnect.addListener((port) => {
  if (port.name === 'canopy-devtools') {
    handleDevtoolsConnection(port);
  } else if (port.name === 'canopy-content') {
    handleContentConnection(port);
  }
});

/**
 * Handle devtools panel connections
 */
function handleDevtoolsConnection(port: chrome.runtime.Port): void {
  let tabId: number | null = null;

  port.onMessage.addListener((message) => {
    if (message.type === 'init') {
      tabId = message.tabId;
      if (tabId !== null) {
        devtoolsConnections.set(tabId, port);
      }
      return;
    }

    // Forward messages to content script
    if (tabId !== null) {
      const contentPort = contentConnections.get(tabId);
      if (contentPort) {
        contentPort.postMessage(message);
      } else {
        // Try to send via tabs API
        chrome.tabs.sendMessage(tabId, message).catch(() => {
          // Tab might not have content script
        });
      }
    }
  });

  port.onDisconnect.addListener(() => {
    if (tabId !== null) {
      devtoolsConnections.delete(tabId);
    }
  });
}

/**
 * Handle content script connections
 */
function handleContentConnection(port: chrome.runtime.Port): void {
  const tabId = port.sender?.tab?.id;

  if (tabId === undefined) {
    return;
  }

  contentConnections.set(tabId, port);

  port.onMessage.addListener((message) => {
    // Forward messages to devtools
    const devtoolsPort = devtoolsConnections.get(tabId);
    if (devtoolsPort) {
      devtoolsPort.postMessage(message);
    }
  });

  port.onDisconnect.addListener(() => {
    contentConnections.delete(tabId);
  });
}

/**
 * Handle messages from content scripts (one-time messages)
 */
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const tabId = sender.tab?.id;

  if (!tabId) {
    return;
  }

  // Forward to devtools if connected
  const devtoolsPort = devtoolsConnections.get(tabId);
  if (devtoolsPort) {
    devtoolsPort.postMessage(message);
  }

  // Handle specific message types
  switch (message.type) {
    case 'canopyDetected':
      // Update badge to show Canopy is detected
      chrome.action.setBadgeText({ text: 'ON', tabId });
      chrome.action.setBadgeBackgroundColor({ color: '#4CAF50', tabId });
      break;

    case 'canopyNotDetected':
      chrome.action.setBadgeText({ text: '', tabId });
      break;
  }

  sendResponse({ received: true });
  return true;
});

/**
 * Handle tab updates
 */
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === 'complete') {
    // Check if Canopy is present on the page
    chrome.tabs.sendMessage(tabId, { type: 'checkCanopy' }).catch(() => {
      // Content script not loaded yet
    });
  }
});

/**
 * Handle tab removal
 */
chrome.tabs.onRemoved.addListener((tabId) => {
  devtoolsConnections.delete(tabId);
  contentConnections.delete(tabId);
});

console.log('[Canopy Debugger] Background service worker started');
