{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

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
-- For browser\/async tests, generates a Node.js script that bundles:
--
-- * @task-executor.js@ — Task monad execution engine
-- * @test-runner.js@ — Async-aware test runner with Playwright support
-- * Compiled test code
-- * Configuration (server URL, browser options)
--
-- @since 0.19.1
module Test.Harness
  ( -- * Types
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

import Test.External (JsContent (..))
import Test.Server (ServerPort (..))

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

-- | Generate a browser test harness from components.
--
-- Bundles the task executor, playwright bindings, test runner,
-- compiled tests, and configuration into a single self-contained
-- Node.js script. The load order matters:
--
-- 1. DOM shim (provides @document@\/@window@ for Elm runtime)
-- 2. Task executor (sets @window.CanopyTaskExecutor@)
-- 3. Compiled test code (includes FFI JS from package artifacts)
-- 4. Playwright bindings (overrides FFI functions with URL resolution)
-- 5. Test runner (picks up executor and playwright from globals)
-- 6. Configuration
-- 7. Execute section (calls @runAndReport@)
--
-- @since 0.19.1
generateBrowserHarness ::
  HarnessConfig ->
  JsContent ->
  JsContent ->
  JsContent ->
  JsContent ->
  HarnessContent
generateBrowserHarness config runner executor playwright tests =
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
        "// --- Task Executor ---",
        unJsContent executor,
        "",
        "// --- Compiled Tests ---",
        unJsContent tests,
        "",
        "// --- Playwright Bindings (after compiled tests to override FFI) ---",
        unJsContent playwright,
        "",
        "// --- Test Runner ---",
        unJsContent runner,
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

-- | Generate a minimal DOM shim so the Elm runtime initializes in Node.js.
--
-- The compiled Elm code sets @_VirtualDom_doc = typeof document !== 'undefined' ? document : {}@.
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
      "  var scope = (typeof global !== 'undefined' ? global : this);",
      "  var testScope = scope.Canopy || scope.Elm || {};",
      "",
      "  for (var moduleName of Object.keys(testScope)) {",
      "    var mod = testScope[moduleName];",
      "    if (mod && typeof mod.init === 'function') {",
      "      try {",
      "        var app = mod.init();",
      "        if (app && app._testMain) {",
      "          await runner.runAndReport(app._testMain);",
      "          return;",
      "        }",
      "      } catch (e) {",
      "        console.error('Test module ' + moduleName + ' failed to initialize: ' + e.message);",
      "        if (e.stack) console.error(e.stack);",
      "        process.exit(1);",
      "      }",
      "    }",
      "  }",
      "",
      "  console.error('No test modules found.');",
      "  process.exit(1);",
      "})();"
    ]

-- | Generate an HTML page for BrowserTest execution.
--
-- Produces a self-contained HTML file that:
--
-- 1. Includes the compiled Canopy test code (with FFI externals)
-- 2. Includes the browser-side test runner
-- 3. Initializes the test module and extracts @_browserTestMain@
-- 4. Runs all tests with real browser APIs
-- 5. Emits NDJSON results via @console.log@
-- 6. Sets @window.__canopyTestsDone@ and @window.__canopyExitCode@
--
-- The Playwright launcher script navigates to this page and collects
-- the console.log output as NDJSON.
--
-- @since 0.19.1
generateBrowserTestHarness ::
  JsContent ->
  JsContent ->
  HarnessContent
generateBrowserTestHarness tests browserRunner =
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
        unJsContent browserRunner,
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
      "  var moduleNames = Object.keys(scope);",
      "  for (var i = 0; i < moduleNames.length; i++) {",
      "    var mod = scope[moduleNames[i]];",
      "    if (mod && typeof mod.init === 'function') {",
      "      try {",
      "        var app = mod.init();",
      "        if (app && app._browserTestMain) {",
      "          await window.__canopyBrowserTestRunner.run(app._browserTestMain);",
      "          return;",
      "        }",
      "      } catch (e) {",
      "        console.log(JSON.stringify({event:'result',status:'failed',name:'Module init',duration:0,message:'Init failed: ' + e.message}));",
      "      }",
      "    }",
      "  }",
      "  console.log(JSON.stringify({event:'summary',passed:0,failed:1,skipped:0,todo:0,total:1,duration:0}));",
      "  window.__canopyTestsDone = true;",
      "  window.__canopyExitCode = 1;",
      "})();"
    ]

-- | Generate a simple unit test harness for @Html msg@ programs.
--
-- Wraps compiled JavaScript with the DOM shim and a text-capturing
-- root node. After the Elm runtime renders into the node, the harness
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
      "Object.keys(testScope).forEach(function(moduleName) {",
      "  var mod = testScope[moduleName];",
      "  if (mod && typeof mod.init === 'function') {",
      "    hasTests = true;",
      "    try {",
      "      var root = createCapturingNode();",
      "      mod.init({ node: root });",
      "      var captured = root.getTexts().join('');",
      "      if (captured.length > 0) {",
      "        console.log(captured);",
      "      }",
      "    } catch (e) {",
      "      console.error('Test module ' + moduleName + ' failed: ' + e.message);",
      "      anyFailed = true;",
      "    }",
      "  }",
      "});",
      "",
      "if (!hasTests) {",
      "  console.error('No test modules found.');",
      "  process.exit(1);",
      "}",
      "",
      "process.exit(anyFailed ? 1 : 0);"
    ]
