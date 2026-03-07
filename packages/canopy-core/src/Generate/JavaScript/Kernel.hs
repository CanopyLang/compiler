{-# LANGUAGE OverloadedStrings #-}

-- | Generate.JavaScript.Kernel - Kernel, cycle, enum, box, port, and export generation
--
-- This module handles the JavaScript code generation for:
--
-- * Kernel chunks (raw JS, variable references, field accesses)
-- * Value cycles (mutually recursive definitions)
-- * Enum constructors (zero-arity)
-- * Box constructors (identity wrappers)
-- * Port declarations (incoming/outgoing)
-- * Effect manager helpers
-- * Main export trie construction
--
-- It is a sub-module of "Generate.JavaScript" and is imported from there.
-- Users should import "Generate.JavaScript" rather than this module directly.
--
-- @since 0.19.1
module Generate.JavaScript.Kernel
  ( -- * Kernel Generation
    generateKernel,
    addChunk,

    -- * Cycle Generation
    generateCycle,
    generateCycleFunc,
    generateSafeCycle,
    generateRealCycle,
    drawCycle,

    -- * Node Type Generation
    generateEnum,
    generateBox,
    generatePort,
    generateManagerHelp,
    generateLeaf,
    identity,
    isDebugger,

    -- * Export Trie Generation
    toMainExports,
    generateExports,
    addSubTrie,
    Trie (..),
    emptyTrie,
    addToTrie,
    segmentsToTrie,
    merge,
    checkedMerge,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as Kernel
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Canopy.Data.Index as Index
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import qualified Reporting.Doc as Doc
import qualified Reporting.InternalError as InternalError

-- KERNEL GENERATION

-- | Generate JavaScript for a sequence of kernel chunks.
--
-- @since 0.19.1
generateKernel :: Mode.Mode -> [Kernel.Chunk] -> Builder
generateKernel mode = List.foldr (addChunk mode) mempty

-- | Add a single kernel chunk to the output builder.
--
-- @since 0.19.1
addChunk :: Mode.Mode -> Kernel.Chunk -> Builder -> Builder
addChunk mode chunk builder =
  case chunk of
    Kernel.JS javascript ->
      BB.byteString javascript <> builder
    Kernel.CanopyVar home name ->
      JsName.toBuilder (JsName.fromGlobal home name) <> builder
    Kernel.JsVar home name ->
      JsName.toBuilder (JsName.fromKernel home name) <> builder
    Kernel.CanopyField name ->
      JsName.toBuilder (Expr.generateField mode name) <> builder
    Kernel.JsField int ->
      JsName.toBuilder (JsName.fromInt int) <> builder
    Kernel.JsEnum int ->
      BB.intDec int <> builder
    Kernel.Debug ->
      case mode of
        Mode.Dev _ _ _ _ _ _ -> builder
        Mode.Prod {} -> "_UNUSED" <> builder
    Kernel.Prod ->
      case mode of
        Mode.Dev _ _ _ _ _ _ -> "_UNUSED" <> builder
        Mode.Prod {} -> builder

-- CYCLE GENERATION

-- | Generate JavaScript for a mutually-recursive cycle of definitions.
--
-- @since 0.19.1
generateCycle :: Mode.Mode -> Opt.Global -> [Name.Name] -> [(Name.Name, Opt.Expr)] -> [Opt.Def] -> JS.Stmt
generateCycle mode (Opt.Global home _) names values functions =
  let functionStmts = fmap (generateCycleFunc mode home) functions
      safeStmts = fmap (generateSafeCycle mode home) values
      realStmts = buildRealStmts mode home names values
      allStmts = functionStmts ++ safeStmts ++ realStmts
  in case allStmts of
       [singleStmt] -> singleStmt
       _ -> JS.Block allStmts

buildRealStmts :: Mode.Mode -> ModuleName.Canonical -> [Name.Name] -> [(Name.Name, Opt.Expr)] -> [JS.Stmt]
buildRealStmts mode home names values =
  case fmap (generateRealCycle home) values of
    [] -> []
    realBlock@(_ : _) ->
      case mode of
        Mode.Prod {} -> realBlock
        Mode.Dev _ _ _ _ _ _ ->
          [(JS.Try (JS.Block realBlock) JsName.dollar . JS.Throw) . JS.String $
            ( "Some top-level definitions from `" <> Name.toBuilder (ModuleName._module home) <> "` are causing infinite recursion:\\n"
                <> drawCycle names
                <> "\\n\\nThese errors are very tricky, so read "
                <> BB.stringUtf8 (Doc.makeNakedLink "bad-recursion")
                <> " to learn how to fix it!"
            )]

-- | Generate JavaScript for a single cycle function definition.
--
-- @since 0.19.1
generateCycleFunc :: Mode.Mode -> ModuleName.Canonical -> Opt.Def -> JS.Stmt
generateCycleFunc mode home def =
  case def of
    Opt.Def name expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr (Expr.generate mode expr))
    Opt.TailDef name args expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name args expr)

