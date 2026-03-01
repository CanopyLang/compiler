
-- | Local variable minification for production builds.
--
-- In production mode, renames local variables (function parameters,
-- let-bindings, destructured names) to short single-character names
-- (@a@, @b@, @c@, ..., @z@, @aa@, @ab@, ...). Each function scope
-- gets an independent counter, so inner functions reuse short names.
--
-- Global references, kernel references, and cycle references are
-- never renamed — only 'Opt.VarLocal', 'Opt.Function' parameters,
-- 'Opt.Let' bindings, 'Opt.Destruct' targets, 'Opt.TailCall' args,
-- and 'Opt.Case' names are affected.
--
-- @since 0.19.2
module Generate.JavaScript.Minify
  ( minifyGraph,
  )
where

import qualified AST.Optimized as Opt
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name

-- | Rename all local variables in a global graph to short names.
--
-- Each function scope gets independent short names starting from
-- counter 0, which produces @a@, @b@, @c@, etc.
--
-- @since 0.19.2
minifyGraph :: Map Opt.Global Opt.Node -> Map Opt.Global Opt.Node
minifyGraph = Map.map minifyNode

-- | Rename locals in a single dependency-graph node.
minifyNode :: Opt.Node -> Opt.Node
minifyNode node =
  case node of
    Opt.Define expr deps ->
      Opt.Define (minifyTop expr) deps
    Opt.DefineTailFunc argNames body deps ->
      let (scope, counter) = renameList Map.empty 0 argNames
          renamedArgs = map (lookupRenamed scope) argNames
       in Opt.DefineTailFunc renamedArgs (minifyExpr scope counter body) deps
    Opt.Cycle names values functions deps ->
      Opt.Cycle names (map (minifyNamedExpr Map.empty 0) values) (map minifyDef functions) deps
    Opt.PortIncoming expr deps ->
      Opt.PortIncoming (minifyTop expr) deps
    Opt.PortOutgoing expr deps ->
      Opt.PortOutgoing (minifyTop expr) deps
    _ -> node

-- | Minify a top-level expression (fresh scope).
minifyTop :: Opt.Expr -> Opt.Expr
minifyTop = minifyExpr Map.empty 0

-- | Minify a (name, expr) pair used in Cycle values.
minifyNamedExpr :: Map Name Name -> Int -> (Name, Opt.Expr) -> (Name, Opt.Expr)
minifyNamedExpr scope counter (n, expr) = (n, minifyExpr scope counter expr)

-- | Minify a definition (fresh scope for TailDef).
minifyDef :: Opt.Def -> Opt.Def
minifyDef def =
  case def of
    Opt.Def n expr ->
      Opt.Def n (minifyTop expr)
    Opt.TailDef n args body ->
      let (scope, counter) = renameList Map.empty 0 args
          renamedArgs = map (lookupRenamed scope) args
       in Opt.TailDef n renamedArgs (minifyExpr scope counter body)

-- | Rename locals in an expression within a scope.
minifyExpr :: Map Name Name -> Int -> Opt.Expr -> Opt.Expr
minifyExpr scope counter expr =
  case expr of
    Opt.VarLocal n ->
      Opt.VarLocal (lookupRenamed scope n)
    Opt.Function args body ->
      let (innerScope, innerCounter) = renameList scope counter args
          renamedArgs = map (lookupRenamed innerScope) args
       in Opt.Function renamedArgs (minifyExpr innerScope innerCounter body)
    Opt.Call func callArgs ->
      Opt.Call (minifyExpr scope counter func) (map (minifyExpr scope counter) callArgs)
    Opt.ArithBinop op left right ->
      Opt.ArithBinop op (minifyExpr scope counter left) (minifyExpr scope counter right)
    Opt.TailCall n pairs ->
      Opt.TailCall (lookupRenamed scope n) (map (minifyTailPair scope counter) pairs)
    Opt.If branches final ->
      Opt.If (map (minifyBranch scope counter) branches) (minifyExpr scope counter final)
    Opt.Let def body ->
      minifyLet scope counter def body
    Opt.Destruct (Opt.Destructor n path) body ->
      let (short, newCounter) = freshName scope counter n
          newScope = Map.insert n short scope
       in Opt.Destruct (Opt.Destructor short (minifyPath scope path)) (minifyExpr newScope newCounter body)
    Opt.Case inputName resultName decider jumps ->
      let (shortInput, c1) = freshName scope counter inputName
          (shortResult, c2) = freshName (Map.insert inputName shortInput scope) c1 resultName
          newScope = Map.insert resultName shortResult (Map.insert inputName shortInput scope)
       in Opt.Case shortInput shortResult (minifyDecider newScope c2 decider) (map (minifyJump newScope c2) jumps)
    Opt.Access rec field ->
      Opt.Access (minifyExpr scope counter rec) field
    Opt.Update rec fields ->
      Opt.Update (minifyExpr scope counter rec) (Map.map (minifyExpr scope counter) fields)
    Opt.Record fields ->
      Opt.Record (Map.map (minifyExpr scope counter) fields)
    Opt.List entries ->
      Opt.List (map (minifyExpr scope counter) entries)
    Opt.Tuple a b mc ->
      Opt.Tuple (minifyExpr scope counter a) (minifyExpr scope counter b) (fmap (minifyExpr scope counter) mc)
    _ -> expr

