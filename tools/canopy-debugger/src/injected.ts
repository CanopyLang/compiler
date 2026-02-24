/**
 * Injected script that runs in the page context
 *
 * This script hooks into the Canopy/Elm runtime to intercept messages and state.
 */

(function () {
  'use strict';

  // Prevent double-injection
  if ((window as any).__CANOPY_DEBUGGER_INJECTED__) {
    return;
  }
  (window as any).__CANOPY_DEBUGGER_INJECTED__ = true;

  interface DebugEntry {
    index: number;
    timestamp: number;
    message: string;
    state: string;
  }

  let entryIndex = 0;

  /**
   * Send a message to the content script
   */
  function sendToExtension(message: any): void {
    window.postMessage({ source: 'canopy-debugger-page', ...message }, '*');
  }

  /**
   * Serialize a value for the debugger
   */
  function serializeValue(value: any): string {
    if (value === null) return 'null';
    if (value === undefined) return 'undefined';

    // Handle Canopy/Elm custom types
    if (typeof value === 'object' && '$' in value) {
      return serializeCustomType(value);
    }

    // Handle arrays
    if (Array.isArray(value)) {
      return '[' + value.map(serializeValue).join(', ') + ']';
    }

    // Handle objects/records
    if (typeof value === 'object') {
      return serializeRecord(value);
    }

    // Handle strings
    if (typeof value === 'string') {
      return '"' + value + '"';
    }

    return String(value);
  }

  /**
   * Serialize a custom type (e.g., Just 5, Nothing, Msg.Click)
   */
  function serializeCustomType(value: any): string {
    const ctor = value.$;
    const args = Object.keys(value)
      .filter((k) => k !== '$')
      .sort()
      .map((k) => serializeValue(value[k]));

    if (args.length === 0) {
      return ctor;
    }

    return ctor + ' ' + args.join(' ');
  }

  /**
   * Serialize a record/object
   */
  function serializeRecord(value: any): string {
    const pairs = Object.keys(value)
      .filter((k) => !k.startsWith('_'))
      .sort()
      .map((k) => k + ' = ' + serializeValue(value[k]));

    return '{ ' + pairs.join(', ') + ' }';
  }

  /**
   * Record a debug entry
   */
  function recordEntry(msg: any, model: any): void {
    const entry: DebugEntry = {
      index: entryIndex++,
      timestamp: Date.now(),
      message: serializeValue(msg),
      state: serializeValue(model)
    };

    sendToExtension({ type: 'entry', entry });

    // Also store in global for debugging
    if ((window as any).__CANOPY_DEBUGGER__) {
      (window as any).__CANOPY_DEBUGGER__.recordEntry(msg, model);
    }
  }

  /**
   * Hook into Elm's runtime
   */
  function hookElmRuntime(): void {
    // Wait for Elm to be loaded
    const checkElm = setInterval(() => {
      if (!(window as any).Elm) {
        return;
      }

      clearInterval(checkElm);
      console.log('[Canopy Debugger] Elm runtime detected');

      // Hook into Elm.init
      const originalElm = (window as any).Elm;

      Object.keys(originalElm).forEach((moduleName) => {
        const module = originalElm[moduleName];
        if (typeof module.init === 'function') {
          const originalInit = module.init;

          module.init = function (options: any) {
            const app = originalInit.call(this, options);
            hookElmApp(app, moduleName);
            return app;
          };
        }
      });

      sendToExtension({ type: 'canopyDetected', runtime: 'elm' });
    }, 100);

    // Give up after 10 seconds
    setTimeout(() => clearInterval(checkElm), 10000);
  }

  /**
   * Hook into an Elm application instance
   */
  function hookElmApp(app: any, moduleName: string): void {
    console.log('[Canopy Debugger] Hooking into module:', moduleName);

    // Store reference
    (window as any).__CANOPY_APP__ = app;

    // Hook into ports if available
    if (app.ports) {
      Object.keys(app.ports).forEach((portName) => {
        const port = app.ports[portName];

        // Hook into subscribe (outgoing ports)
        if (typeof port.subscribe === 'function') {
          const originalSubscribe = port.subscribe;
          port.subscribe = function (callback: (data: any) => void) {
            return originalSubscribe.call(this, (data: any) => {
              recordEntry({ $: 'Port', portName, data }, data);
              callback(data);
            });
          };
        }

        // Hook into send (incoming ports)
        if (typeof port.send === 'function') {
          const originalSend = port.send;
          port.send = function (data: any) {
            recordEntry({ $: 'PortIn', portName, data }, {});
            return originalSend.call(this, data);
          };
        }
      });
    }

    sendToExtension({
      type: 'appInitialized',
      module: moduleName,
      hasPorts: !!app.ports
    });
  }

  /**
   * Hook into Canopy runtime (if different from Elm)
   */
  function hookCanopyRuntime(): void {
    const checkCanopy = setInterval(() => {
      if (!(window as any).__CANOPY_DEBUGGER__) {
        return;
      }

      clearInterval(checkCanopy);
      console.log('[Canopy Debugger] Canopy runtime detected');

      const debugger_ = (window as any).__CANOPY_DEBUGGER__;

      // Hook into recordEntry
      const originalRecordEntry = debugger_.recordEntry;
      debugger_.recordEntry = function (msg: any, model: any) {
        recordEntry(msg, model);
        if (originalRecordEntry) {
          originalRecordEntry.call(this, msg, model);
        }
      };

      sendToExtension({ type: 'canopyDetected', runtime: 'canopy' });
    }, 100);

    setTimeout(() => clearInterval(checkCanopy), 10000);
  }

  /**
   * Listen for commands from the extension
   */
  window.addEventListener('message', (event) => {
    if (event.source !== window) return;
    if (event.data?.source !== 'canopy-debugger-extension') return;

    const message = event.data;

    switch (message.type) {
      case 'checkCanopy':
        const hasCanopy =
          '__CANOPY_DEBUGGER__' in window ||
          '__CANOPY_APP__' in window ||
          'Elm' in window;

        sendToExtension({ type: hasCanopy ? 'canopyDetected' : 'canopyNotDetected' });
        break;

      case 'jumpTo':
        if ((window as any).__CANOPY_DEBUGGER__?.jumpTo) {
          (window as any).__CANOPY_DEBUGGER__.jumpTo(message.index);
        }
        break;

      case 'stepForward':
        if ((window as any).__CANOPY_DEBUGGER__?.stepForward) {
          (window as any).__CANOPY_DEBUGGER__.stepForward();
        }
        break;

      case 'stepBackward':
        if ((window as any).__CANOPY_DEBUGGER__?.stepBackward) {
          (window as any).__CANOPY_DEBUGGER__.stepBackward();
        }
        break;

      case 'getHistory':
        if ((window as any).__CANOPY_DEBUGGER__?.getHistory) {
          const history = (window as any).__CANOPY_DEBUGGER__.getHistory();
          sendToExtension({ type: 'history', history });
        }
        break;
    }
  });

  // Initialize hooks
  hookElmRuntime();
  hookCanopyRuntime();

  console.log('[Canopy Debugger] Page script injected');
})();
