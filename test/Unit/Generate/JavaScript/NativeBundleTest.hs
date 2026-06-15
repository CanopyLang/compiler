{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Generate.JavaScript.NativeBundle' (CMP-5).
--
-- The native bundle emitter folds the host-facing trailer (the
-- @__canopy_boot@ entry hook, ABI fallbacks, and the in-bundle source map) onto
-- the IIFE the web reuse path compiles — replacing the brittle out-of-tree
-- string-splice the native build tool used to do. These tests pin the
-- assembler's contract at the unit level:
--
--   * the boot hook + ABI fallbacks are present and emitted UNCONDITIONALLY
--     (dev and @--optimize@), so the host can always boot;
--   * the source map is inlined as @globalThis.__canopy_sourcemap@ ONLY when a
--     map exists (dev), and the inlined JSON is byte-identical to the standalone
--     @.js.map@ the assembler hands back — so a host symbolicates identically
--     from either copy;
--   * the trailer is appended strictly AFTER the IIFE, so the map needs no
--     re-shift: the assembled JS begins with the verbatim IIFE bytes (the
--     alignment property the hand-splice could not guarantee); and
--   * the JS-string escaping of the inlined map round-trips through
--     @JSON.parse@ (no raw newline/quote breaks the single assignment).
--
-- @since 0.20.9
module Unit.Generate.JavaScript.NativeBundleTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import Data.List (isInfixOf, isPrefixOf)
import qualified Generate.JavaScript.NativeBundle as NativeBundle
import qualified Generate.JavaScript.SourceMap as SourceMap
import Test.Tasty
import Test.Tasty.HUnit

-- | Render a 'BB.Builder' to a 'String' for substring/prefix assertions.
render :: BB.Builder -> String
render = LChar8.unpack . BB.toLazyByteString

-- | A small, representative source map with two mappings on different generated
-- lines and two source files — enough that the encoded @mappings@ string is
-- non-trivial and its JSON contains characters that must survive JS-string
-- escaping (quotes around source names).
sampleMap :: SourceMap.SourceMap
sampleMap =
  (SourceMap.empty "canopy.bundle.js")
    { SourceMap._smSources = ["Main.can", "Html.can"]
    , SourceMap._smSourcesContent = ["", ""]
    , SourceMap._smMappings =
        -- stored reverse-ordered (the accumulation convention), serialized in order
        [ SourceMap.Mapping 5 0 1 2 0 Nothing
        , SourceMap.Mapping 0 4 0 0 0 Nothing
        ]
    }

-- | A stand-in for the compiled IIFE bundle. We do not need a real compile here
-- — the assembler's job is purely to PREPEND nothing and APPEND the trailer, so
-- any recognizable byte string exercises the contract.
sampleIife :: BB.Builder
sampleIife =
  BB.stringUtf8 "(function(scope){'use strict';\nvar $x=1;\n}(typeof window !== 'undefined' ? window : this));"

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.NativeBundle (CMP-5)"
    [ bootHookTests
    , inlineMapTests
    , assembleDevTests
    , assembleProdTests
    , archiveMapTests
    , escapeTests
    ]

-- BOOT HOOK -----------------------------------------------------------------

bootHookTests :: TestTree
bootHookTests =
  testGroup
    "boot hook + ABI fallbacks"
    [ testCase "installs __canopy_boot" $
        assertBool "expected g.__canopy_boot assignment"
          ("g.__canopy_boot = function (rootTag, flags)" `isInfixOf` render NativeBundle.bootHook)
    , testCase "resolves the program via the Elm global the IIFE exports" $
        assertBool "expected g.Elm lookup"
          ("g.Elm" `isInfixOf` render NativeBundle.bootHook)
    , testCase "carries the scope[Elm] ABI fallback" $
        -- The IIFE assigns scope['Elm'] where scope is window/this; on a bare
        -- Hermes/JSI global the hook must tolerate the scoped-global shape too.
        assertBool "expected g.scope.Elm fallback"
          ("(g.scope && g.scope.Elm)" `isInfixOf` render NativeBundle.bootHook)
    , testCase "boots through Main.init({ node, flags })" $
        assertBool "expected elm.Main.init mount call"
          ("elm.Main.init({ node: rootTag, flags: flags })" `isInfixOf` render NativeBundle.bootHook)
    , testCase "closes over globalThis with a this fallback" $
        assertBool "expected globalThis-or-this scope tail"
          ("typeof globalThis !== 'undefined' ? globalThis : this" `isInfixOf` render NativeBundle.bootHook)
    ]

-- INLINE MAP ----------------------------------------------------------------

inlineMapTests :: TestTree
inlineMapTests =
  testGroup
    "inline source map assignment"
    [ testCase "assigns globalThis.__canopy_sourcemap" $
        assertBool "expected the in-bundle map assignment"
          ("globalThis.__canopy_sourcemap = \"" `isInfixOf` render (NativeBundle.inlineSourceMap sampleMap))
    , testCase "embeds the map JSON as an escaped string (version field present)" $
        -- The map JSON's own quotes are escaped to \" inside the JS string.
        assertBool "expected escaped \\\"version\\\":3 inside the assignment"
          ("\\\"version\\\":3" `isInfixOf` render (NativeBundle.inlineSourceMap sampleMap))
    , testCase "is a single statement (one trailing newline, no bare newline inside)" $
        let s = render (NativeBundle.inlineSourceMap sampleMap)
         in do
              assertBool "should end with \";\\n\"" (";\n" `isSuffixOf'` s)
              -- exactly one newline (the terminator); the escaped map carries no raw newline
              length (filter (== '\n') s) @?= 1
    , testCase "sourceMappingURL points at the sibling .map of the bundle name" $
        render (NativeBundle.sourceMappingRef "canopy.bundle.js")
          @?= "//# sourceMappingURL=canopy.bundle.js.map\n"
    , testCase "sourceMappingURL uses only the file name (strips any directory)" $
        render (NativeBundle.sourceMappingRef "build/canopy.bundle.js")
          @?= "//# sourceMappingURL=canopy.bundle.js.map\n"
    ]

-- ASSEMBLE (DEV — with map) -------------------------------------------------

assembleDevTests :: TestTree
assembleDevTests =
  testGroup
    "assemble (dev — map present)"
    [ testCase "assembled JS begins with the verbatim IIFE (no prepend, map stays aligned)" $
        let (js, _) = NativeBundle.assemble "canopy.bundle.js" sampleIife (Just sampleMap)
         in assertBool "assembled JS must start with the exact IIFE bytes"
              (render sampleIife `isPrefixOf` render js)
    , testCase "assembled JS contains the boot hook AFTER the IIFE" $
        let (js, _) = NativeBundle.assemble "canopy.bundle.js" sampleIife (Just sampleMap)
            out = render js
            iifeEnd = length (render sampleIife)
         in assertBool "boot hook must come after the IIFE bytes"
              ("g.__canopy_boot" `isInfixOf` drop iifeEnd out)
    , testCase "assembled JS inlines the map and a sourceMappingURL" $
        let (js, _) = NativeBundle.assemble "canopy.bundle.js" sampleIife (Just sampleMap)
            out = render js
         in do
              assertBool "expected inline __canopy_sourcemap"
                ("globalThis.__canopy_sourcemap" `isInfixOf` out)
              assertBool "expected sourceMappingURL comment"
                ("//# sourceMappingURL=canopy.bundle.js.map" `isInfixOf` out)
    , testCase "standalone .map builder is returned and equals the serialized map" $
        let (_, maybeMap) = NativeBundle.assemble "canopy.bundle.js" sampleIife (Just sampleMap)
         in case maybeMap of
              Nothing -> assertFailure "expected a standalone map builder in dev"
              Just mb ->
                render mb @?= render (SourceMap.toBuilder sampleMap)
    , testCase "the INLINED map JSON equals the standalone .map JSON (byte-identical)" $
        -- The host can symbolicate from the in-bundle copy (bare Hermes) or the
        -- sibling file; both must carry the SAME JSON.
        case NativeBundle.assemble "canopy.bundle.js" sampleIife (Just sampleMap) of
          (_, Nothing) -> assertFailure "expected a standalone map builder in dev"
          (js, Just mb) ->
            let siblingJson = render mb
                inlinedJson = extractInlinedMapJson (render js)
             in inlinedJson @?= Just siblingJson
    ]

-- ASSEMBLE (PROD — no map) --------------------------------------------------

assembleProdTests :: TestTree
assembleProdTests =
  testGroup
    "assemble (prod — no map)"
    [ testCase "still installs the boot hook (host always boots)" $
        let (js, _) = NativeBundle.assemble "canopy.bundle.js" sampleIife Nothing
         in assertBool "expected boot hook even without a map"
              ("g.__canopy_boot" `isInfixOf` render js)
    , testCase "omits the inline map and sourceMappingURL" $
        let (js, _) = NativeBundle.assemble "canopy.bundle.js" sampleIife Nothing
            out = render js
         in do
              assertBool "no __canopy_sourcemap without a map"
                (not ("__canopy_sourcemap" `isInfixOf` out))
              assertBool "no sourceMappingURL without a map"
                (not ("sourceMappingURL" `isInfixOf` out))
    , testCase "returns no standalone map builder" $
        let (_, maybeMap) = NativeBundle.assemble "canopy.bundle.js" sampleIife Nothing
         in assertBool "expected Nothing for the map builder under --optimize"
              (maybeNull maybeMap)
    ]

-- ASSEMBLE (PROD — map archived out-of-band, CMP-8b) ------------------------

-- | CMP-8b's 'NativeBundle.ArchiveMap' disposition: when a map IS present (the
-- native prod path now produces one), an optimized build archives it to the
-- sibling @.js.map@ and emits the @sourceMappingURL@ comment, but does NOT
-- inline the JSON into the bundle bytes (the size budget). This is the contrast
-- with 'InlineMap' (dev), which inlines AND archives.
archiveMapTests :: TestTree
archiveMapTests =
  testGroup
    "assemble (prod — ArchiveMap, CMP-8b)"
    [ testCase "dispositionFor True is ArchiveMap; False is InlineMap" $ do
        NativeBundle.dispositionFor True @?= NativeBundle.ArchiveMap
        NativeBundle.dispositionFor False @?= NativeBundle.InlineMap
    , testCase "ArchiveMap still installs the boot hook" $
        let (js, _) =
              NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife (Just sampleMap)
         in assertBool "expected boot hook under ArchiveMap"
              ("g.__canopy_boot" `isInfixOf` render js)
    , testCase "ArchiveMap does NOT inline the map (size budget)" $
        let (js, _) =
              NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife (Just sampleMap)
            out = render js
         in assertBool "the map JSON must not be inlined under ArchiveMap"
              (not ("__canopy_sourcemap" `isInfixOf` out))
    , testCase "ArchiveMap STILL emits the sourceMappingURL comment" $
        let (js, _) =
              NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife (Just sampleMap)
         in assertBool "expected sourceMappingURL even when archived"
              ("//# sourceMappingURL=canopy.bundle.js.map" `isInfixOf` render js)
    , testCase "ArchiveMap STILL returns the standalone .js.map builder (written to disk)" $
        case NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife (Just sampleMap) of
          (_, Nothing) -> assertFailure "ArchiveMap must still hand back the standalone map to write"
          (_, Just mb) -> render mb @?= render (SourceMap.toBuilder sampleMap)
    , testCase "ArchiveMap with no map at all emits no trailer (boot hook only)" $
        let (js, mb) =
              NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife Nothing
            out = render js
         in do
              assertBool "no map -> no sourceMappingURL" (not ("sourceMappingURL" `isInfixOf` out))
              assertBool "no map -> no inline assignment" (not ("__canopy_sourcemap" `isInfixOf` out))
              assertBool "no map -> no standalone builder" (maybeNull mb)
    , testCase "the assembled JS still begins with the verbatim IIFE under ArchiveMap" $
        let (js, _) =
              NativeBundle.assembleWith NativeBundle.ArchiveMap "canopy.bundle.js" sampleIife (Just sampleMap)
         in assertBool "ArchiveMap must not prepend anything to the IIFE"
              (render sampleIife `isPrefixOf` render js)
    ]

