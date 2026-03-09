{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Test harness generation for both unit and browser tests.
--
-- Produces the JavaScript harness that wraps compiled test code
-- with the appropriate test runner infrastructure.
--
-- == Unit Test Harness
--
-- For simple unit tests, generates a Node.js script that initializes
-- the compiled Canopy modules and extracts test results from the
-- virtual DOM output.
--
-- == Browser Test Harness
--
-- For browser\/async tests, the compiled output already includes all FFI
-- JavaScript (test-runner.js, task-executor.js, playwright.js,
-- browser-test-runner.js) via normal FFI imports. The harness just
-- wraps the compiled output with a DOM shim, configuration, and
-- execution bootstrap.
--
-- @since 0.19.1
module Test.Harness
  ( -- * Types
    JsContent (..),
    HarnessConfig (..),
    HarnessContent (..),

    -- * Generation
    generateBrowserHarness,
    generateBrowserTestHarness,
    generateUnitHarness,

    -- * Lenses
    harnessServerPort,
    harnessHeaded,
    harnessSlowMo,
  )
where

import Control.Lens (makeLenses, (^.))
import Data.Text (Text)
import Data.Word (Word16)
import qualified Data.Text as Text

import Test.Server (ServerPort (..))

-- | JavaScript file content wrapper.
newtype JsContent = JsContent {unJsContent :: Text}
  deriving (Eq, Show)

-- | Configuration for the browser test harness.
data HarnessConfig = HarnessConfig
  { -- | Port the embedded server is listening on
    _harnessServerPort :: !ServerPort,
    -- | Whether to show the browser window (non-headless)
    _harnessHeaded :: !Bool,
    -- | Milliseconds delay between Playwright actions
    _harnessSlowMo :: !Word16
  }
  deriving (Eq, Show)

makeLenses ''HarnessConfig

-- | Generated harness JavaScript content.
newtype HarnessContent = HarnessContent {unHarnessContent :: Text}
  deriving (Eq, Show)

-- | Generate a browser test harness from compiled test output.
--
-- The compiled output already includes all FFI JavaScript
-- (test-runner.js, task-executor.js, playwright.js) via normal
-- FFI imports in the Canopy test packages. The harness wraps
-- the compiled output with:
--
-- 1. DOM shim (provides @document@\/@window@ for Canopy runtime)
-- 2. Stdout guard (redirect @console.log@ to stderr)
-- 3. Compiled test code (includes all FFI JS)
-- 4. Configuration (server URL, browser options)
-- 5. Execute section (calls @runAndReport@)
--
-- @since 0.19.1
generateBrowserHarness ::
  HarnessConfig ->
  JsContent ->
  HarnessContent
generateBrowserHarness config tests =
  HarnessContent (Text.unlines sections)
  where
    sections =
      [ "// Canopy Browser Test Harness (auto-generated)",
        "",
        "// --- DOM Shim for Node.js ---",
        domShim,
        "",
        "// --- Stdout Guard (redirect console.log to stderr) ---",
        stdoutGuard,
        "",
        "// --- Compiled Tests (includes FFI externals) ---",
        unJsContent tests,
        "",
        "// --- Configuration ---",
        configSection config,
        "",
        "// --- Execute ---",
        executeSection
      ]

-- | Generate the configuration JavaScript block.
configSection :: HarnessConfig -> Text
configSection config =
  Text.unlines
    [ "const TEST_CONFIG = {",
      "  serverUrl: 'http://localhost:" <> portText <> "',",
      "  headed: " <> headedText <> ",",
      "  slowMo: " <> slowMoText,
      "};"
    ]
  where
    portText = Text.pack (show (unServerPort (config ^. harnessServerPort)))
    headedText = if config ^. harnessHeaded then "true" else "false"
    slowMoText = Text.pack (show (config ^. harnessSlowMo))

-- | Generate a minimal DOM shim so the Canopy runtime initializes in Node.js.
--
-- The compiled Canopy code sets @_VirtualDom_doc = typeof document !== 'undefined' ? document : {}@.
-- Without a global @document@, the runtime gets an empty object and crashes
-- when calling @createElement@, @createTextNode@, etc.
--
-- @since 0.19.1
domShim :: Text
domShim =
  Text.unlines
    [ "(function() {",
      "  if (typeof document !== 'undefined') return;",
      "  function makeNode() {",
      "    var n = {",
      "      appendChild: function(c) { return c; },",
      "      removeChild: function(c) { return c; },",
      "      replaceChild: function(a,b) { return a; },",
      "      insertBefore: function(a,b) { return a; },",
      "      cloneNode: function() { return makeNode(); },",
      "      childNodes: [], children: [], firstChild: null, lastChild: null,",
      "      style: {}, classList: { add:function(){}, remove:function(){}, toggle:function(){}, contains:function(){return false;} },",
      "      setAttribute: function(){}, removeAttribute: function(){}, getAttribute: function(){return '';},",
      "      addEventListener: function(){}, removeEventListener: function(){},",
      "      namespaceURI: 'http://www.w3.org/1999/xhtml',",
      "      nodeType: 1, tagName: 'DIV', nodeName: 'DIV',",
      "      textContent: '', innerHTML: '', innerText: '',",
      "      ownerDocument: null",
      "    };",
      "    n.parentNode = n;",
      "    n.parentElement = n;",
      "    return n;",
      "  }",
      "  var body = makeNode();",
      "  var doc = {",
      "    createTextNode: function(t) { var tn = makeNode(); tn.nodeType = 3; tn.textContent = t; return tn; },",
      "    createElement: function(t) { var el = makeNode(); el.tagName = t; el.nodeName = t; return el; },",
      "    createElementNS: function(ns,t) { var el = makeNode(); el.tagName = t; el.nodeName = t; el.namespaceURI = ns; return el; },",
      "    createDocumentFragment: function() { return makeNode(); },",
      "    body: body, title: '', hidden: false,",
      "    location: { href: 'http://localhost/', protocol: 'http:', host: 'localhost', pathname: '/', search: '', hash: '' },",
      "    addEventListener: function(){}, removeEventListener: function(){}",
      "  };",
      "  body.ownerDocument = doc;",
      "  globalThis.document = doc;",
      "  if (typeof window === 'undefined') {",
      "    globalThis.window = { document: doc, addEventListener: function(){}, removeEventListener: function(){}, location: doc.location, navigator: { userAgent: 'node' } };",
      "  }",
      "})();"
    ]

-- | Redirect @process.stdout.write@ to stderr.
--
-- User test code and Node.js warnings can @console.log@ to stdout,
-- corrupting the NDJSON stream. Our NDJSON output uses
-- @_fs.writeSync(1, ...)@ which bypasses @process.stdout.write@
-- entirely (direct fd syscall), so redirecting @process.stdout.write@
-- to stderr is safe and keeps the JSON stream clean.
--
-- @since 0.19.1
stdoutGuard :: Text
stdoutGuard =
  Text.unlines
    [ "(function() {",
      "  process.stdout.write = function(chunk, encoding, callback) {",
      "    return process.stderr.write(chunk, encoding, callback);",
      "  };",
      "})();"
    ]

-- | Generate the execution JavaScript block.
--
-- Locates the bundled test runner (available via @module.exports@ or
-- @window.CanopyTestRunner@), initializes each test module, and calls
-- @runAndReport@ on the @_testMain@ value. The test runner handles
-- sync\/async detection, result formatting, and exit codes.
--
-- When the @CANOPY_TEST_FILTER@ environment variable is set, only test
-- modules whose names contain the filter string (case-insensitive) are
-- initialized. This allows @canopy test --filter "Router"@ to run a
-- subset of tests.
--
-- @since 0.19.1
executeSection :: Text
executeSection =
  Text.unlines
    [ "(async function() {",
      "  var runner = (typeof module !== 'undefined' && module.exports && module.exports.runAndReport)",
      "    ? module.exports",
      "    : (typeof window !== 'undefined' && window.CanopyTestRunner)",
      "      ? window.CanopyTestRunner",
      "      : null;",
      "",
      "  if (!runner) {",
      "    console.error('Error: Test runner not available.');",
      "    process.exit(1);",
      "  }",
      "",
      "  var filterPattern = (typeof process !== 'undefined' && process.env && process.env.CANOPY_TEST_FILTER) || '';",
      "  var filterLower = filterPattern.toLowerCase();",
      "",
      "  var scope = (typeof global !== 'undefined' ? global : this);",
      "  var testScope = scope.Canopy || scope.Elm || {};",
      "  var allTestMains = [];",
      "  var skippedCount = 0;",
      "",
      "  function collectTestMains(obj, path) {",
      "    if (obj && typeof obj.init === 'function') {",
      "      var fullName = path.join('.');",
      "      if (filterLower && fullName.toLowerCase().indexOf(filterLower) === -1) {",
      "        skippedCount++;",
      "        return;",
      "      }",
      "      try {",
      "        var app = obj.init();",
      "        if (app && app._testMain) { allTestMains.push(app._testMain); }",
      "      } catch (e) {",
      "        console.error('Test module ' + fullName + ' failed to initialize: ' + e.message);",
      "        if (e.stack) console.error(e.stack);",
      "        process.exit(1);",
      "      }",
      "      return;",
      "    }",
      "    if (obj && typeof obj === 'object') {",
      "      for (var key of Object.keys(obj)) { collectTestMains(obj[key], path.concat(key)); }",
      "    }",
      "  }",
      "  collectTestMains(testScope, []);",
      "",
      "  if (skippedCount > 0) {",
      "    process.stderr.write('Skipping ' + skippedCount + ' modules not matching \"' + filterPattern + '\"\\n');",
      "  }",
      "",
      "  if (allTestMains.length === 0) {",
      "    console.error('No test modules found' + (filterPattern ? ' matching \"' + filterPattern + '\"' : '') + '.');",
      "    process.exit(1);",
      "  }",
      "",
      "  var report;",
      "  if (allTestMains.length === 1) {",
      "    report = await runner.runAndReport(allTestMains[0]);",
      "  } else {",
      "    var list = { $: '[]' };",
      "    for (var i = allTestMains.length - 1; i >= 0; i--) {",
      "      list = { $: '::', a: allTestMains[i], b: list };",
      "    }",
      "    report = await runner.runAndReport({ $: 'TestGroup', a: 'All Tests', b: list });",
      "  }",
      "",
      "  if (typeof __canopy_cov !== 'undefined') {",
      "    var _fs = require('fs');",
      "    _fs.writeSync(1, JSON.stringify({event:'coverage', data: __canopy_cov}) + '\\n');",
      "  }",
      "",
      "  var exitCode = (report && report.summary && report.summary.failed > 0) ? 1 : 0;",
      "  process.exit(exitCode);",
      "})();"
    ]

-- | Generate an HTML page for BrowserTest execution.
--
-- Produces a self-contained HTML file that:
--
-- 1. Includes the compiled Canopy test code (with all FFI externals
--    including browser-test-runner.js)
-- 2. Initializes the test module and extracts @_browserTestMain@
-- 3. Runs all tests with real browser APIs
-- 4. Emits NDJSON results via @console.log@
-- 5. Sets @window.__canopyTestsDone@ and @window.__canopyExitCode@
--
-- The Playwright launcher script navigates to this page and collects
-- the console.log output as NDJSON.
--
-- @since 0.19.1
generateBrowserTestHarness ::
  JsContent ->
  HarnessContent
generateBrowserTestHarness tests =
  HarnessContent (Text.unlines sections)
  where
    sections =
      [ "<!DOCTYPE html>",
        "<html>",
        "<head><title>Canopy Browser Tests</title></head>",
        "<body>",
        "  <div id=\"test-root\"></div>",
        "  <iframe id=\"test-target\" style=\"width:100%;height:0;border:none;position:absolute;\"></iframe>",
        "  <script>",
        unJsContent tests,
        "  </script>",
        "  <script>",
        browserTestExecuteSection,
        "  </script>",
        "</body>",
        "</html>"
      ]

-- | JavaScript execution block for the browser test HTML page.
--
-- Finds the compiled Canopy module, calls @init()@, extracts the
-- @_browserTestMain@ value, and passes it to the async browser test runner.
-- The runner is async because PlaywrightStep nodes send RPC requests
-- and await responses from the Node.js Playwright launcher.
browserTestExecuteSection :: Text
browserTestExecuteSection =
  Text.unlines
    [ "(async function() {",
      "  var scope = window.Canopy || window.Elm || {};",
      "  var allTestNodes = [];",
      "  var hasBrowserElementApps = false;",
      "  function collectModules(obj, path) {",
      "    if (!obj || typeof obj !== 'object') return;",
      "    if (typeof obj.init === 'function') {",
      "      try {",
      "        var app;",
      "        try { app = obj.init(); } catch (_e1) {",
      "          console.log(JSON.stringify({event:'result',status:'failed',name:'[debug] Init1 fail ' + path + ': ' + _e1.message,duration:0,message:(_e1.stack||'').split('\\n').slice(0,5).join(' | ')}));",
      "          var node = document.createElement('div');",
      "          node.id = 'app-' + (path || 'root').replace(/\\./g, '-');",
      "          document.body.appendChild(node);",
      "          try { app = obj.init({ node: node }); console.log(JSON.stringify({event:'result',status:'skipped',name:'[debug] Init2 OK ' + path,duration:0,message:''})); } catch (_e2) { console.log(JSON.stringify({event:'result',status:'failed',name:'[debug] Init2 fail ' + path + ': ' + _e2.message,duration:0,message:(_e2.stack||'').split('\\n').slice(0,5).join(' | ')})); return; }",
      "        }",
      "        if (app && app._browserTestMain) {",
      "          var cur = app._browserTestMain.a;",
      "          while (cur && cur.$ === '::') { allTestNodes.push(cur.a); cur = cur.b; }",
      "        } else if (app && app._testMain) {",
      "          allTestNodes.push(app._testMain);",
      "        } else {",
      "          hasBrowserElementApps = true;",
      "        }",
      "      } catch (e) {",
      "        console.log(JSON.stringify({event:'result',status:'failed',name:'Module init: '+path,duration:0,message:'Init failed: ' + e.message}));",
      "      }",
      "      return;",
      "    }",
      "    var keys = Object.keys(obj);",
      "    for (var i = 0; i < keys.length; i++) {",
      "      collectModules(obj[keys[i]], path ? path + '.' + keys[i] : keys[i]);",
      "    }",
      "  }",
      "  collectModules(scope, '');",
      "  if (hasBrowserElementApps) {",
      "    await new Promise(function(r) { setTimeout(r, 1000); });",
      "  }",
      "  if (allTestNodes.length === 0) {",
      "    console.log(JSON.stringify({event:'summary',passed:0,failed:1,skipped:0,todo:0,total:1,duration:0}));",
      "    window.__canopyTestsDone = true;",
      "    window.__canopyExitCode = 1;",
      "    return;",
      "  }",
      "  var combined = { $: '[]' };",
      "  for (var j = allTestNodes.length - 1; j >= 0; j--) {",
      "    combined = { $: '::', a: allTestNodes[j], b: combined };",
      "  }",
      "  await window.__canopyBrowserTestRunner.run({ $: 'InBrowser', a: combined });",
      "",
      "  if (typeof __canopy_cov !== 'undefined') {",
      "    console.log(JSON.stringify({event:'coverage', data: __canopy_cov}));",
      "  }",
      "})();"
    ]

-- | Generate a simple unit test harness for @Html msg@ programs.
--
-- Wraps compiled JavaScript with the DOM shim and a text-capturing
-- root node. After the Canopy runtime renders into the node, the harness
-- extracts accumulated text content and prints it.
--
-- This harness is used for legacy @main : Html msg@ programs that
-- render test results as HTML text. For @main : Test@ programs, the
-- browser harness with test-runner.js is used instead.
--
-- @since 0.19.1
generateUnitHarness :: JsContent -> HarnessContent
generateUnitHarness tests =
  HarnessContent (Text.unlines sections)
  where
    sections =
      [ "// Canopy Unit Test Harness (auto-generated)",
        "",
        "// --- DOM Shim for Node.js ---",
        domShim,
        "",
        unJsContent tests,
        "",
        unitTestBootstrap
      ]

-- | Bootstrap code for unit test harness.
--
-- Creates a text-capturing root node, initializes each Elm module
-- into it, and extracts the rendered text content.
unitTestBootstrap :: Text
unitTestBootstrap =
  Text.unlines
    [ "// Text-capturing node for rendered output",
      "function createCapturingNode() {",
      "  var texts = [];",
      "  function captureNode() {",
      "    var n = {",
      "      childNodes: [], children: [], firstChild: null, lastChild: null,",
      "      nodeType: 1, tagName: 'DIV', nodeName: 'DIV',",
      "      textContent: '', innerHTML: '', innerText: '',",
      "      style: {}, namespaceURI: 'http://www.w3.org/1999/xhtml',",
      "      classList: { add:function(){}, remove:function(){}, toggle:function(){}, contains:function(){return false;} },",
      "      setAttribute: function(){}, removeAttribute: function(){}, getAttribute: function(){return '';},",
      "      addEventListener: function(){}, removeEventListener: function(){},",
      "      appendChild: function(c) { if (c && c._texts) texts = texts.concat(c._texts); return c; },",
      "      removeChild: function(c) { return c; },",
      "      replaceChild: function(a,b) { return a; },",
      "      insertBefore: function(a,b) { if (a && a._texts) texts = texts.concat(a._texts); return a; },",
      "      cloneNode: function() { return captureNode(); },",
      "      ownerDocument: null",
      "    };",
      "    n.parentNode = n;",
      "    n.parentElement = n;",
      "    return n;",
      "  }",
      "  var node = captureNode();",
      "  node.getTexts = function() { return texts; };",
      "  return node;",
      "}",
      "",
      "// Patch document to track text in created nodes",
      "var _origCreateTextNode = document.createTextNode;",
      "document.createTextNode = function(t) {",
      "  var tn = _origCreateTextNode.call(document, t);",
      "  tn._texts = [t];",
      "  return tn;",
      "};",
      "var _origCreateElement = document.createElement;",
      "document.createElement = function(tag) {",
      "  var el = _origCreateElement.call(document, tag);",
      "  el._texts = [];",
      "  var origAppend = el.appendChild;",
      "  el.appendChild = function(c) { if (c && c._texts) el._texts = el._texts.concat(c._texts); return origAppend.call(el, c); };",
      "  return el;",
      "};",
      "",
      "// Find and run test modules",
      "var scope = (typeof global !== 'undefined' ? global : (typeof window !== 'undefined' ? window : this));",
      "var testScope = scope.Canopy || scope.Elm || {};",
      "var hasTests = false;",
      "var anyFailed = false;",
      "",
      "function walkTestModules(obj) {",
      "  if (obj && typeof obj.init === 'function') {",
      "    hasTests = true;",
      "    try {",
      "      var root = createCapturingNode();",
      "      obj.init({ node: root });",
      "      var captured = root.getTexts().join('');",
      "      if (captured.length > 0) { console.log(captured); }",
      "    } catch (e) {",
      "      console.error('Test module failed: ' + e.message);",
      "      anyFailed = true;",
      "    }",
      "    return;",
      "  }",
      "  if (obj && typeof obj === 'object') {",
      "    Object.keys(obj).forEach(function(k) { walkTestModules(obj[k]); });",
      "  }",
      "}",
      "walkTestModules(testScope);",
      "",
      "if (!hasTests) {",
      "  console.error('No test modules found.');",
      "  process.exit(1);",
      "}",
      "",
      "if (typeof __canopy_cov !== 'undefined') {",
      "  var _fs = require('fs');",
      "  _fs.writeSync(1, JSON.stringify({event:'coverage', data: __canopy_cov}) + '\\n');",
      "}",
      "",
      "process.exit(anyFailed ? 1 : 0);"
    ]