-- | Generate JavaScript for the safe (thunked) version of a cycle value.
--
-- @since 0.19.1
generateSafeCycle :: Mode.Mode -> ModuleName.Canonical -> (Name.Name, Opt.Expr) -> JS.Stmt
generateSafeCycle mode home (name, expr) =
  JS.FunctionStmt (JsName.fromCycle home name) [] $
    Expr.codeToStmtList (Expr.generate mode expr)

-- | Generate JavaScript to replace a safe cycle thunk with the real value.
--
-- @since 0.19.1
generateRealCycle :: ModuleName.Canonical -> (Name.Name, expr) -> JS.Stmt
generateRealCycle home (name, _) =
  let safeName = JsName.fromCycle home name
      realName = JsName.fromGlobal home name
   in JS.Block
        [ JS.Var realName (JS.Call (JS.Ref safeName) []),
          JS.ExprStmt . JS.Assign (JS.LRef safeName) $ JS.Function Nothing [] [JS.Return (JS.Ref realName)]
        ]

-- | Render a list of mutually-recursive names as a cycle diagram.
--
-- @since 0.19.1
drawCycle :: [Name.Name] -> Builder
drawCycle names =
  let topLine = "\\n  ┌─────┐"
      nameLine name = "\\n  │    " <> Name.toBuilder name
      midLine = "\\n  │     ↓"
      bottomLine = "\\n  └─────┘"
   in mconcat (topLine : (List.intersperse midLine (fmap nameLine names) <> [bottomLine]))

-- NODE TYPE GENERATION

-- | Generate JavaScript for an enum (zero-arity constructor).
--
-- @since 0.19.1
generateEnum :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> JS.Stmt
generateEnum mode global@(Opt.Global home name) index =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ _ _ _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global index 0)
      Mode.Prod {} ->
        JS.Int (Index.toMachine index)

-- | Generate JavaScript for a box (identity wrapper constructor).
--
-- @since 0.19.1
generateBox :: Mode.Mode -> Opt.Global -> JS.Stmt
generateBox mode global@(Opt.Global home name) =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ _ _ _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global Index.first 1)
      Mode.Prod {} ->
        JS.Ref (JsName.fromGlobal ModuleName.basics Name.identity)

-- | The identity global, shared between 'generateBox' usages.
--
-- @since 0.19.1
{-# NOINLINE identity #-}
identity :: Opt.Global
identity =
  Opt.Global ModuleName.basics Name.identity

-- | Generate JavaScript for a port declaration.
--
-- @since 0.19.1
generatePort :: Mode.Mode -> Opt.Global -> Name.Name -> Opt.Expr -> JS.Stmt
generatePort mode (Opt.Global home name) makePort converter =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call
      (JS.Ref (JsName.fromKernel Name.platform makePort))
      [ JS.String (Name.toBuilder name),
        Expr.codeToExpr (Expr.generate mode converter)
      ]

-- | Generate JavaScript for a leaf effect (Cmd or Sub).
--
-- @since 0.19.1
generateLeaf :: ModuleName.Canonical -> Name.Name -> JS.Stmt
generateLeaf home@(ModuleName.Canonical _ moduleName) name =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call leaf [JS.String (Name.toBuilder moduleName)]

{-# NOINLINE leaf #-}
leaf :: JS.Expr
leaf =
  JS.Ref (JsName.fromKernel Name.platform "leaf")

-- | Build the dependency list, argument list, and additional statements
-- for registering an effect manager.
--
-- @since 0.19.1
generateManagerHelp :: ModuleName.Canonical -> Opt.EffectsType -> ([Opt.Global], [JS.Expr], [JS.Stmt])
generateManagerHelp home effectsType =
  let ref name = JS.Ref (JsName.fromGlobal home name)
      dep = Opt.Global home
   in case effectsType of
        Opt.Cmd ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap"],
            [generateLeaf home "command"]
          )
        Opt.Sub ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", JS.Int 0, ref "subMap"],
            [generateLeaf home "subscription"]
          )
        Opt.Fx ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap", ref "subMap"],
            [ generateLeaf home "command",
              generateLeaf home "subscription"
            ]
          )