-- ESCAPING ------------------------------------------------------------------

escapeTests :: TestTree
escapeTests =
  testGroup
    "JS-string escaping"
    [ testCase "escapes backslash, quote, newline, CR, tab" $
        render (NativeBundle.escapeJsString (LChar8.pack "a\\b\"c\nd\re\tf"))
          @?= "a\\\\b\\\"c\\nd\\re\\tf"
    , testCase "leaves plain ASCII untouched" $
        render (NativeBundle.escapeJsString (LChar8.pack "{\\u0041}"))
          -- the literal backslash in the input is escaped; letters/braces pass through
          @?= "{\\\\u0041}"
    , testCase "escaped map round-trips: no raw newline survives in the assignment" $
        -- A map whose JSON would contain a control char must not break the
        -- single-line assignment; the escaper turns every newline into \\n.
        let asgn = render (NativeBundle.inlineSourceMap sampleMap)
         in assertBool "the assignment line itself carries exactly one newline (its terminator)"
              (length (filter (== '\n') asgn) == 1)
    ]

-- HELPERS -------------------------------------------------------------------

-- | Whether a 'Maybe' is 'Nothing' (avoids importing Data.Maybe just for this).
maybeNull :: Maybe a -> Bool
maybeNull Nothing = True
maybeNull (Just _) = False

