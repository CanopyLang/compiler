{-# LANGUAGE OverloadedStrings #-}

-- | Coverage instrumentation for the Canopy compiler.
--
-- When @--coverage@ is passed, the compiler injects @__cov(N)@ calls at
-- function entries, if-branch sites, and case-branch sites. After tests
-- run, the runtime counters are combined with a source-location map to
-- produce terminal, Istanbul JSON, and LCOV reports.
--
-- == Design: Deterministic Counter IDs
--
-- Both 'buildCoverageMap' (Haskell) and the JS instrumentor must agree on
-- IDs. Globals are visited in 'Map.Map' order (ordered by @(Name, Canonical)@).
-- Within each expression, a depth-first walk visits: Function->body,
-- If->branches->final, Case->jumps, Let->def->body, Call->func->args.
--
-- @since 0.19.2
module Generate.JavaScript.Coverage
  ( CoveragePointType (..),
    CoveragePoint (..),
    CoverageMap (..),
    buildCoverageMap,
    countNodePoints,
    countExprPoints,
    countDefPoints,
    computeBaseIds,
    coverageRuntimePreamble,
    covCall,
    toIstanbulJson,
    toLCOV,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.Map.Strict as Map
import qualified Json.Encode as Encode
import Json.Encode ((==>))
import qualified Json.String as Json
import qualified Reporting.Annotation as Ann

-- | Type of instrumentation point.
--
-- @since 0.19.2
data CoveragePointType
  = FunctionEntry
  | BranchArm !Int !Int
  | TopLevelDef
  deriving (Eq, Show)

-- | A single coverage instrumentation point.
--
-- @since 0.19.2
data CoveragePoint = CoveragePoint
  { _covId :: !Int,
    _covModule :: !Name.Name,
    _covDef :: !Name.Name,
    _covRegion :: !Ann.Region,
    _covType :: !CoveragePointType
  }
  deriving (Eq, Show)

-- | Map from coverage point ID to its metadata.
--
-- @since 0.19.2
newtype CoverageMap = CoverageMap (Map.Map Int CoveragePoint)
  deriving (Eq, Show)

-- | Build the coverage map from all globals and their source locations.
--
-- Walks sorted globals in the same order as the JS instrumentor,
-- assigning sequential IDs based on 'computeBaseIds'.
--
-- @since 0.19.2
buildCoverageMap ::
  Map.Map Opt.Global Opt.Node ->
  Map.Map Opt.Global Ann.Region ->
  CoverageMap
buildCoverageMap graph locs =
  CoverageMap (Map.foldlWithKey' addNodePoints Map.empty baseIds)
  where
    baseIds = computeBaseIds graph

    addNodePoints acc global baseId =
      case Map.lookup global graph of
        Nothing -> acc
        Just node ->
          addPointsForNode acc global baseId node (Map.lookup global locs)

-- | Add coverage points for a single node.
addPointsForNode ::
  Map.Map Int CoveragePoint ->
  Opt.Global ->
  Int ->
  Opt.Node ->
  Maybe Ann.Region ->
  Map.Map Int CoveragePoint
addPointsForNode acc (Opt.Global home name) baseId node maybeRegion =
  case node of
    Opt.Define expr _deps ->
      addExprPoints acc moduleName name baseId region expr
    Opt.DefineTailFunc _args body _deps ->
      addExprPoints acc moduleName name baseId region body
    _ -> acc
  where
    moduleName = ModuleName._module home
    region = maybe defaultRegion id maybeRegion
    defaultRegion = Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

-- | Recursively add coverage points for an expression tree.
addExprPoints ::
  Map.Map Int CoveragePoint ->
  Name.Name ->
  Name.Name ->
  Int ->
  Ann.Region ->
  Opt.Expr ->
  Map.Map Int CoveragePoint
addExprPoints acc modName defName baseId region expr =
  fst (addExprPointsAccum acc modName defName baseId region expr)

-- | Add expression points, returning updated map and next counter.
addExprPointsAccum ::
  Map.Map Int CoveragePoint ->
  Name.Name ->
  Name.Name ->
  Int ->
  Ann.Region ->
  Opt.Expr ->
  (Map.Map Int CoveragePoint, Int)
addExprPointsAccum acc modName defName counter region expr =
  case expr of
    Opt.Function _args body ->
      let pt = mkPoint counter modName defName region FunctionEntry
          acc' = Map.insert counter pt acc
       in addExprPointsAccum acc' modName defName (counter + 1) region body
    Opt.If branches final ->
      let (acc', counter') = foldl addBranch (acc, counter) (zip [0 ..] branches)
          ptElse = mkPoint counter' modName defName region (BranchArm (length branches) (length branches))
          acc'' = Map.insert counter' ptElse acc'
       in addExprPointsAccum acc'' modName defName (counter' + 1) region final
      where
        addBranch (a, c) (i, (_cond, thenExpr)) =
          let pt = mkPoint c modName defName region (BranchArm i (length branches + 1))
              a' = Map.insert c pt a
           in addExprPointsAccum a' modName defName (c + 1) region thenExpr
    Opt.Case _label _root _decider jumps ->
      foldl addJump (acc, counter) (zip [0 ..] jumps)
      where
        addJump (a, c) (i, (_idx, jumpExpr)) =
          let pt = mkPoint c modName defName region (BranchArm i (length jumps))
              a' = Map.insert c pt a
           in addExprPointsAccum a' modName defName (c + 1) region jumpExpr
    Opt.Let def body ->
      let (acc', counter') = addDefPoints acc modName defName counter region def
       in addExprPointsAccum acc' modName defName counter' region body
    Opt.Call func args ->
      let (acc', counter') = addExprPointsAccum acc modName defName counter region func
       in foldl (\(a, c) arg -> addExprPointsAccum a modName defName c region arg) (acc', counter') args
    Opt.Destruct _destructor body ->
      addExprPointsAccum acc modName defName counter region body
    _ -> (acc, counter)

-- | Add points from a definition.
addDefPoints ::
  Map.Map Int CoveragePoint ->
  Name.Name ->
  Name.Name ->
  Int ->
  Ann.Region ->
  Opt.Def ->
  (Map.Map Int CoveragePoint, Int)
addDefPoints acc modName defName counter region def =
  case def of
    Opt.Def _name body ->
      addExprPointsAccum acc modName defName counter region body
    Opt.TailDef _name _args body ->
      addExprPointsAccum acc modName defName counter region body

-- | Create a coverage point.
mkPoint :: Int -> Name.Name -> Name.Name -> Ann.Region -> CoveragePointType -> CoveragePoint
mkPoint covId modName defName region covType =
  CoveragePoint covId modName defName region covType

-- | Count the number of coverage points in a node.
--
-- @since 0.19.2
countNodePoints :: Opt.Node -> Int
countNodePoints node =
  case node of
    Opt.Define expr _deps -> countExprPoints expr
    Opt.DefineTailFunc _args body _deps -> countExprPoints body
    _ -> 0

-- | Count the number of coverage points in an expression.
--
-- Uses the same depth-first traversal order as the instrumentor:
--
-- * @Opt.Function@ -> 1 point (function entry) + recurse body
-- * @Opt.If branches final@ -> @length branches + 1@ points + recurse all
-- * @Opt.Case _ _ _ jumps@ -> @length jumps@ points + recurse all
-- * Recurse into sub-expressions for Let, Call, Destruct
--
-- @since 0.19.2
countExprPoints :: Opt.Expr -> Int
countExprPoints expr =
  case expr of
    Opt.Function _args body -> 1 + countExprPoints body
    Opt.If branches final ->
      length branches + 1
        + sum (map (\(_c, t) -> countExprPoints t) branches)
        + countExprPoints final
    Opt.Case _label _root _decider jumps ->
      length jumps
        + sum (map (\(_i, e) -> countExprPoints e) jumps)
    Opt.Let def body -> countDefPoints def + countExprPoints body
    Opt.Call func args ->
      countExprPoints func + sum (map countExprPoints args)
    Opt.Destruct _destructor body -> countExprPoints body
    _ -> 0

-- | Count points in a definition.
countDefPoints :: Opt.Def -> Int
countDefPoints (Opt.Def _name body) = countExprPoints body
countDefPoints (Opt.TailDef _name _args body) = countExprPoints body

-- | Compute the base counter offset for each global.
--
-- Globals are visited in 'Map.Map' order. Each global's base ID is the
-- cumulative sum of points from all preceding globals.
--
-- @since 0.19.2
computeBaseIds :: Map.Map Opt.Global Opt.Node -> Map.Map Opt.Global Int
computeBaseIds graph =
  snd (Map.foldlWithKey' accumulate (0, Map.empty) graph)
  where
    accumulate (offset, acc) global node =
      let pts = countNodePoints node
       in (offset + pts, Map.insert global offset acc)

-- | JavaScript preamble that initializes coverage counters.
--
-- Emits: @var __canopy_cov = {}; function __cov(id) { __canopy_cov[id] = (__canopy_cov[id] || 0) + 1; }@
--
-- @since 0.19.2
coverageRuntimePreamble :: Builder
coverageRuntimePreamble =
  BB.stringUtf8 "var __canopy_cov = {}; function __cov(id) { __canopy_cov[id] = (__canopy_cov[id] || 0) + 1; }\n"

-- | Generate a @__cov(N)@ call statement as a JS expression statement.
--
-- @since 0.19.2
covCall :: Int -> Builder
covCall covId =
  BB.stringUtf8 "__cov(" <> BB.intDec covId <> BB.stringUtf8 ");\n"

-- | Convert a coverage map and hit data to Istanbul JSON format.
--
-- @since 0.19.2
toIstanbulJson :: CoverageMap -> Map.Map Int Int -> Encode.Value
toIstanbulJson (CoverageMap points) hits =
  Encode.object
    [ "fnMap" ==> Encode.object (map encodeFnEntry fnPoints),
      "f" ==> Encode.object (map (encodeHit hits) fnPoints),
      "branchMap" ==> Encode.object (map encodeBranchEntry branchPoints),
      "b" ==> Encode.object (map (encodeHit hits) branchPoints),
      "s" ==> Encode.object (map (encodeHit hits) (Map.toList points)),
      "statementMap" ==> Encode.object (map encodeStmtEntry (Map.toList points))
    ]
  where
    fnPoints = filter (isFunctionEntry . snd) (Map.toList points)
    branchPoints = filter (isBranchArm . snd) (Map.toList points)

    isFunctionEntry (CoveragePoint _ _ _ _ FunctionEntry) = True
    isFunctionEntry _ = False

    isBranchArm (CoveragePoint _ _ _ _ (BranchArm _ _)) = True
    isBranchArm _ = False

-- | Encode a function entry for Istanbul fnMap.
encodeFnEntry :: (Int, CoveragePoint) -> (Json.String, Encode.Value)
encodeFnEntry (k, CoveragePoint _ _modName defName region _) =
  ( Json.fromChars (show k),
    Encode.object
      [ "name" ==> Encode.chars (Name.toChars defName),
        "loc" ==> encodeRegion region
      ]
  )

-- | Encode a branch entry for Istanbul branchMap.
encodeBranchEntry :: (Int, CoveragePoint) -> (Json.String, Encode.Value)
encodeBranchEntry (k, CoveragePoint _ _modName _defName region _) =
  ( Json.fromChars (show k),
    Encode.object
      [ "type" ==> Encode.chars "if",
        "loc" ==> encodeRegion region
      ]
  )

-- | Encode a statement entry for Istanbul statementMap.
encodeStmtEntry :: (Int, CoveragePoint) -> (Json.String, Encode.Value)
encodeStmtEntry (k, CoveragePoint _ _modName _defName region _) =
  (Json.fromChars (show k), encodeRegion region)

-- | Encode a hit count.
encodeHit :: Map.Map Int Int -> (Int, CoveragePoint) -> (Json.String, Encode.Value)
encodeHit hits (k, _) =
  (Json.fromChars (show k), Encode.int (maybe 0 id (Map.lookup k hits)))

-- | Encode a source region to Istanbul location format.
encodeRegion :: Ann.Region -> Encode.Value
encodeRegion (Ann.Region (Ann.Position startLine startCol) (Ann.Position endLine endCol)) =
  Encode.object
    [ "start" ==> Encode.object ["line" ==> Encode.int (fromIntegral startLine), "column" ==> Encode.int (fromIntegral startCol)],
      "end" ==> Encode.object ["line" ==> Encode.int (fromIntegral endLine), "column" ==> Encode.int (fromIntegral endCol)]
    ]

-- | Convert a coverage map and hit data to LCOV format.
--
-- @since 0.19.2
toLCOV :: CoverageMap -> Map.Map Int Int -> Builder
toLCOV (CoverageMap points) hits =
  Map.foldlWithKey' appendLine mempty points
  where
    appendLine acc covId (CoveragePoint _ modName defName region covType) =
      acc <> formatLCOVLine modName defName region covType (Map.findWithDefault 0 covId hits)

-- | Format a single LCOV line.
formatLCOVLine :: Name.Name -> Name.Name -> Ann.Region -> CoveragePointType -> Int -> Builder
formatLCOVLine modName defName (Ann.Region (Ann.Position line _) _) covType hitCount =
  case covType of
    FunctionEntry ->
      BB.stringUtf8 "FN:"
        <> BB.intDec (fromIntegral line)
        <> BB.char7 ','
        <> BB.stringUtf8 (Name.toChars modName)
        <> BB.char7 '.'
        <> BB.stringUtf8 (Name.toChars defName)
        <> BB.char7 '\n'
        <> BB.stringUtf8 "FNDA:"
        <> BB.intDec hitCount
        <> BB.char7 ','
        <> BB.stringUtf8 (Name.toChars modName)
        <> BB.char7 '.'
        <> BB.stringUtf8 (Name.toChars defName)
        <> BB.char7 '\n'
    BranchArm branchIdx _total ->
      BB.stringUtf8 "BRDA:"
        <> BB.intDec (fromIntegral line)
        <> BB.char7 ','
        <> BB.intDec 0
        <> BB.char7 ','
        <> BB.intDec branchIdx
        <> BB.char7 ','
        <> BB.intDec hitCount
        <> BB.char7 '\n'
    TopLevelDef ->
      BB.stringUtf8 "DA:"
        <> BB.intDec (fromIntegral line)
        <> BB.char7 ','
        <> BB.intDec hitCount
        <> BB.char7 '\n'