-- | Check whether a global belongs to the debugger module.
--
-- @since 0.19.1
isDebugger :: Opt.Global -> Bool
isDebugger (Opt.Global (ModuleName.Canonical _ home) _) =
  home == Name.debugger

-- EXPORT TRIE

-- | Trie structure for module name segmentation into JavaScript exports.
--
-- @since 0.19.1
data Trie = Trie
  { _main :: Maybe (ModuleName.Canonical, Opt.Main),
    _subs :: Map Name.Name Trie
  }

-- | Empty trie with no mains and no sub-segments.
--
-- @since 0.19.1
emptyTrie :: Trie
emptyTrie =
  Trie Nothing Map.empty

-- | Generate the top-level export call and set @scope['Canopy']@.
--
-- @since 0.19.1
toMainExports :: Mode.Mode -> Map ModuleName.Canonical Opt.Main -> Builder
toMainExports mode mains =
  let export = JsName.fromKernel Name.platform "export"
      exports = generateExports mode (Map.foldrWithKey addToTrie emptyTrie mains)
   in JsName.toBuilder export <> "(" <> exports <> ");"
        <> "scope['Canopy'] = scope['Elm'];"

-- | Render a trie of mains as a nested JavaScript object literal.
--
-- @since 0.19.1
generateExports :: Mode.Mode -> Trie -> Builder
generateExports mode (Trie maybeMain subs) =
  let starter end =
        case maybeMain of
          Nothing ->
            "{"
          Just (home, main) ->
            "{'init':"
              <> JS.exprToBuilder (Expr.generateMain mode home main)
              <> end
   in case Map.toList subs of
        [] ->
          starter "" <> "}"
        (name, subTrie) : otherSubTries ->
          starter ","
            <> "'"
            <> Utf8.toBuilder name
            <> "':"
            <> generateExports mode subTrie
            <> List.foldl' (addSubTrie mode) "}" otherSubTries

-- | Append a sub-trie entry to a builder accumulator.
--
-- @since 0.19.1
addSubTrie :: Mode.Mode -> Builder -> (Name.Name, Trie) -> Builder
addSubTrie mode end (name, trie) =
  ",'" <> Utf8.toBuilder name <> "':" <> generateExports mode trie <> end

-- | Insert a module into the trie using its dot-separated name segments.
--
-- @since 0.19.1
addToTrie :: ModuleName.Canonical -> Opt.Main -> Trie -> Trie
addToTrie home@(ModuleName.Canonical _ moduleName) main trie =
  merge trie $ segmentsToTrie home (Name.splitDots moduleName) main

-- | Build a trie from a list of name segments and a main.
--
-- @since 0.19.1
segmentsToTrie :: ModuleName.Canonical -> [Name.Name] -> Opt.Main -> Trie
segmentsToTrie home segments main =
  case segments of
    [] ->
      Trie (Just (home, main)) Map.empty
    segment : otherSegments ->
      Trie Nothing (Map.singleton segment (segmentsToTrie home otherSegments main))

-- | Merge two tries, failing if two mains share the same path.
--
-- @since 0.19.1
merge :: Trie -> Trie -> Trie
merge (Trie main1 subs1) (Trie main2 subs2) =
  Trie
    (checkedMerge main1 main2)
    (Map.unionWith merge subs1 subs2)

-- | Merge two @Maybe@ mains, reporting an internal error on conflict.
--
-- @since 0.19.1
checkedMerge :: Maybe a -> Maybe a -> Maybe a
checkedMerge a b =
  case (a, b) of
    (Nothing, main) ->
      main
    (main, Nothing) ->
      main
    (Just _, Just _) ->
      InternalError.report
        "Generate.JavaScript.checkedMerge"
        "Two modules share the same name"
        "This is an internal compiler error — the same module name was registered twice in the export trie."
