# Browser Testing Implementation Plan

## Executive Summary

The Browser testing modules (`Browser.Test`, `Browser.Page`, etc.) exist with comprehensive Playwright FFI bindings, but **the test execution infrastructure cannot run async tests**. This document outlines the production-ready implementation path.

---

## Current State Analysis

### What Exists (Working)

| Component | Location | Status |
|-----------|----------|--------|
| Playwright FFI bindings | `core-packages/test/external/playwright.js` | Complete (1200+ lines) |
| Browser.Test DSL | `core-packages/test/src/Browser/Test.can` | Complete API |
| Browser.Page operations | `core-packages/test/src/Browser/Page.can` | Complete API |
| Browser.Element interactions | `core-packages/test/src/Browser/Element.can` | Complete API |
| Browser.Expect assertions | `core-packages/test/src/Browser/Expect.can` | Complete API |
| Accessibility module | `core-packages/test/src/Accessibility.can` | Complete API |
| Module exposure | `core-packages/test/canopy.json` | Updated |

### What's Broken

| Component | Issue | Impact |
|-----------|-------|--------|
| Test Runner | Synchronous only (`test.b()`) | Cannot execute browser tests |
| `withBrowser` | `launchSync` returns null handles | No actual browser launch |
| Task Executor | Doesn't exist | `Task BrowserError a` types can't run |
| CLI integration | No async test detection | Can't run browser tests from CLI |

---

## Architecture Requirements

### 1. Async Test Execution Model

Browser tests return `Task BrowserError Browser` which must be:
1. Unwrapped from Canopy's Task representation
2. Executed as JavaScript Promises
3. Awaited to completion
4. Results mapped back to `Expectation`

```
Canopy Test ──> Task BrowserError a ──> Promise<a> ──> await ──> Expectation
```

### 2. Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         canopy test                              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Test Detection Layer                          │
│  - Detect BrowserTest vs UnitTest                               │
│  - Route to appropriate executor                                 │
└─────────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                                 ▼
┌──────────────────────┐            ┌──────────────────────────────┐
│  Sync Test Runner    │            │   Async Browser Test Runner   │
│  (existing)          │            │   (new)                       │
└──────────────────────┘            └──────────────────────────────┘
                                                │
                                                ▼
                                    ┌──────────────────────────────┐
                                    │     Task Executor Engine      │
                                    │  - Unwrap Task constructors   │
                                    │  - Execute as Promises        │
                                    │  - Chain with andThen/map     │
                                    └──────────────────────────────┘
                                                │
                                                ▼
                                    ┌──────────────────────────────┐
                                    │      Playwright Driver        │
                                    │  - Browser lifecycle          │
                                    │  - Page operations            │
                                    │  - Element interactions       │
                                    └──────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Task Executor Engine

**Goal**: Create JavaScript runtime for executing Canopy `Task` types

**File**: `core-packages/test/external/task-executor.js`

**Responsibilities**:
1. Recognize Task constructors (`Task`, `Succeed`, `Fail`, `AndThen`, `Map`)
2. Convert to JavaScript Promise chain
3. Handle error propagation
4. Support browser-specific tasks

**Key Functions**:
```javascript
/**
 * Execute a Canopy Task and return a Promise
 * @canopy-type Task err a -> Promise a
 */
async function executeTask(task) {
    switch (task.$) {
        case 'Succeed':
            return task.a;

        case 'Fail':
            throw task.a;

        case 'AndThen':
            // task.a = callback (a -> Task err b)
            // task.b = inner task (Task err a)
            const result = await executeTask(task.b);
            return await executeTask(task.a(result));

        case 'Map':
            // task.a = function (a -> b)
            // task.b = inner task (Task err a)
            const value = await executeTask(task.b);
            return task.a(value);

        case 'OnError':
            // task.a = error handler (err -> Task err2 a)
            // task.b = inner task (Task err a)
            try {
                return await executeTask(task.b);
            } catch (e) {
                return await executeTask(task.a(e));
            }

        // FFI task (actual async operation)
        case 'FFI':
            return await task.a();  // Execute the wrapped async function

        default:
            throw new Error(`Unknown Task constructor: ${task.$}`);
    }
}
```