-- | Suffix check on 'String'.
isSuffixOf' :: String -> String -> Bool
isSuffixOf' suf s = reverse suf `isPrefixOf` reverse s

-- | Pull the inlined map JSON back out of an assembled bundle by un-escaping the
-- @globalThis.__canopy_sourcemap = "..."@ string literal, so we can compare it
-- to the standalone serialized map. Mirrors what @JSON.parse@ does on the host.
extractInlinedMapJson :: String -> Maybe String
extractInlinedMapJson out =
  case dropToAfter marker out of
    Nothing -> Nothing
    Just rest -> Just (unescapeJsString rest)
  where
    marker = "globalThis.__canopy_sourcemap = \""

-- | Drop everything up to and including the marker, returning the remainder.
dropToAfter :: String -> String -> Maybe String
dropToAfter _ [] = Nothing
dropToAfter marker s@(_ : rest)
  | marker `isPrefixOf` s = Just (drop (length marker) s)
  | otherwise = dropToAfter marker rest

-- | Decode a JS double-quoted string body up to its closing unescaped quote,
-- reversing 'NativeBundle.escapeJsString'.
unescapeJsString :: String -> String
unescapeJsString [] = []
unescapeJsString ('"' : _) = [] -- closing quote: end of the literal
unescapeJsString ('\\' : c : rest) =
  let ch = case c of
        'n' -> '\n'
        'r' -> '\r'
        't' -> '\t'
        '"' -> '"'
        '\\' -> '\\'
        other -> other
   in ch : unescapeJsString rest
unescapeJsString (c : rest) = c : unescapeJsString rest
