{-# LANGUAGE OverloadedStrings #-}

-- | String literal deduplication for production builds.
--
-- Identifies string literals appearing two or more times in the
-- program and hoists them into shared top-level variables. This
-- reduces bundle size for programs with repeated strings (error
-- messages, CSS class names, attribute keys, etc.).
--
-- In production mode the pool is built from the 'GlobalGraph', pool
-- declarations are emitted after the header, and expression
-- generation checks the pool before emitting a string literal.
--
-- @since 0.19.2
module Generate.JavaScript.StringPool
  ( StringPool,
    emptyPool,
    buildPool,
    poolDeclarations,
    lookupString,
  )
where

import qualified AST.Optimized as Opt
import Data.ByteString.Builder (Builder)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Canopy.String as ES
import qualified Data.Utf8 as Utf8
import qualified Generate.JavaScript.Name as JsName

-- | Pool of deduplicated string literals for production builds.
--
-- Maps string literal values to their assigned short variable names.
-- Only strings with two or more occurrences are included.
newtype StringPool = StringPool (Map ES.String JsName.Name)
  deriving (Show)

-- | Empty pool (used in Dev mode and when no dedup is needed).
emptyPool :: StringPool
emptyPool = StringPool Map.empty

-- | Build pool by scanning all nodes in the graph.
--
-- Pass 1: Count occurrences of each 'Opt.Str' literal.
-- Pass 2: Assign short variable names to strings with count >= 2.
--
-- @since 0.19.2
buildPool :: Map Opt.Global Opt.Node -> StringPool
buildPool graph =
  let freqs = Map.foldl' countNodeStrings Map.empty graph
      poolEntries = Map.filterWithKey (\_ count -> count >= (2 :: Int)) freqs
      indexed = zip (Map.keys poolEntries) [0 :: Int ..]
      poolMap = Map.fromList [(str, poolVarName i) | (str, i) <- indexed]
   in StringPool poolMap

-- | Generate JS variable declarations for pooled strings.
--
-- Produces @var _s0 = "hello"; var _s1 = "world";@ etc.
--
-- @since 0.19.2
poolDeclarations :: StringPool -> Builder
poolDeclarations (StringPool pool)
  | Map.null pool = mempty
  | otherwise =
      Map.foldlWithKey' emitDecl mempty pool
  where
    emitDecl acc str jsName =
      acc <> "var " <> JsName.toBuilder jsName <> " = \""
        <> Utf8.toBuilder str <> "\";\n"

-- | Look up a string in the pool.
--
-- Returns 'Just' the pool variable name if the string is pooled,
-- 'Nothing' otherwise.
--
-- @since 0.19.2
lookupString :: StringPool -> ES.String -> Maybe JsName.Name
lookupString (StringPool pool) str = Map.lookup str pool

-- INTERNAL: Counting

-- | Count string literals in a single node.
countNodeStrings :: Map ES.String Int -> Opt.Node -> Map ES.String Int
countNodeStrings acc node =
  case node of
    Opt.Define expr _ -> countExprStrings acc expr
    Opt.DefineTailFunc _ body _ -> countExprStrings acc body
    Opt.Cycle _ values functions _ ->
      let acc1 = foldl (\a (_, e) -> countExprStrings a e) acc values
       in foldl countDefStrings acc1 functions
    Opt.PortIncoming expr _ -> countExprStrings acc expr
    Opt.PortOutgoing expr _ -> countExprStrings acc expr
    _ -> acc

-- | Count string literals in a definition.
countDefStrings :: Map ES.String Int -> Opt.Def -> Map ES.String Int
countDefStrings acc def =
  case def of
    Opt.Def _ expr -> countExprStrings acc expr
    Opt.TailDef _ _ body -> countExprStrings acc body

-- | Recursively count string occurrences in an expression.
countExprStrings :: Map ES.String Int -> Opt.Expr -> Map ES.String Int
countExprStrings acc expr =
  case expr of
    Opt.Str s -> Map.insertWith (+) s 1 acc
    Opt.Function _ body -> countExprStrings acc body
    Opt.Call func args -> foldl countExprStrings (countExprStrings acc func) args
    Opt.ArithBinop _ l r -> countExprStrings (countExprStrings acc l) r
    Opt.TailCall _ pairs -> foldl (\a (_, e) -> countExprStrings a e) acc pairs
    Opt.If branches final ->
      let acc1 = foldl (\a (c, b) -> countExprStrings (countExprStrings a c) b) acc branches
       in countExprStrings acc1 final
    Opt.Let def body -> countDefStrings (countExprStrings acc body) def
    Opt.Destruct _ body -> countExprStrings acc body
    Opt.Case _ _ decider jumps ->
      let acc1 = countDeciderStrings acc decider
       in foldl (\a (_, e) -> countExprStrings a e) acc1 jumps
    Opt.Access rec _ -> countExprStrings acc rec
    Opt.Update rec fields -> Map.foldl' countExprStrings (countExprStrings acc rec) fields
    Opt.Record fields -> Map.foldl' countExprStrings acc fields
    Opt.List entries -> foldl countExprStrings acc entries
    Opt.Tuple a b mc ->
      let acc1 = countExprStrings (countExprStrings acc a) b
       in maybe acc1 (countExprStrings acc1) mc
    _ -> acc

-- | Count strings in a decision tree.
countDeciderStrings :: Map ES.String Int -> Opt.Decider Opt.Choice -> Map ES.String Int
countDeciderStrings acc decider =
  case decider of
    Opt.Leaf choice -> countChoiceStrings acc choice
    Opt.Chain _ success failure ->
      countDeciderStrings (countDeciderStrings acc success) failure
    Opt.FanOut _ tests fallback ->
      let acc1 = foldl (\a (_, d) -> countDeciderStrings a d) acc tests
       in countDeciderStrings acc1 fallback

-- | Count strings in a choice.
countChoiceStrings :: Map ES.String Int -> Opt.Choice -> Map ES.String Int
countChoiceStrings acc choice =
  case choice of
    Opt.Inline e -> countExprStrings acc e
    Opt.Jump _ -> acc

-- INTERNAL: Naming

-- | Generate pool variable name from index.
--
-- Produces @_s0@, @_s1@, @_s2@, etc.
poolVarName :: Int -> JsName.Name
poolVarName i = JsName.fromLocal (Name.fromChars ("_s" ++ show i))