### Phase 2: Async Test Runner

**Goal**: Extend test runner to handle async/browser tests

**Files**:
- `core-packages/test/external/test-runner.js` (modify)
- `core-packages/test/external/browser-test-runner.js` (new)

**Changes to test-runner.js**:
```javascript
async function runTestAsync(test, path) {
    switch (test.$) {
        case 'UnitTest':
            // Existing sync logic
            break;

        case 'BrowserTest':
            // NEW: Handle browser tests
            return await runBrowserTest(test, path);

        case 'AsyncTest':
            // NEW: Handle Task-based tests
            return await runAsyncTest(test, path);
    }
}

async function runBrowserTest(test, path) {
    const { config, steps, name } = unwrapBrowserTest(test);
    const browser = await playwright.launch(config);

    try {
        for (const step of steps) {
            await executeTask(step(browser));
        }
        return { $: 'Passed', a: name, b: duration };
    } catch (e) {
        return { $: 'Failed', a: name, b: e.message, c: duration };
    } finally {
        await playwright.close(browser);
    }
}
```

### Phase 3: Canopy Test Type Extensions

**Goal**: Add async test types to Test module

**File**: `core-packages/test/src/Test.can`

**New Types**:
```canopy
type Test
    = UnitTest String (() -> Expectation)
    | TestGroup String (List Test)
    | Skip Test
    | Todo String
    | BrowserTest String Config (List Step)  -- NEW
    | AsyncTest String (Task TestError Expectation)  -- NEW
```

### Phase 4: Browser.Test Integration

**Goal**: Make `runBrowserTests` produce actual executable tests

**File**: `core-packages/test/src/Browser/Test.can`

**Changes**:
```canopy
{-| Convert BrowserTest to executable Test.

This creates an AsyncTest that the runner can execute.
-}
toTest : BrowserTest -> Test
toTest browserTestDef =
    case browserTestDef of
        BrowserTest name config steps ->
            AsyncTest name (executeBrowserSteps config steps)

        BrowserTestGroup name tests ->
            TestGroup name (List.map toTest tests)


{-| Execute browser steps as a Task.
-}
executeBrowserSteps : Config -> List Step -> Task TestError Expectation
executeBrowserSteps config steps =
    Browser.launch config
        |> Task.andThen (runAllSteps steps)
        |> Task.andThen (\_ -> Task.succeed Expect.pass)
        |> Task.onError (\err -> Task.succeed (Expect.fail (errorToString err)))
        |> Task.andThen (\result ->
            Browser.close browser
                |> Task.map (\_ -> result)
        )
```

### Phase 5: CLI Integration

**Goal**: `canopy test` command handles browser tests

**Files**:
- `terminal/src/Test.hs` (modify)
- `terminal/impl/test-runner.js` (new/modify)

**Responsibilities**:
1. Detect if test suite contains `BrowserTest` or `AsyncTest`
2. If yes, use Node.js async runner instead of sync runner
3. Ensure Playwright is available (helpful error if not)
4. Support `--headed` flag for debugging
5. Support `--browser chromium|firefox|webkit` flag

**CLI Flags**:
```bash
canopy test [files...]
    --headed          # Show browser window
    --browser TYPE    # chromium (default), firefox, webkit
    --slowmo MS       # Delay between actions
    --timeout MS      # Test timeout (default 30000)
    --video           # Record video of tests
```

### Phase 6: Fix withBrowser

**Goal**: Make `withBrowser` actually work

**File**: `core-packages/test/external/playwright.js`

