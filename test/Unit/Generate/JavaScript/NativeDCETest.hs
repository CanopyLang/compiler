{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Generate.JavaScript.NativeDCE' (CMP-8b).
--
-- The native-DCE module gates the browser-only @window@/@document@ references
-- the baked-in @canopy/html@ + @canopy/virtual-dom@ kernel carries — references
-- that are harmless on a full engine but free identifiers on bare Hermes. These
-- tests pin the three pieces:
--
--   * the ALLOWLIST is the exact browser surface the stub provides, and
--     'isAllowed' agrees with it;
--   * the STUB preamble installs @window@/@document@ only-when-absent, exposes
--     the allowlisted members, is idempotent, and is a single statement;
--   * the GATE 'unstubbedRefs' flags a non-allowlisted access, ignores guarded
--     probes and string mentions, respects a left word boundary, and returns
--     empty for an all-allowlisted bundle.
--
-- @since 0.20.10
module Unit.Generate.JavaScript.NativeDCETest (tests) where

import Data.List (isInfixOf)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Generate.JavaScript.NativeDCE as DCE
import Test.Tasty
import Test.Tasty.HUnit

render :: BB.Builder -> String
render = LChar8.unpack . BB.toLazyByteString

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.NativeDCE (CMP-8b)"
    [ allowlistTests
    , stubTests
    , gateTests
    ]

-- ALLOWLIST -----------------------------------------------------------------

allowlistTests :: TestTree
allowlistTests =
  testGroup
    "browser-global allowlist"
    [ testCase "window allows exactly add/removeEventListener" $
        lookupMembers "window" @?= Just ["addEventListener", "removeEventListener"]
    , testCase "document allows body/location + the listener/create members the stub provides" $
        lookupMembers "document"
          @?= Just ["body", "location", "addEventListener", "removeEventListener", "createElement", "createTextNode"]
    , testCase "flattened allowlist matches isAllowed" $ do
        assertBool "window.addEventListener allowed" (DCE.isAllowed "window" "addEventListener")
        assertBool "document.body allowed" (DCE.isAllowed "document" "body")
        assertBool "window.location NOT allowed" (not (DCE.isAllowed "window" "location"))
        assertBool "document.cookie NOT allowed" (not (DCE.isAllowed "document" "cookie"))
        assertBool "navigator (not a tracked global) NOT allowed" (not (DCE.isAllowed "navigator" "userAgent"))
    ]
  where
    lookupMembers g =
      DCE.bgMembers <$> lookupBy ((== g) . DCE.bgName) DCE.allowedBrowserGlobals
    lookupBy p = foldr (\x acc -> if p x then Just x else acc) Nothing

-- STUB ----------------------------------------------------------------------

stubTests :: TestTree
stubTests =
  testGroup
    "browser-global stub preamble"
    [ testCase "installs the dom-stub marker" $
        assertBool "expected the __canopy_dom_stub marker assignment"
          (("g." ++ DCE.stubMarkerName ++ " = marker") `isInfixOf` stub)
    , testCase "is idempotent (early-returns if already installed)" $
        assertBool "expected the marker guard"
          (("if (g." ++ DCE.stubMarkerName ++ ")") `isInfixOf` stub)
    , testCase "stubs window ONLY when absent" $
        assertBool "expected a typeof-undefined guard around the window stub"
          ("if (typeof g.window === 'undefined')" `isInfixOf` stub)
    , testCase "stubs document ONLY when absent" $
        assertBool "expected a typeof-undefined guard around the document stub"
          ("if (typeof g.document === 'undefined')" `isInfixOf` stub)
    , testCase "the window stub exposes addEventListener/removeEventListener" $ do
        assertBool "addEventListener no-op" ("addEventListener: function () {}" `isInfixOf` stub)
        assertBool "removeEventListener no-op" ("removeEventListener: function () {}" `isInfixOf` stub)
    , testCase "the document stub exposes body" $
        assertBool "expected document.body stub" ("body: body" `isInfixOf` stub)
    , testCase "is a single spliceable statement (one trailing IIFE close)" $
        assertBool "expected the IIFE to close with }())"
          ("}());" `isInfixOf` stub)
    , testCase "preamble builder equals the source" $
        render DCE.browserGlobalStub @?= DCE.browserStubSource
    ]
  where
    stub = DCE.browserStubSource

-- GATE ----------------------------------------------------------------------

gateTests :: TestTree
gateTests =
  testGroup
    "unstubbedRefs static gate"
    [ testCase "flags a non-allowlisted window member" $
        DCE.unstubbedRefs "var x = window.location.href;" @?= [("window", "location")]
    , testCase "flags a non-allowlisted document member" $
        DCE.unstubbedRefs "document.cookie = 'a=b';" @?= [("document", "cookie")]
    , testCase "passes an allowlisted access" $
        DCE.unstubbedRefs "window.addEventListener('x', f); document.body.appendChild(n);"
          @?= []
    , testCase "ignores a guarded probe (no member access)" $
        DCE.unstubbedRefs "var w = (typeof window !== 'undefined') ? window : this;"
          @?= []
    , testCase "ignores a mention inside a string/error message" $
        DCE.unstubbedRefs "throw new Error('do Elm.Main.init({ node: document.getElementById(\"n\") })');"
          @?= []
    , testCase "respects a left word boundary (mywindow.foo is not window.foo)" $
        DCE.unstubbedRefs "mywindow.foo(); _document.bar();" @?= []
    , testCase "de-duplicates repeated unstubbed refs" $
        DCE.unstubbedRefs "window.location; window.location; window.location;"
          @?= [("window", "location")]
    , testCase "reports multiple distinct unstubbed refs, sorted" $
        DCE.unstubbedRefs "document.cookie; window.location;"
          @?= [("document", "cookie"), ("window", "location")]
    , testCase "the real allowlisted surface passes (the kernel's own refs)" $
        -- The exact unguarded accesses the assembled native bundle carries.
        DCE.unstubbedRefs
          (unlines
             [ "var root = _VirtualDom_delegationRoot || document.body;"
             , "window.addEventListener('t', null, opts);"
             , "window.removeEventListener('t', null);"
             ])
          @?= []
    ]
