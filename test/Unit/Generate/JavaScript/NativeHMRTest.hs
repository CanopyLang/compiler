{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Generate.JavaScript.NativeHMR' (CMP-9).
--
-- The native Fast Refresh emitter appends, INSIDE the IIFE and dev-only, the
-- @__canopy_hmr@ runtime, the @__canopy_model_typehash@ global the DEV-8 host
-- seam reads, and the per-module @__canopy_hmr.register(...)@ boundary. These
-- tests pin that contract at the unit level:
--
--   * the model-typehash global is emitted as @globalThis.__canopy_model_typehash@
--     with the SAME hex 'ESM.HMR' uses (so the two HMR paths agree), and is the
--     load-bearing DEV-8 emission the host's @_Native_modelTypehash()@ reads;
--   * @register@ carries @(moduleId, members, modelHash)@ in that order, with the
--     moduleId the module name and the modelHash byte-equal to the global's hex;
--   * the @__canopy_hmr@ runtime is idempotent (re-eval-safe) and exposes the
--     @register@\/@accept@ model-compat gate the plan names;
--   * production (@--optimize@) emits NOTHING (Fast Refresh is dev-only), a
--     @Static@\/headless main emits nothing (no Model to preserve), and equal
--     Model types hash equal while a changed Model type hashes differently —
--     the preserve-vs-reset gate the host keys off.
--
-- @since 0.20.11
module Unit.Generate.JavaScript.NativeHMRTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Numeric (showHex)
import qualified Generate.JavaScript.ESM.HMR as HMR
import qualified Generate.JavaScript.NativeHMR as NativeHMR
import qualified Generate.Mode as Mode
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Data.Set as Set
import Test.Tasty
import Test.Tasty.HUnit

-- HELPERS -------------------------------------------------------------------

render :: BB.Builder -> String
render = LChar8.unpack . BB.toLazyByteString

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty Map.empty

mainHome :: ModuleName.Canonical
mainHome = ModuleName.Canonical Pkg.core (Name.fromChars "Main")

-- | A Model type with a single Int field: @{ count : Int }@. Representative of a
-- counter program's Model.
counterModel :: Can.Type
counterModel =
  Can.TRecord (Map.fromList [(Name.fromChars "count", Can.FieldType 0 intType)]) Nothing

-- | A Model type with a different shape (an added @label : String@ field): a
-- structural change that MUST hash differently from 'counterModel'.
counterModelV2 :: Can.Type
counterModelV2 =
  Can.TRecord
    ( Map.fromList
        [ (Name.fromChars "count", Can.FieldType 0 intType)
        , (Name.fromChars "label", Can.FieldType 1 stringType)
        ]
    )
    Nothing

intType :: Can.Type
intType = Can.TType (ModuleName.Canonical Pkg.core (Name.fromChars "Basics")) (Name.fromChars "Int") []

stringType :: Can.Type
stringType = Can.TType (ModuleName.Canonical Pkg.core (Name.fromChars "String")) (Name.fromChars "String") []

-- | A Dynamic (TEA) main carrying 'counterModel'. The message type + decoder are
-- never read by the HMR emitter (it gates only on the Model type), so a unit
-- message type and a trivial decoder expression stand in.
dynamicMain :: Can.Type -> Opt.Main
dynamicMain model = Opt.Dynamic model Can.TUnit Opt.Unit

-- | The expected hex string for a Model type, matching 'ESM.HMR's hash.
expectedHex :: Can.Type -> String
expectedHex t = showHex (HMR.hashCanType t) ""

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.NativeHMR (CMP-9)"
    [ runtimeTests
    , typehashTests
    , registerTests
    , gatingTests
    , compatGateTests
    ]

-- THE __canopy_hmr RUNTIME --------------------------------------------------

runtimeTests :: TestTree
runtimeTests =
  testGroup
    "__canopy_hmr runtime"
    [ testCase "installs __canopy_hmr on the global" $
        assertBool "names g.__canopy_hmr" $
          "g.__canopy_hmr" `isInfixOf` render NativeHMR.hmrRuntime
    , testCase "is idempotent (re-eval-safe): bails if already installed" $
        assertBool "guards on existing __canopy_hmr" $
          "if (g.__canopy_hmr) { return; }" `isInfixOf` render NativeHMR.hmrRuntime
    , testCase "exposes register(moduleId, members, modelHash)" $
        assertBool "register signature present" $
          "register: function (moduleId, members, modelHash)"
            `isInfixOf` render NativeHMR.hmrRuntime
    , testCase "exposes the accept model-compat gate" $
        assertBool "accept signature present" $
          "accept: function (moduleId, nextMembers, nextModelHash)"
            `isInfixOf` render NativeHMR.hmrRuntime
    , testCase "accept rejects (returns false) on a changed modelHash" $
        assertBool "compat gate compares hashes and returns false on mismatch" $
          "if (prev.modelHash !== nextModelHash)"
            `isInfixOf` render NativeHMR.hmrRuntime
    , testCase "installs onto globalThis (bare Hermes host global)" $
        assertBool "uses globalThis fallback" $
          "typeof globalThis !== 'undefined' ? globalThis : this"
            `isInfixOf` render NativeHMR.hmrRuntime
    ]

-- THE __canopy_model_typehash GLOBAL (DEV-8 load-bearing) --------------------

typehashTests :: TestTree
typehashTests =
  testGroup
    "__canopy_model_typehash global (DEV-8)"
    [ testCase "sets globalThis.__canopy_model_typehash" $
        assertBool "names the exact global the host reads" $
          "globalThis.__canopy_model_typehash = \""
            `isInfixOf` render (NativeHMR.modelTypehashGlobal (HMR.hashCanType counterModel))
    , testCase "carries the SAME hex ESM.HMR uses for the same Model" $
        assertBool ("expected hex " <> expectedHex counterModel) $
          ("\"" <> expectedHex counterModel <> "\"")
            `isInfixOf` render (NativeHMR.modelTypehashGlobal (HMR.hashCanType counterModel))
    , testCase "modelHashHex matches BB.word32Hex (the ESM hex shape)" $
        render (NativeHMR.modelHashHex (HMR.hashCanType counterModel))
          @?= expectedHex counterModel
    ]

-- THE register(...) BOUNDARY -------------------------------------------------

registerTests :: TestTree
registerTests =
  let out = render (NativeHMR.generateNativeHMR devMode (Map.singleton mainHome (dynamicMain counterModel)))
   in testGroup
        "register(...) boundary (dev, Dynamic main)"
        [ testCase "emits the runtime install" $
            assertBool "runtime present" $ "g.__canopy_hmr" `isInfixOf` out
        , testCase "emits the model-typehash global" $
            assertBool "typehash global present" $
              "globalThis.__canopy_model_typehash = \"" `isInfixOf` out
        , testCase "calls __canopy_hmr.register" $
            assertBool "register call present" $ "__canopy_hmr.register(" `isInfixOf` out
        , testCase "register's first arg is the module id \"Main\"" $
            assertBool "moduleId is \"Main\"" $ "__canopy_hmr.register(\"Main\", " `isInfixOf` out
        , testCase "register reaches the exported program under scope['Canopy']" $
            assertBool "program ref present" $ "scope['Canopy']['Main']" `isInfixOf` out
        , testCase "register's modelHash equals the typehash global's hex" $
            assertBool ("hash " <> expectedHex counterModel <> " appears twice (global + register)") $
              count (expectedHex counterModel) out >= 2
        , testCase "moduleIdFor renders the module name" $
            render (NativeHMR.moduleIdFor mainHome) @?= "Main"
        ]

-- DEV/PROD + STATIC GATING ---------------------------------------------------

gatingTests :: TestTree
gatingTests =
  testGroup
    "gating"
    [ testCase "production (--optimize) emits NOTHING (Fast Refresh is dev-only)" $
        render (NativeHMR.generateNativeHMR prodMode (Map.singleton mainHome (dynamicMain counterModel)))
          @?= ""
    , testCase "a Static (headless) main emits NOTHING (no Model to preserve)" $
        render (NativeHMR.generateNativeHMR devMode (Map.singleton mainHome Opt.Static))
          @?= ""
    , testCase "no mains at all emits NOTHING" $
        render (NativeHMR.generateNativeHMR devMode Map.empty)
          @?= ""
    , testCase "a Dynamic main in dev DOES emit" $
        assertBool "non-empty for a dev Dynamic main" $
          not (null (render (NativeHMR.generateNativeHMR devMode (Map.singleton mainHome (dynamicMain counterModel)))))
    ]

-- THE MODEL-COMPAT GATE (preserve vs reset) ----------------------------------

compatGateTests :: TestTree
compatGateTests =
  testGroup
    "model-compat gate (reuses hashCanType)"
    [ testCase "the SAME Model type hashes the SAME (preserve)" $
        HMR.hashCanType counterModel @?= HMR.hashCanType counterModel
    , testCase "a CHANGED Model type hashes DIFFERENTLY (reset)" $
        assertBool "an added field changes the hash" $
          HMR.hashCanType counterModel /= HMR.hashCanType counterModelV2
    , testCase "the emitted hex differs for the changed Model" $
        assertBool "register hex tracks the Model change" $
          let outV1 = render (NativeHMR.generateNativeHMR devMode (Map.singleton mainHome (dynamicMain counterModel)))
              outV2 = render (NativeHMR.generateNativeHMR devMode (Map.singleton mainHome (dynamicMain counterModelV2)))
           in (expectedHex counterModel `isInfixOf` outV1)
                && (expectedHex counterModelV2 `isInfixOf` outV2)
                && not (expectedHex counterModelV2 `isInfixOf` outV1)
    ]

-- | Count non-overlapping occurrences of a needle in a haystack.
count :: String -> String -> Int
count needle haystack = go haystack
  where
    n = length needle
    go [] = 0
    go s@(_ : rest)
      | needle `isPrefixOf'` s = 1 + go (drop n s)
      | otherwise = go rest
    isPrefixOf' p xs = take (length p) xs == p
