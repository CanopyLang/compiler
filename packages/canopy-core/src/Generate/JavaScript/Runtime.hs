{-# LANGUAGE OverloadedStrings #-}

-- | Embedded Canopy Runtime
--
-- This module provides the core runtime primitives that the Canopy code
-- generator references directly by global name (@_Utils_eq@, @_List_Nil@,
-- @_Basics_add@, @_Scheduler_succeed@, @_Platform_worker@, etc.).
--
-- The runtime content lives in "Generate.JavaScript.Runtime.Registry" as
-- individually addressable definitions. This module provides the public
-- API for emitting the runtime — either in full (backwards compatible)
-- or tree-shaken (only the functions that are actually referenced).
--
-- = Debug\/Prod Mode
--
-- The runtime uses @__canopy_debug@ (emitted before the runtime content)
-- to select between debug representations (string tags like @\"Just\"@)
-- and prod representations (integer tags like @0@).
--
-- @since 0.20.0
module Generate.JavaScript.Runtime
  ( -- * Full emission (backwards compatible)
    embeddedRuntimeForMode,
    embeddedRuntime,

    -- * Tree-shaken emission
    emitNeeded,

    -- * Re-exports from Registry
    module Generate.JavaScript.Runtime.Registry,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.Set (Set)
import Generate.JavaScript.Runtime.Registry
import qualified Generate.JavaScript.FFI.Minify as FFIMinify
import qualified Generate.JavaScript.Runtime.Registry as Registry
import qualified Generate.Mode as Mode

-- | Emit the full Canopy runtime, preceded by the @__canopy_debug@ declaration.
--
-- In dev mode: @var __canopy_debug = true;@ followed by the runtime.
-- In prod mode: @var __canopy_debug = false;@ followed by the runtime.
--
-- This is the backwards-compatible path that emits all ~144 runtime functions.
-- For tree-shaken output, use 'emitNeeded' instead.
--
-- @since 0.20.0
embeddedRuntimeForMode :: Mode.Mode -> Builder
embeddedRuntimeForMode mode = case mode of
  Mode.Dev {} ->
    modeDeclaration mode <> Registry.topoEmit Registry.allIds
  Mode.Prod {} ->
    let raw = modeDeclaration mode <> Registry.topoEmit Registry.allIds
        rawBS = BL.toStrict (BB.toLazyByteString raw)
    in BB.byteString (FFIMinify.stripDebugBranches rawBS)

-- | Full embedded Canopy runtime without mode declaration.
--
-- Emits all runtime functions in topological order.
-- Equivalent to the former monolithic quasi-quote.
--
-- @since 0.20.0
embeddedRuntime :: Builder
embeddedRuntime = Registry.rawRuntimeContent

-- | Emit only the needed runtime functions, preceded by the mode declaration.
--
-- The given set should already be closed under dependencies
-- (use 'Registry.closeDeps' to compute the transitive closure).
--
-- @since 0.20.1
emitNeeded :: Mode.Mode -> Set RuntimeId -> Builder
emitNeeded mode needed =
  modeDeclaration mode <> minifiedContent
  where
    rawContent = Registry.topoEmit needed
    minifiedContent = case mode of
      Mode.Prod {} ->
        BB.byteString (FFIMinify.stripDebugBranches (BL.toStrict (BB.toLazyByteString rawContent)))
      Mode.Dev {} -> rawContent

-- INTERNAL

-- | Mode-dependent debug flag declaration.
modeDeclaration :: Mode.Mode -> Builder
modeDeclaration (Mode.Dev {}) = "var __canopy_debug = true;\n"
modeDeclaration (Mode.Prod {}) = "var __canopy_debug = false;\n"