-- | Minify a let-binding and its body.
minifyLet :: Map Name Name -> Int -> Opt.Def -> Opt.Expr -> Opt.Expr
minifyLet scope counter def body =
  case def of
    Opt.Def n defExpr ->
      let (short, newCounter) = freshName scope counter n
          newScope = Map.insert n short scope
       in Opt.Let (Opt.Def short (minifyExpr scope counter defExpr)) (minifyExpr newScope newCounter body)
    Opt.TailDef n args defBody ->
      let (shortN, c1) = freshName scope counter n
          scopeWithN = Map.insert n shortN scope
          (innerScope, innerC) = renameList scopeWithN c1 args
          renamedArgs = map (lookupRenamed innerScope) args
       in Opt.Let (Opt.TailDef shortN renamedArgs (minifyExpr innerScope innerC defBody)) (minifyExpr scopeWithN c1 body)

-- | Minify a tail-call argument pair.
minifyTailPair :: Map Name Name -> Int -> (Name, Opt.Expr) -> (Name, Opt.Expr)
minifyTailPair scope counter (n, e) =
  (lookupRenamed scope n, minifyExpr scope counter e)

-- | Minify an if-branch pair.
minifyBranch :: Map Name Name -> Int -> (Opt.Expr, Opt.Expr) -> (Opt.Expr, Opt.Expr)
minifyBranch scope counter (cond, branch) =
  (minifyExpr scope counter cond, minifyExpr scope counter branch)

-- | Minify a jump (index, expression) pair.
minifyJump :: Map Name Name -> Int -> (Int, Opt.Expr) -> (Int, Opt.Expr)
minifyJump scope counter (idx, e) = (idx, minifyExpr scope counter e)

-- | Minify a path (only Root names are renamed).
minifyPath :: Map Name Name -> Opt.Path -> Opt.Path
minifyPath scope path =
  case path of
    Opt.Root n -> Opt.Root (lookupRenamed scope n)
    Opt.Index i sub -> Opt.Index i (minifyPath scope sub)
    Opt.Field n sub -> Opt.Field n (minifyPath scope sub)
    Opt.Unbox sub -> Opt.Unbox (minifyPath scope sub)

-- | Minify a decision tree.
minifyDecider :: Map Name Name -> Int -> Opt.Decider Opt.Choice -> Opt.Decider Opt.Choice
minifyDecider scope counter decider =
  case decider of
    Opt.Leaf choice -> Opt.Leaf (minifyChoice scope counter choice)
    Opt.Chain tests success failure ->
      Opt.Chain tests (minifyDecider scope counter success) (minifyDecider scope counter failure)
    Opt.FanOut path tests fallback ->
      Opt.FanOut path (map (\(t, d) -> (t, minifyDecider scope counter d)) tests) (minifyDecider scope counter fallback)

-- | Minify a choice in a decision tree.
minifyChoice :: Map Name Name -> Int -> Opt.Choice -> Opt.Choice
minifyChoice scope counter choice =
  case choice of
    Opt.Inline e -> Opt.Inline (minifyExpr scope counter e)
    Opt.Jump i -> Opt.Jump i

-- NAMING

-- | Generate a short name from a counter.
--
-- Uses the same scheme as 'Generate.JavaScript.Name.intToAscii':
-- 0->a, 1->b, ..., 25->z, 26->aa, 27->ab, ...
--
-- Builds the character list directly without intermediate Name
-- conversions to avoid allocation round-trips.
shortName :: Int -> Name
shortName n = Name.fromChars (shortNameChars n)

-- | Compute the character list for a short name index.
shortNameChars :: Int -> String
shortNameChars n
  | n < 26 = [toEnum (fromEnum 'a' + n)]
  | otherwise =
      let (q, r) = divMod n 26
       in shortNameChars (q - 1) ++ [toEnum (fromEnum 'a' + r)]

-- | Allocate a fresh short name for an original name.
-- Returns the short name and the incremented counter.
freshName :: Map Name Name -> Int -> Name -> (Name, Int)
freshName _scope counter _original =
  (shortName counter, counter + 1)

-- | Rename a list of names, threading the counter.
renameList :: Map Name Name -> Int -> [Name] -> (Map Name Name, Int)
renameList scope counter [] = (scope, counter)
renameList scope counter (n : ns) =
  let (short, newCounter) = freshName scope counter n
      newScope = Map.insert n short scope
   in renameList newScope newCounter ns

-- | Look up a renamed name; return the original if not in scope.
lookupRenamed :: Map Name Name -> Name -> Name
lookupRenamed scope n = Map.findWithDefault n n scope
