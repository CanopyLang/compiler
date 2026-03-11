{-# LANGUAGE OverloadedStrings #-}

-- | FFI Capability Enforcement
--
-- Validates that FFI functions' capability requirements are satisfied by
-- the capabilities declared in canopy.json, and generates runtime
-- capability guard code for the JavaScript output.
--
-- == Design
--
-- The capability enforcement pipeline has three stages:
--
-- 1. __Collection__: During canonicalization, capability requirements are
--    extracted from @\@capability@ JSDoc annotations (handled by
--    'Canonicalize.Module.FFI').
--
-- 2. __Validation__: At compile time, required capabilities are checked
--    against the set declared in canopy.json. Missing capabilities produce
--    compile-time errors; unused declared capabilities produce warnings.
--
-- 3. __Runtime Guards__: For each FFI function with capability requirements,
--    the JavaScript output includes a guard that checks the capability
--    registry before allowing execution.
--
-- @since 0.20.0
module FFI.CapabilityEnforcement
  ( -- * Validation
    CapabilityError (..)
  , CapabilityErrorKind (..)
  , validateCapabilities
  , validateCapabilitiesWithDeny
  , findUnusedCapabilities

    -- * Runtime Code Generation
  , generateCapabilityRegistry
  , generateCapabilityGuard
  ) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text

-- | The kind of capability violation.
--
-- @since 0.20.0
data CapabilityErrorKind
  = MissingCapability
  | DeniedCapability
  deriving (Eq, Show)

-- | A compile-time error for capability violations.
--
-- Produced when an FFI function requires a capability that is not
-- declared in canopy.json or is explicitly denied.
--
-- @since 0.20.0
data CapabilityError = CapabilityError
  { _ceFunctionName :: !Text
  , _ceFilePath :: !Text
  , _ceMissingCapability :: !Text
  , _ceErrorKind :: !CapabilityErrorKind
  } deriving (Eq, Show)

-- | Validate that all required capabilities are declared (allow-only).
--
-- Takes the set of allowed capabilities and a list of
-- (function name, file path, required capabilities) triples. Returns
-- errors for any function whose required capabilities are not a subset
-- of the allowed capabilities.
--
-- @since 0.20.0
validateCapabilities
  :: Set Text
  -> [(Text, Text, Set Text)]
  -> [CapabilityError]
validateCapabilities allowed = concatMap (validateOneAllow allowed)

-- | Validate capabilities with both allow and deny lists.
--
-- A capability is valid if it appears in the allow set AND does not
-- appear in the deny set. The deny set takes precedence.
--
-- @since 0.20.0
validateCapabilitiesWithDeny
  :: Set Text
  -> Set Text
  -> [(Text, Text, Set Text)]
  -> [CapabilityError]
validateCapabilitiesWithDeny allowed denied =
  concatMap (validateOneWithDeny allowed denied)

-- | Validate a single function's capability requirements (allow-only).
validateOneAllow :: Set Text -> (Text, Text, Set Text) -> [CapabilityError]
validateOneAllow allowed (funcName, filePath, required) =
  map (\cap -> CapabilityError funcName filePath cap MissingCapability) (Set.toList missing)
  where
    missing = Set.difference required allowed

-- | Validate a single function with both allow and deny lists.
validateOneWithDeny :: Set Text -> Set Text -> (Text, Text, Set Text) -> [CapabilityError]
validateOneWithDeny allowed denied (funcName, filePath, required) =
  deniedErrors ++ missingErrors
  where
    deniedCaps = Set.intersection required denied
    deniedErrors = map (\cap -> CapabilityError funcName filePath cap DeniedCapability) (Set.toList deniedCaps)
    remainingRequired = Set.difference required denied
    missingCaps = Set.difference remainingRequired allowed
    missingErrors = map (\cap -> CapabilityError funcName filePath cap MissingCapability) (Set.toList missingCaps)

-- | Find capabilities declared in canopy.json that no FFI function requires.
--
-- Returns the set of unused capabilities so the compiler can emit warnings
-- suggesting their removal to minimize the application's permission surface.
--
-- @since 0.20.0
findUnusedCapabilities
  :: Set Text
  -> [(Text, Text, Set Text)]
  -> Set Text
findUnusedCapabilities declared requirements =
  Set.difference declared allRequired
  where
    allRequired = Set.unions (map (\(_, _, caps) -> caps) requirements)

-- | Generate the JavaScript capability registry and check function.
--
-- Emits a @_Canopy_capabilities@ object mapping each declared capability
-- to @true@, and a @_Canopy_checkCapability@ function that throws a
-- descriptive error when an undeclared capability is used at runtime.
--
-- When the declared set is empty, no code is emitted (no overhead for
-- projects that do not use capabilities).
--
-- @since 0.20.0
generateCapabilityRegistry :: Set Text -> Builder
generateCapabilityRegistry caps
  | Set.null caps = mempty
  | otherwise =
      BB.stringUtf8 "var _Canopy_capabilities = {"
        <> capEntries
        <> BB.stringUtf8 "};\n"
        <> checkFunction
  where
    capEntries =
      mconcat
        (zipWith (\i c -> separator i <> quoteText c <> BB.stringUtf8 ": true") [0 :: Int ..] (Set.toList caps))

    separator 0 = mempty
    separator _ = BB.stringUtf8 ", "

    checkFunction =
      BB.stringUtf8
        "function _Canopy_checkCapability(cap, fn) {\
        \  if (!_Canopy_capabilities[cap]) {\
        \    throw new Error('Capability \\'' + cap + '\\' required by ' + fn + ' but not granted in canopy.json.');\
        \  }\
        \}\n"

-- | Generate a runtime capability guard for a single FFI function.
--
-- Wraps the function call with a capability check. The guard runs before
-- the original function body so the error is thrown immediately on
-- invocation, not after partial execution.
--
-- When the capability set is empty, returns 'mempty' (no guard needed).
--
-- @since 0.20.0
generateCapabilityGuard :: Text -> Set Text -> Builder
generateCapabilityGuard funcName caps
  | Set.null caps = mempty
  | otherwise = mconcat (map (generateOneCheck funcName) (Set.toList caps))

-- | Generate a single capability check call.
generateOneCheck :: Text -> Text -> Builder
generateOneCheck funcName cap =
  BB.stringUtf8 "_Canopy_checkCapability("
    <> quoteText cap
    <> BB.stringUtf8 ", "
    <> quoteText funcName
    <> BB.stringUtf8 ");\n"

-- | Wrap a text value in double quotes for JavaScript output.
quoteText :: Text -> Builder
quoteText t = BB.charUtf8 '"' <> BB.stringUtf8 (Text.unpack t) <> BB.charUtf8 '"'
