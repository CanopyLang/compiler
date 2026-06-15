
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
-- 'buildGlobalRenameMap' produces a mapping from reachable user globals
-- to short names for prod-mode global renaming. Only user-code globals
-- (present in the compiled graph, not from FFI alias modules) are renamed.
--
-- @since 0.19.2
module Generate.JavaScript.Minify
  ( minifyGraph,
    buildGlobalRenameMap,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Data.List as List
import Data.Set (Set)
import qualified Data.Set as Set

-- | Rename all local variables in a global graph to short names.
--
-- Each function scope gets independent short names starting from
-- counter 0, which produces @a@, @b@, @c@, etc.
--
-- The 'Set Name' argument is the set of GLOBAL short names assigned by
-- 'buildGlobalRenameMap'. Local renaming skips any name in this set so a
-- function-local @var a@ can never shadow a top-level global that the same
-- function references — which would otherwise turn @A2(a, ...)@ (a call to the
-- renamed global @Debug.log@) into a read of the still-uninitialised local
-- @a@, crashing under @--optimize@. (Globals and locals share the same
-- single-letter namespace; keeping them disjoint is the only way to guarantee
-- no shadow.)
--
-- @since 0.19.2
minifyGraph :: Set Name -> Map Opt.Global Opt.Node -> Map Opt.Global Opt.Node
minifyGraph reserved = Map.map (minifyNode reserved)

-- | Rename locals in a single dependency-graph node.
minifyNode :: Set Name -> Opt.Node -> Opt.Node
minifyNode reserved node =
  case node of
    Opt.Define expr deps ->
      Opt.Define (minifyTop reserved expr) deps
    Opt.DefineTailFunc argNames body deps ->
      let (scope, counter) = renameList reserved Map.empty 0 argNames
          renamedArgs = map (lookupRenamed scope) argNames
       in Opt.DefineTailFunc renamedArgs (minifyExpr reserved scope counter body) deps
    Opt.Cycle names values functions deps ->
      Opt.Cycle names (map (minifyNamedExpr reserved Map.empty 0) values) (map (minifyDef reserved) functions) deps
    Opt.PortIncoming expr deps ->
      Opt.PortIncoming (minifyTop reserved expr) deps
    Opt.PortOutgoing expr deps ->
      Opt.PortOutgoing (minifyTop reserved expr) deps
    _ -> node

-- | Minify a top-level expression (fresh scope).
minifyTop :: Set Name -> Opt.Expr -> Opt.Expr
minifyTop reserved = minifyExpr reserved Map.empty 0

-- | Minify a (name, expr) pair used in Cycle values.
minifyNamedExpr :: Set Name -> Map Name Name -> Int -> (Name, Opt.Expr) -> (Name, Opt.Expr)
minifyNamedExpr reserved scope counter (n, expr) = (n, minifyExpr reserved scope counter expr)

-- | Minify a definition (fresh scope for TailDef).
minifyDef :: Set Name -> Opt.Def -> Opt.Def
minifyDef reserved def =
  case def of
    Opt.Def n expr ->
      Opt.Def n (minifyTop reserved expr)
    Opt.TailDef n args body ->
      let (scope, counter) = renameList reserved Map.empty 0 args
          renamedArgs = map (lookupRenamed scope) args
       in Opt.TailDef n renamedArgs (minifyExpr reserved scope counter body)

-- | Rename locals in an expression within a scope.
minifyExpr :: Set Name -> Map Name Name -> Int -> Opt.Expr -> Opt.Expr
minifyExpr reserved scope counter expr =
  case expr of
    Opt.VarLocal n ->
      Opt.VarLocal (lookupRenamed scope n)
    Opt.Function args body ->
      let (innerScope, innerCounter) = renameList reserved scope counter args
          renamedArgs = map (lookupRenamed innerScope) args
       in Opt.Function renamedArgs (minifyExpr reserved innerScope innerCounter body)
    Opt.Call func callArgs ->
      Opt.Call (minifyExpr reserved scope counter func) (map (minifyExpr reserved scope counter) callArgs)
    Opt.ArithBinop op left right ->
      Opt.ArithBinop op (minifyExpr reserved scope counter left) (minifyExpr reserved scope counter right)
    Opt.TailCall n pairs ->
      Opt.TailCall (lookupRenamed scope n) (map (minifyTailPair reserved scope counter) pairs)
    Opt.If branches final ->
      Opt.If (map (minifyBranch reserved scope counter) branches) (minifyExpr reserved scope counter final)
    Opt.Let def body ->
      minifyLet reserved scope counter def body
    Opt.Destruct (Opt.Destructor n path) body ->
      let (short, newCounter) = freshName reserved scope counter n
          newScope = Map.insert n short scope
       in Opt.Destruct (Opt.Destructor short (minifyPath scope path)) (minifyExpr reserved newScope newCounter body)
    Opt.Case inputName resultName decider jumps ->
      -- Both inputName and resultName refer to variables already in scope
      -- (function parameters or let-bound values).  Calling freshName twice
      -- for the same variable would advance the counter twice and let the
      -- second write clobber the first, causing the decider to reference an
      -- undefined variable.  Use lookupRenamed to reuse existing short names.
      let shortInput = lookupRenamed scope inputName
          shortResult = lookupRenamed scope resultName
          newScope = Map.insert resultName shortResult (Map.insert inputName shortInput scope)
       in Opt.Case shortInput shortResult (minifyDecider reserved newScope counter decider) (map (minifyJump reserved newScope counter) jumps)
    Opt.Access rec field ->
      Opt.Access (minifyExpr reserved scope counter rec) field
    Opt.Update rec fields ->
      Opt.Update (minifyExpr reserved scope counter rec) (Map.map (minifyExpr reserved scope counter) fields)
    Opt.Record fields ->
      Opt.Record (Map.map (minifyExpr reserved scope counter) fields)
    Opt.List entries ->
      Opt.List (map (minifyExpr reserved scope counter) entries)
    Opt.Tuple a b mc ->
      Opt.Tuple (minifyExpr reserved scope counter a) (minifyExpr reserved scope counter b) (fmap (minifyExpr reserved scope counter) mc)
    _ -> expr

-- | Minify a let-binding and its body.
minifyLet :: Set Name -> Map Name Name -> Int -> Opt.Def -> Opt.Expr -> Opt.Expr
minifyLet reserved scope counter def body =
  case def of
    Opt.Def n defExpr ->
      let (short, newCounter) = freshName reserved scope counter n
          newScope = Map.insert n short scope
       in Opt.Let (Opt.Def short (minifyExpr reserved scope counter defExpr)) (minifyExpr reserved newScope newCounter body)
    Opt.TailDef n args defBody ->
      let (shortN, c1) = freshName reserved scope counter n
          scopeWithN = Map.insert n shortN scope
          (innerScope, innerC) = renameList reserved scopeWithN c1 args
          renamedArgs = map (lookupRenamed innerScope) args
       in Opt.Let (Opt.TailDef shortN renamedArgs (minifyExpr reserved innerScope innerC defBody)) (minifyExpr reserved scopeWithN c1 body)

-- | Minify a tail-call argument pair.
minifyTailPair :: Set Name -> Map Name Name -> Int -> (Name, Opt.Expr) -> (Name, Opt.Expr)
minifyTailPair reserved scope counter (n, e) =
  (lookupRenamed scope n, minifyExpr reserved scope counter e)

-- | Minify an if-branch pair.
minifyBranch :: Set Name -> Map Name Name -> Int -> (Opt.Expr, Opt.Expr) -> (Opt.Expr, Opt.Expr)
minifyBranch reserved scope counter (cond, branch) =
  (minifyExpr reserved scope counter cond, minifyExpr reserved scope counter branch)

-- | Minify a jump (index, expression) pair.
minifyJump :: Set Name -> Map Name Name -> Int -> (Int, Opt.Expr) -> (Int, Opt.Expr)
minifyJump reserved scope counter (idx, e) = (idx, minifyExpr reserved scope counter e)

-- | Minify a path (only Root names are renamed).
minifyPath :: Map Name Name -> Opt.Path -> Opt.Path
minifyPath scope path =
  case path of
    Opt.Root n -> Opt.Root (lookupRenamed scope n)
    Opt.Index i sub -> Opt.Index i (minifyPath scope sub)
    Opt.Field n sub -> Opt.Field n (minifyPath scope sub)
    Opt.Unbox sub -> Opt.Unbox (minifyPath scope sub)

-- | Minify a decision tree.
minifyDecider :: Set Name -> Map Name Name -> Int -> Opt.Decider Opt.Choice -> Opt.Decider Opt.Choice
minifyDecider reserved scope counter decider =
  case decider of
    Opt.Leaf choice -> Opt.Leaf (minifyChoice reserved scope counter choice)
    Opt.Chain tests success failure ->
      Opt.Chain tests (minifyDecider reserved scope counter success) (minifyDecider reserved scope counter failure)
    Opt.FanOut path tests fallback ->
      Opt.FanOut path (map (\(t, d) -> (t, minifyDecider reserved scope counter d)) tests) (minifyDecider reserved scope counter fallback)

-- | Minify a choice in a decision tree.
minifyChoice :: Set Name -> Map Name Name -> Int -> Opt.Choice -> Opt.Choice
minifyChoice reserved scope counter choice =
  case choice of
    Opt.Inline e -> Opt.Inline (minifyExpr reserved scope counter e)
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
--
-- Skips any name in the GLOBAL reserved set so a local can never shadow a
-- top-level global short name (see 'minifyGraph').
freshName :: Set Name -> Map Name Name -> Int -> Name -> (Name, Int)
freshName reserved _scope counter _original =
  let candidate = shortName counter
   in if Set.member candidate reserved
        then freshName reserved _scope (counter + 1) _original
        else (candidate, counter + 1)

-- | Rename a list of names, threading the counter.
renameList :: Set Name -> Map Name Name -> Int -> [Name] -> (Map Name Name, Int)
renameList _reserved scope counter [] = (scope, counter)
renameList reserved scope counter (n : ns) =
  let (short, newCounter) = freshName reserved scope counter n
      newScope = Map.insert n short scope
   in renameList reserved newScope newCounter ns

-- | Look up a renamed name; return the original if not in scope.
lookupRenamed :: Map Name Name -> Name -> Name
lookupRenamed scope n = Map.findWithDefault n n scope


-- GLOBAL RENAMING

-- | Build a mapping from reachable user globals to short JS names.
--
-- Only renames globals present in the compiled graph whose home module
-- is not an FFI alias module. Kernel and FFI globals keep their mangled
-- names for runtime\/FFI compatibility.
--
-- The result is used in production mode to replace long mangled global
-- names (@$author$project$Module$func@) with short names (@a@, @b@, …).
--
-- @since 0.20.4
buildGlobalRenameMap
  :: Set Name         -- ^ FFI alias module names (excluded from renaming)
  -> Map Opt.Global Opt.Node  -- ^ Full compiled graph (only user globals present)
  -> Set Opt.Global   -- ^ Reachable globals
  -> Map Opt.Global Name
buildGlobalRenameMap ffiAliases graph reachable =
  Map.fromList (zip userGlobals (globalShortNames 0))
  where
    userGlobals = List.sortOn globalSortKey (filter isUserGlobal (Set.toList reachable))
    isUserGlobal g@(Opt.Global home _) =
      Map.member g graph
      && not (Set.member (ModuleName._module home) ffiAliases)
    globalSortKey (Opt.Global home name) =
      (Name.toChars (ModuleName._module home), Name.toChars name)

-- | Infinite sequence of valid short names, skipping JS reserved words.
--
-- Generates names in the same order as 'shortNameChars' (a, b, …, z, aa, …)
-- but filters out any name that collides with JavaScript reserved words or
-- the Canopy F\/A arity helpers (F2–F9, A2–A9).
globalShortNames :: Int -> [Name]
globalShortNames n =
  let candidate = Name.fromChars (shortNameChars n)
  in if Set.member candidate globalReservedNames
       then globalShortNames (n + 1)
       else candidate : globalShortNames (n + 1)

-- | Names that must not be used as global short names.
--
-- Includes the Canopy F\/A helpers and common single-letter JS identifiers
-- that conflict with runtime or built-in names. Does not include the full
-- JS reserved-word set because 'shortNameChars' only produces lowercase
-- letters, and lowercase reserved words (do, if, in, for, …) are excluded
-- here explicitly.
{-# NOINLINE globalReservedNames #-}
globalReservedNames :: Set Name
globalReservedNames =
  Set.fromList (map Name.fromChars
    [ "do", "if", "in"
    , "for", "let", "new", "try", "var"
    , "case", "else", "this", "void", "with"
    , "break", "catch", "class", "const", "super", "throw", "while", "yield"
    , "delete", "return", "switch", "typeof"
    , "default", "extends"
    , "finally", "continue"
    , "debugger", "function"
    , "instanceof"
    ])