**Replace** lines 1034-1100 with:
```javascript
/**
 * Execute a browser test with proper async lifecycle.
 *
 * @canopy-type BrowserConfig -> (Browser -> Task BrowserError Expectation) -> Task TestError Expectation
 * @name withBrowserAsync
 */
async function withBrowserAsync(config, testFn) {
    let browser = null;

    try {
        browser = await launch(config);
        const task = testFn(browser);
        const expectation = await executeTask(task);
        return expectation;
    } catch (e) {
        return {
            $: 'Fail',
            a: { $: 'Custom', a: 'Browser test error: ' + e.message }
        };
    } finally {
        if (browser) {
            await close(browser);
        }
    }
}
```

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `core-packages/test/external/task-executor.js` | CREATE | Task execution engine |
| `core-packages/test/external/test-runner.js` | MODIFY | Add async test support |
| `core-packages/test/external/browser-test-runner.js` | CREATE | Browser-specific runner |
| `core-packages/test/external/playwright.js` | MODIFY | Fix withBrowser, add withBrowserAsync |
| `core-packages/test/src/Test.can` | MODIFY | Add AsyncTest, BrowserTest types |
| `core-packages/test/src/Browser/Test.can` | MODIFY | Fix runBrowserTests to use AsyncTest |
| `terminal/src/Test.hs` | MODIFY | CLI async test detection |

---

## Testing Strategy

### Unit Tests for Task Executor
```javascript
// Test succeed
const succeed = { $: 'Succeed', a: 42 };
assert.equal(await executeTask(succeed), 42);

// Test fail
const fail = { $: 'Fail', a: 'error' };
await assert.rejects(executeTask(fail));

// Test andThen
const chain = {
    $: 'AndThen',
    a: (x) => ({ $: 'Succeed', a: x * 2 }),
    b: { $: 'Succeed', a: 21 }
};
assert.equal(await executeTask(chain), 42);
```

### Integration Tests
```canopy
suite : Test
suite =
    Browser.Test.runBrowserTests
        [ browserTest "visits page"
            [ visit "http://localhost:8000"
            , seeText "Hello"
            ]
        ]
```

### End-to-End Test
```bash
cd examples/audio-ffi
canopy test test/PlaywrightTest.can --headed
```

---

## Dependencies

### Required Node.js Packages
```json
{
  "dependencies": {
    "playwright": "^1.40.0"
  }
}
```

### Playwright Browser Installation
```bash
npx playwright install chromium
```

---

## Success Criteria

1. **`canopy test` runs browser tests** without manual HTML setup
2. **Tests execute in real Chromium** via Playwright
3. **Async operations complete** (click, wait, navigate)
4. **Results report correctly** (pass/fail/error messages)
5. **Cleanup happens** (browser closes even on failure)
6. **Debug mode works** (`--headed` shows browser)
7. **CI integration** (headless by default, JUnit output)

---

## Timeline Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: Task Executor | 2-3 days | None |
| Phase 2: Async Test Runner | 2-3 days | Phase 1 |
| Phase 3: Test Types | 1-2 days | Phase 2 |
| Phase 4: Browser.Test | 1-2 days | Phase 3 |
| Phase 5: CLI Integration | 2-3 days | Phase 4 |
| Phase 6: Fix withBrowser | 1 day | Phase 1 |
| Testing & Polish | 2-3 days | All |

**Total: 11-17 days**

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Task representation differs | High | Audit actual Task constructors in compiler output |
| Playwright API changes | Medium | Pin version, add compatibility layer |
| CI doesn't have browsers | Medium | Document `npx playwright install` requirement |
| Memory leaks on failure | Medium | Ensure finally blocks in all paths |

---

## Next Steps

1. **Audit Task implementation**: Examine generated JS for actual Task constructor names
2. **Prototype task-executor.js**: Get basic Task execution working
3. **Add AsyncTest to Test.can**: Extend the test type
4. **Integrate with test runner**: Make `runTests` async-aware
5. **CLI changes**: Add browser test detection to `canopy test`
