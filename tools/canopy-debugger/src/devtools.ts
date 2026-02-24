/**
 * DevTools entry point - creates the Canopy panel in Chrome DevTools
 */

// Create a panel in the Elements panel sidebar
chrome.devtools.panels.create(
  'Canopy',
  'public/icon48.png',
  'panel.html',
  (panel) => {
    console.log('[Canopy Debugger] Panel created');

    // Handle panel show/hide events
    panel.onShown.addListener((window) => {
      // Panel is visible
      const port = chrome.runtime.connect({ name: 'canopy-devtools' });
      port.postMessage({ type: 'init', tabId: chrome.devtools.inspectedWindow.tabId });
    });

    panel.onHidden.addListener(() => {
      // Panel is hidden
    });
  }
);

// Also add a sidebar panel to Elements
chrome.devtools.panels.elements.createSidebarPane('Canopy State', (sidebar) => {
  // Update sidebar when selection changes
  chrome.devtools.panels.elements.onSelectionChanged.addListener(() => {
    chrome.devtools.inspectedWindow.eval(
      'window.__CANOPY_DEBUGGER__?.getState()',
      (result, exception) => {
        if (exception) {
          sidebar.setObject({ error: 'No Canopy state available' });
        } else if (result) {
          sidebar.setObject(result);
        } else {
          sidebar.setObject({ message: 'No Canopy application detected' });
        }
      }
    );
  });
});
