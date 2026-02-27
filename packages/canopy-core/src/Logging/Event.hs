{-# LANGUAGE OverloadedStrings #-}

-- | Structured log events for the Canopy compiler.
--
-- This module defines the 'LogEvent' ADT that replaces all stringly-typed
-- logging in the compiler. Each event captures structured data about a
-- specific compiler operation, enabling machine-parseable output, filtering
-- by phase/level, and zero-cost disabling.
--
-- == Design
--
-- Events are grouped by compiler phase. Each constructor carries only the
-- data needed to render a human-readable message or a JSON object. The
-- 'eventLevel' and 'eventPhase' projections enable filtering without
-- pattern-matching on every constructor at the call site.
--
-- @since 0.19.1
module Logging.Event
  ( -- * Core types
    LogLevel (..),
    Phase (..),
    Duration (..),
    LogEvent (..),

    -- * Stat records
    ParseStats (..),
    CanonStats (..),
    TypeStats (..),
    OptStats (..),
    GenStats (..),
    CompileStats (..),

    -- * Resolution & constraint kinds
    VarResolution (..),
    ConstraintKind (..),

    -- * Projections
    eventLevel,
    eventPhase,

    -- * Rendering
    renderCLI,
    renderPhase,
    renderLevel,

    -- * Duration helpers
    durationMicros,
    durationMillis,
    formatDuration,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text

-- | Log severity levels, ordered from most verbose to least verbose.
--
-- @since 0.19.1
data LogLevel
  = TRACE
  | DEBUG
  | INFO
  | WARN
  | ERROR
  deriving (Show, Eq, Ord)

-- | Compiler phases for event grouping and filtering.
--
-- @since 0.19.1
data Phase
  = PhaseParse
  | PhaseCanon
  | PhaseType
  | PhaseOptimize
  | PhaseGenerate
  | PhaseBuild
  | PhaseCache
  | PhaseFFI
  | PhaseWorker
  | PhaseKernel
  | PhasePackage
  deriving (Show, Eq, Ord)

-- | Elapsed time measurement in microseconds.
--
-- @since 0.19.1
newtype Duration = Duration {_durationMicros :: Int}
  deriving (Show, Eq, Ord)

-- | Extract the raw microsecond count.
durationMicros :: Duration -> Int
durationMicros (Duration us) = us

-- | Convert duration to milliseconds.
durationMillis :: Duration -> Double
durationMillis (Duration us) = fromIntegral us / 1000.0

-- | Render duration for human consumption.
formatDuration :: Duration -> Text
formatDuration (Duration us)
  | us < 1000 = Text.pack (show us) <> "us"
  | us < 1000000 = Text.pack (show (us `div` 1000)) <> "ms"
  | otherwise = Text.pack (show (us `div` 1000000)) <> "s"

-- | How a variable was resolved during canonicalization.
--
-- @since 0.19.1
data VarResolution
  = ResLocal
  | ResToplevel
  | ResForeign !Text
  | ResKernel
  | ResAmbiguous
  deriving (Show, Eq)

-- | The kind of type constraint that was solved.
--
-- @since 0.19.1
data ConstraintKind
  = CKEqual
  | CKLocal
  | CKForeign
  | CKPattern
  | CKLet
  | CKAnd
  | CKCase
  deriving (Show, Eq)

-- | Statistics collected after parsing a module.
data ParseStats = ParseStats
  { _parseDecls :: !Int,
    _parseImports :: !Int,
    _parseFFI :: !Bool
  }
  deriving (Show, Eq)

-- | Statistics collected after canonicalization.
data CanonStats = CanonStats
  { _canonBindings :: !Int,
    _canonForeign :: !Int,
    _canonErrors :: !Int
  }
  deriving (Show, Eq)

-- | Statistics collected after type solving.
data TypeStats = TypeStats
  { _typeBindings :: !Int,
    _typeConstraints :: !Int,
    _typeUnifications :: !Int
  }
  deriving (Show, Eq)

-- | Statistics collected after optimization.
data OptStats = OptStats
  { _optNodes :: !Int,
    _optInlined :: !Int,
    _optDeadElim :: !Int
  }
  deriving (Show, Eq)

-- | Statistics collected after code generation.
data GenStats = GenStats
  { _genBytes :: !Int,
    _genFunctions :: !Int
  }
  deriving (Show, Eq)

-- | Statistics collected after full compilation pipeline.
data CompileStats = CompileStats
  { _compileModules :: !Int,
    _compileDuration :: !Duration
  }
  deriving (Show, Eq)

-- | Every loggable event in the Canopy compiler.
--
-- Constructors are grouped by phase. Each carries only the structured data
-- needed for rendering. Call 'eventLevel' and 'eventPhase' for filtering.
--
-- @since 0.19.1
data LogEvent
  = -- Parse
    ParseStarted !FilePath !Int
  | ParseCompleted !FilePath !ParseStats
  | ParseFailed !FilePath !Text
  | -- Canonicalize
    CanonStarted !Text
  | CanonVarResolved !Text !Text !VarResolution
  | CanonCompleted !Text !CanonStats
  | CanonFailed !Text !Text
  | -- Type
    TypeConstrainStarted !Text
  | TypeConstraintSolved !Text !ConstraintKind
  | TypeUnified !Text !Text !Text
  | TypeUnifyFailed !Text !Text !Text
  | TypeSolveStarted !Text !Int
  | TypeSolveCompleted !Text !TypeStats
  | TypeSolveFailed !Text !Int
  | TypeLetGeneralized !Text !Text !Int
  | -- Optimize
    OptimizeStarted !Text
  | OptimizeBranchInlined !Text !Int
  | OptimizeBranchJumped !Text !Int !Int
  | OptimizeDecisionTree !Text !Int !Int
  | OptimizeCompleted !Text !OptStats
  | OptimizeFailed !Text !Text
  | -- Generate
    GenerateStarted !Text
  | GenerateCompleted !Text !GenStats
  | -- Compile pipeline
    CompileStarted !FilePath
  | CompilePhaseEnter !Phase !Text
  | CompilePhaseExit !Phase !Text !Duration
  | CompileCompleted !FilePath !CompileStats
  | CompileFailed !FilePath !Phase !Text
  | -- Cache
    CacheHit !Phase !Text
  | CacheMiss !Phase !Text
  | CacheStored !Text !Int
  | -- FFI
    FFILoading !FilePath
  | FFILoaded !FilePath !Int
  | FFIMissing !FilePath
  | -- Worker
    WorkerSpawned !Int
  | WorkerCompleted !Int !Duration
  | WorkerFailed !Int !Text
  | -- Kernel
    KernelStarted !FilePath
  | KernelCompleted !FilePath !Int
  | KernelFailed !FilePath !Text
  | -- Build
    BuildStarted !Text
  | BuildModuleQueued !Text
  | BuildCompleted !Int !Duration
  | BuildFailed !Text
  | BuildHashComputed !FilePath
  | BuildIncremental !Int !Int
  | -- Package / Archive
    PackageOperation !Text !Text
  | ArchiveOperation !Text !Text
  | -- Interface
    InterfaceLoaded !FilePath
  | InterfaceSaved !FilePath
  deriving (Show, Eq)

-- | Determine the log level for an event.
--
-- Boundary events (Started/Completed/Failed) are DEBUG.
-- Internal detail events (VarResolved, Unified, BranchInlined) are TRACE.
-- Cache and build progress are INFO. Failures are WARN or ERROR.
eventLevel :: LogEvent -> LogLevel
eventLevel = \case
  ParseStarted {} -> DEBUG
  ParseCompleted {} -> DEBUG
  ParseFailed {} -> ERROR
  CanonStarted {} -> DEBUG
  CanonVarResolved {} -> TRACE
  CanonCompleted {} -> DEBUG
  CanonFailed {} -> ERROR
  TypeConstrainStarted {} -> DEBUG
  TypeConstraintSolved {} -> TRACE
  TypeUnified {} -> TRACE
  TypeUnifyFailed {} -> TRACE
  TypeSolveStarted {} -> DEBUG
  TypeSolveCompleted {} -> DEBUG
  TypeSolveFailed {} -> ERROR
  TypeLetGeneralized {} -> TRACE
  OptimizeStarted {} -> DEBUG
  OptimizeBranchInlined {} -> TRACE
  OptimizeBranchJumped {} -> TRACE
  OptimizeDecisionTree {} -> TRACE
  OptimizeCompleted {} -> DEBUG
  OptimizeFailed {} -> ERROR
  GenerateStarted {} -> DEBUG
  GenerateCompleted {} -> DEBUG
  CompileStarted {} -> INFO
  CompilePhaseEnter {} -> DEBUG
  CompilePhaseExit {} -> DEBUG
  CompileCompleted {} -> INFO
  CompileFailed {} -> ERROR
  CacheHit {} -> DEBUG
  CacheMiss {} -> DEBUG
  CacheStored {} -> DEBUG
  FFILoading {} -> DEBUG
  FFILoaded {} -> DEBUG
  FFIMissing {} -> WARN
  WorkerSpawned {} -> DEBUG
  WorkerCompleted {} -> DEBUG
  WorkerFailed {} -> ERROR
  KernelStarted {} -> DEBUG
  KernelCompleted {} -> DEBUG
  KernelFailed {} -> ERROR
  BuildStarted {} -> INFO
  BuildModuleQueued {} -> DEBUG
  BuildCompleted {} -> INFO
  BuildFailed {} -> ERROR
  BuildHashComputed {} -> TRACE
  BuildIncremental {} -> INFO
  PackageOperation {} -> DEBUG
  ArchiveOperation {} -> DEBUG
  InterfaceLoaded {} -> DEBUG
  InterfaceSaved {} -> DEBUG

-- | Determine the phase for an event.
eventPhase :: LogEvent -> Phase
eventPhase = \case
  ParseStarted {} -> PhaseParse
  ParseCompleted {} -> PhaseParse
  ParseFailed {} -> PhaseParse
  CanonStarted {} -> PhaseCanon
  CanonVarResolved {} -> PhaseCanon
  CanonCompleted {} -> PhaseCanon
  CanonFailed {} -> PhaseCanon
  TypeConstrainStarted {} -> PhaseType
  TypeConstraintSolved {} -> PhaseType
  TypeUnified {} -> PhaseType
  TypeUnifyFailed {} -> PhaseType
  TypeSolveStarted {} -> PhaseType
  TypeSolveCompleted {} -> PhaseType
  TypeSolveFailed {} -> PhaseType
  TypeLetGeneralized {} -> PhaseType
  OptimizeStarted {} -> PhaseOptimize
  OptimizeBranchInlined {} -> PhaseOptimize
  OptimizeBranchJumped {} -> PhaseOptimize
  OptimizeDecisionTree {} -> PhaseOptimize
  OptimizeCompleted {} -> PhaseOptimize
  OptimizeFailed {} -> PhaseOptimize
  GenerateStarted {} -> PhaseGenerate
  GenerateCompleted {} -> PhaseGenerate
  CompileStarted {} -> PhaseBuild
  CompilePhaseEnter {} -> PhaseBuild
  CompilePhaseExit {} -> PhaseBuild
  CompileCompleted {} -> PhaseBuild
  CompileFailed {} -> PhaseBuild
  CacheHit {} -> PhaseCache
  CacheMiss {} -> PhaseCache
  CacheStored {} -> PhaseCache
  FFILoading {} -> PhaseFFI
  FFILoaded {} -> PhaseFFI
  FFIMissing {} -> PhaseFFI
  WorkerSpawned {} -> PhaseWorker
  WorkerCompleted {} -> PhaseWorker
  WorkerFailed {} -> PhaseWorker
  KernelStarted {} -> PhaseKernel
  KernelCompleted {} -> PhaseKernel
  KernelFailed {} -> PhaseKernel
  BuildStarted {} -> PhaseBuild
  BuildModuleQueued {} -> PhaseBuild
  BuildCompleted {} -> PhaseBuild
  BuildFailed {} -> PhaseBuild
  BuildHashComputed {} -> PhaseBuild
  BuildIncremental {} -> PhaseBuild
  PackageOperation {} -> PhasePackage
  ArchiveOperation {} -> PhasePackage
  InterfaceLoaded {} -> PhaseCache
  InterfaceSaved {} -> PhaseCache

-- | Render an event as a single-line CLI string (no timestamp prefix).
renderCLI :: LogEvent -> Text
renderCLI = \case
  ParseStarted path size ->
    "Parsing " <> Text.pack path <> " (" <> Text.pack (show size) <> " bytes)"
  ParseCompleted path stats ->
    "Parsed " <> Text.pack path <> " (" <> Text.pack (show (_parseDecls stats)) <> " decls, " <> Text.pack (show (_parseImports stats)) <> " imports)"
  ParseFailed path msg ->
    "Parse failed: " <> Text.pack path <> " — " <> msg
  CanonStarted modName ->
    "Canonicalizing " <> modName
  CanonVarResolved modName name res ->
    "Resolved " <> modName <> "." <> name <> " → " <> renderResolution res
  CanonCompleted modName stats ->
    "Canonicalized " <> modName <> " (" <> Text.pack (show (_canonBindings stats)) <> " bindings)"
  CanonFailed modName msg ->
    "Canon failed: " <> modName <> " — " <> msg
  TypeConstrainStarted modName ->
    "Constraining " <> modName
  TypeConstraintSolved modName kind ->
    "Solved " <> renderConstraintKind kind <> " in " <> modName
  TypeUnified modName t1 t2 ->
    "Unified " <> t1 <> " ~ " <> t2 <> " in " <> modName
  TypeUnifyFailed modName t1 t2 ->
    "Unify failed: " <> t1 <> " !~ " <> t2 <> " in " <> modName
  TypeSolveStarted modName count ->
    "Solving " <> modName <> " (" <> Text.pack (show count) <> " constraints)"
  TypeSolveCompleted modName stats ->
    "Solved " <> modName <> " (" <> Text.pack (show (_typeBindings stats)) <> " bindings, " <> Text.pack (show (_typeUnifications stats)) <> " unifications)"
  TypeSolveFailed modName count ->
    "Type solve failed: " <> modName <> " (" <> Text.pack (show count) <> " errors)"
  TypeLetGeneralized modName name flexCount ->
    "Generalized let " <> name <> " (" <> Text.pack (show flexCount) <> " flex vars) in " <> modName
  OptimizeStarted modName ->
    "Optimizing " <> modName
  OptimizeBranchInlined modName idx ->
    "Inlined branch " <> Text.pack (show idx) <> " in " <> modName
  OptimizeBranchJumped modName idx refs ->
    "Jump branch " <> Text.pack (show idx) <> " (" <> Text.pack (show refs) <> " refs) in " <> modName
  OptimizeDecisionTree modName branches depth ->
    "Decision tree: " <> Text.pack (show branches) <> " branches, depth " <> Text.pack (show depth) <> " in " <> modName
  OptimizeCompleted modName stats ->
    "Optimized " <> modName <> " (" <> Text.pack (show (_optNodes stats)) <> " nodes, " <> Text.pack (show (_optInlined stats)) <> " inlined)"
  OptimizeFailed modName msg ->
    "Optimize failed: " <> modName <> " — " <> msg
  GenerateStarted modName ->
    "Generating " <> modName
  GenerateCompleted modName stats ->
    "Generated " <> modName <> " (" <> Text.pack (show (_genBytes stats)) <> " bytes, " <> Text.pack (show (_genFunctions stats)) <> " functions)"
  CompileStarted path ->
    "Compiling " <> Text.pack path
  CompilePhaseEnter phase modName ->
    "→ " <> renderPhase phase <> " " <> modName
  CompilePhaseExit phase modName dur ->
    "← " <> renderPhase phase <> " " <> modName <> " (" <> formatDuration dur <> ")"
  CompileCompleted path stats ->
    "Compiled " <> Text.pack path <> " (" <> Text.pack (show (_compileModules stats)) <> " modules, " <> formatDuration (_compileDuration stats) <> ")"
  CompileFailed path phase msg ->
    "Compile failed: " <> Text.pack path <> " at " <> renderPhase phase <> " — " <> msg
  CacheHit phase key ->
    "Cache hit: " <> renderPhase phase <> " " <> key
  CacheMiss phase key ->
    "Cache miss: " <> renderPhase phase <> " " <> key
  CacheStored key bytes ->
    "Cache stored: " <> key <> " (" <> Text.pack (show bytes) <> " bytes)"
  FFILoading path ->
    "Loading FFI: " <> Text.pack path
  FFILoaded path count ->
    "Loaded FFI: " <> Text.pack path <> " (" <> Text.pack (show count) <> " bindings)"
  FFIMissing path ->
    "FFI missing: " <> Text.pack path
  WorkerSpawned wid ->
    "Worker spawned: " <> Text.pack (show wid)
  WorkerCompleted wid dur ->
    "Worker completed: " <> Text.pack (show wid) <> " (" <> formatDuration dur <> ")"
  WorkerFailed wid msg ->
    "Worker failed: " <> Text.pack (show wid) <> " — " <> msg
  KernelStarted path ->
    "Loading kernel: " <> Text.pack path
  KernelCompleted path count ->
    "Loaded kernel: " <> Text.pack path <> " (" <> Text.pack (show count) <> " chunks)"
  KernelFailed path msg ->
    "Kernel failed: " <> Text.pack path <> " — " <> msg
  BuildStarted label ->
    "Build started: " <> label
  BuildModuleQueued modName ->
    "Queued: " <> modName
  BuildCompleted count dur ->
    "Build completed: " <> Text.pack (show count) <> " modules (" <> formatDuration dur <> ")"
  BuildFailed msg ->
    "Build failed: " <> msg
  BuildHashComputed path ->
    "Hash computed: " <> Text.pack path
  BuildIncremental hits misses ->
    "Incremental: " <> Text.pack (show hits) <> " hits, " <> Text.pack (show misses) <> " misses"
  PackageOperation op detail ->
    "Package " <> op <> ": " <> detail
  ArchiveOperation op detail ->
    "Archive " <> op <> ": " <> detail
  InterfaceLoaded path ->
    "Interface loaded: " <> Text.pack path
  InterfaceSaved path ->
    "Interface saved: " <> Text.pack path

-- | Render a phase as a short human-readable label.
renderPhase :: Phase -> Text
renderPhase = \case
  PhaseParse -> "PARSE"
  PhaseCanon -> "CANON"
  PhaseType -> "TYPE"
  PhaseOptimize -> "OPT"
  PhaseGenerate -> "GEN"
  PhaseBuild -> "BUILD"
  PhaseCache -> "CACHE"
  PhaseFFI -> "FFI"
  PhaseWorker -> "WORKER"
  PhaseKernel -> "KERNEL"
  PhasePackage -> "PKG"

-- | Render a log level as a fixed-width label.
renderLevel :: LogLevel -> Text
renderLevel = \case
  TRACE -> "TRACE"
  DEBUG -> "DEBUG"
  INFO -> "INFO "
  WARN -> "WARN "
  ERROR -> "ERROR"

-- | Render a variable resolution kind.
renderResolution :: VarResolution -> Text
renderResolution = \case
  ResLocal -> "local"
  ResToplevel -> "toplevel"
  ResForeign modName -> "foreign(" <> modName <> ")"
  ResKernel -> "kernel"
  ResAmbiguous -> "ambiguous"

-- | Render a constraint kind.
renderConstraintKind :: ConstraintKind -> Text
renderConstraintKind = \case
  CKEqual -> "equal"
  CKLocal -> "local"
  CKForeign -> "foreign"
  CKPattern -> "pattern"
  CKLet -> "let"
  CKAnd -> "and"
  CKCase -> "case"
