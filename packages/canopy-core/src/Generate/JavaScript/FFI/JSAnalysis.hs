{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | AST-based free-variable analysis for FFI JavaScript tree-shaking.
--
-- Replaces the byte-level string scanner in @Registry.hs@ with a proper
-- @language-javascript@ AST analysis. This eliminates false dependencies
-- caused by string literals: @args[\'node\']@ was previously scanned as
-- a reference to the top-level @var node = ...@ declaration, pulling in
-- 52 blocks instead of the correct ~8 for a hello-world app.
--
-- The analysis is scope-aware: function parameters and @var@-hoisted
-- names within a function body are treated as locally bound and excluded
-- from the free-variable set.
--
-- @since 0.20.3
module Generate.JavaScript.FFI.JSAnalysis
  ( -- * Types
    BlockGroup (..)

    -- * Parsing
  , parseBlockGroups
  , parseAllGroups

    -- * Free-variable analysis
  , freeVarsInGroup
  , allFreeVarsInGroup

    -- * Arity analysis
  , aritiesInGroup

    -- * Group utilities
  , groupDeclNames
  ) where

import Data.ByteString (ByteString)
import qualified Data.Set as Set
import Data.Set (Set)
import qualified Data.Text as Text
import FFI.StaticAnalysis (commaListToList, trailingListToList)
import qualified Language.JavaScript.Parser as JS
import Language.JavaScript.Parser.AST
  ( JSAnnot (..)
  , JSArrayElement (..)
  , JSBlock (..)
  , JSCommaList
  , JSAST (..)
  , JSExpression (..)
  , JSIdent (..)
  , JSObjectProperty (..)
  , JSStatement (..)
  , JSSwitchParts (..)
  , JSVarInitializer (..)
  )
import qualified Language.JavaScript.Parser.AST as JSAST
import Language.JavaScript.Parser.SrcLocation (TokenPosn (..))


-- TYPES

-- | A top-level declaration group in an FFI JS file.
--
-- Groups the named declaration together with any immediately following
-- non-declaration statements (e.g. @_VirtualDom_renderFns[x] = f@
-- which follows the @nodeNS@ var declaration in virtual-dom.js).
data BlockGroup = BlockGroup
  { _bgName       :: !ByteString
    -- ^ Primary declared name (@var X@ or @function X@).
  , _bgStatements :: ![JSStatement]
    -- ^ The declaration plus trailing non-decl statements.
  , _bgLine       :: !Int
    -- ^ 0-indexed line number of the declaration in the source file.
  }


-- PARSING

-- | Parse an FFI file, returning the full program statements and block groups.
--
-- Returns 'Nothing' on parse failure. The full statement list includes ALL
-- top-level statements (including non-declarations), while the block groups
-- contain only named declarations with their trailing statements.
--
-- Having both in one parse avoids a second round-trip when the caller needs
-- the complete AST for the non-tree-shaken fallback path.
parseAllGroups :: Text.Text -> Maybe ([JSStatement], [BlockGroup])
parseAllGroups content =
  case JS.parse (Text.unpack content) "<ffi>" of
    Left _                    -> Nothing
    Right (JSAstProgram ss _) -> Just (ss, groupStmts ss)
    Right _                   -> Nothing

-- | Parse an FFI JavaScript file into a list of top-level declaration groups.
--
-- Returns 'Nothing' on parse failure; the caller degrades gracefully by
-- emitting the full file without tree-shaking.
--
-- Each top-level @var@ or @function@ declaration starts a new group.
-- Statements between two consecutive declarations belong to the preceding
-- group.
parseBlockGroups :: Text.Text -> Maybe [BlockGroup]
parseBlockGroups content = fmap snd (parseAllGroups content)

-- | Group a flat list of statements into declaration groups.
groupStmts :: [JSStatement] -> [BlockGroup]
groupStmts [] = []
groupStmts (s : rest) =
  case declNameAndLine s of
    Nothing       -> groupStmts rest
    Just (nm, ln) ->
      BlockGroup nm (s : trailing) ln : groupStmts remaining
  where
    (trailing, remaining) = span isNonDecl rest
    isNonDecl stmt = maybe True (const False) (declNameAndLine stmt)

-- | Extract the declared name and 0-indexed line from a top-level declaration.
declNameAndLine :: JSStatement -> Maybe (ByteString, Int)
declNameAndLine = \case
  JSFunction annot (JSIdentName _ nm) _ _ _ _ _ ->
    Just (nm, annotLine0 annot)
  JSVariable annot declList _ ->
    fmap (\nm -> (nm, annotLine0 annot)) (varDeclFirstName declList)
  _ -> Nothing

-- | Convert a 1-indexed 'JSAnnot' line number to a 0-indexed line index.
annotLine0 :: JSAnnot -> Int
annotLine0 (JSAnnot (TokenPn _ line _) _) = max 0 (line - 1)
annotLine0 _ = 0


-- FREE-VARIABLE ANALYSIS

-- | Compute free variables in a block group restricted to a name set.
--
-- Returns the subset of @allNames@ that the group's statements reference
-- as free identifiers — i.e., identifiers that are neither locally bound
-- within the group nor equal to the group's own declared name.
--
-- This is the core of scope-aware dependency computation: string literals
-- are AST nodes with no free variables, so @args[\'node\']@ never produces
-- a spurious dependency on @var node = ...@.
freeVarsInGroup :: Set ByteString -> [JSStatement] -> Set ByteString
freeVarsInGroup allNames stmts =
  Set.intersection allNames (refsInStmts Set.empty stmts)

-- | All free identifiers in a block group, without filtering by a name set.
--
-- Used for cross-file dependency resolution, where we need references that
-- might be defined in other FFI files (and thus not in the local 'allNames').
allFreeVarsInGroup :: [JSStatement] -> Set ByteString
allFreeVarsInGroup = refsInStmts Set.empty

-- | Collect all free identifier references in a list of statements.
refsInStmts :: Set ByteString -> [JSStatement] -> Set ByteString
refsInStmts bound = foldMap (refsInStmt bound)

-- | Collect free identifier references in a single statement.
refsInStmt :: Set ByteString -> JSStatement -> Set ByteString
refsInStmt bound = \case
  JSVariable _ declList _ ->
    foldMap (refsInVarInitExpr bound) (commaListToList declList)
  JSFunction _ _ _ params _ block _ ->
    refsInFunctionBody bound params block
  JSExpressionStatement expr _ -> refsInExpr bound expr
  JSAssignStatement lhs _ rhs _ -> refsInExpr bound lhs <> refsInExpr bound rhs
  JSMethodCall callee _ args _ _ -> refsInExpr bound callee <> refsInArgs bound args
  JSReturn _ maybeExpr _ -> foldMap (refsInExpr bound) maybeExpr
  JSStatementBlock _ stmts _ _ -> refsInStmts bound stmts
  JSIf _ _ cond _ body -> refsInExpr bound cond <> refsInStmt bound body
  JSIfElse _ _ cond _ t _ e ->
    refsInExpr bound cond <> refsInStmt bound t <> refsInStmt bound e
  JSWhile _ _ cond _ body -> refsInExpr bound cond <> refsInStmt bound body
  JSDoWhile _ body _ _ cond _ _ -> refsInStmt bound body <> refsInExpr bound cond
  JSTry _ (JSBlock _ ss _) catches _ ->
    refsInStmts bound ss <> foldMap (refsInCatch bound) catches
  JSSwitch _ _ switchExpr _ _ cases _ _ ->
    refsInExpr bound switchExpr <> foldMap (refsInSwitchPart bound) cases
  stmt -> refsInForLike bound stmt

-- | Collect free references in a switch case/default arm.
refsInSwitchPart :: Set ByteString -> JSSwitchParts -> Set ByteString
refsInSwitchPart bound = \case
  JSCase _ caseExpr _ stmts -> refsInExpr bound caseExpr <> refsInStmts bound stmts
  JSDefault _ _ stmts -> refsInStmts bound stmts

-- | Collect free references in for-loop variants.
refsInForLike :: Set ByteString -> JSStatement -> Set ByteString
refsInForLike bound = \case
  JSFor _ _ inits _ conds _ updates _ body ->
    refsInArgs bound inits <> refsInArgs bound conds
    <> refsInArgs bound updates <> refsInStmt bound body
  JSForIn _ _ expr _ obj _ body ->
    refsInExpr bound expr <> refsInExpr bound obj <> refsInStmt bound body
  JSForVar _ _ _ declList _ conds _ updates _ body ->
    foldMap (refsInVarInitExpr bound) (commaListToList declList)
    <> refsInArgs bound conds <> refsInArgs bound updates <> refsInStmt bound body
  JSForVarIn _ _ _ decl _ obj _ body ->
    refsInVarInitExpr bound decl <> refsInExpr bound obj <> refsInStmt bound body
  _ -> Set.empty

-- | Collect free references in a catch clause.
refsInCatch :: Set ByteString -> JSAST.JSTryCatch -> Set ByteString
refsInCatch bound (JSAST.JSCatch _ _ _ _ (JSBlock _ ss _)) = refsInStmts bound ss
refsInCatch _ _ = Set.empty

-- | Collect free identifier references in an expression.
--
-- The key fix: 'JSStringLiteral' returns the empty set, so bracket accesses
-- like @args[\'node\']@ never produce a spurious dependency on @var node@.
refsInExpr :: Set ByteString -> JSExpression -> Set ByteString
refsInExpr bound = \case
  JSIdentifier _ name -> identRef bound name
  JSStringLiteral _ _ -> Set.empty
  JSDecimal _ _ -> Set.empty
  JSLiteral _ _ -> Set.empty
  JSHexInteger _ _ -> Set.empty
  JSCallExpression callee _ args _ -> refsInCallLike bound callee args
  JSMemberExpression callee _ args _ -> refsInCallLike bound callee args
  JSMemberDot obj _ _ -> refsInExpr bound obj
  JSMemberSquare obj _ key _ -> refsInExpr bound obj <> refsInExpr bound key
  JSFunctionExpression _ _ _ params _ block -> refsInFunctionBody bound params block
  JSAssignExpression l _ r -> refsInExpr bound l <> refsInExpr bound r
  JSVarInitExpression _ varInit -> refsInVarInit bound varInit
  expr -> refsInComplexExpr bound expr

-- | Collect free references in additional expression forms.
refsInComplexExpr :: Set ByteString -> JSExpression -> Set ByteString
refsInComplexExpr bound = \case
  JSExpressionBinary l _ r -> refsInExpr bound l <> refsInExpr bound r
  JSExpressionParen _ e _ -> refsInExpr bound e
  JSExpressionTernary c _ t _ e ->
    refsInExpr bound c <> refsInExpr bound t <> refsInExpr bound e
  JSUnaryExpression _ e -> refsInExpr bound e
  JSExpressionPostfix e _ -> refsInExpr bound e
  JSObjectLiteral _ propList _ ->
    foldMap (refsInObjProp bound) (trailingListToList propList)
  JSArrayLiteral _ elems _ -> foldMap (refsInArrayElem bound) elems
  JSMemberNew _ e _ args _ -> refsInExpr bound e <> refsInArgs bound args
  JSNewExpression _ e -> refsInExpr bound e
  JSCallExpressionDot e _ _ -> refsInExpr bound e
  JSCallExpressionSquare e _ key _ -> refsInExpr bound e <> refsInExpr bound key
  JSCommaExpression l _ r -> refsInExpr bound l <> refsInExpr bound r
  _ -> Set.empty

-- | References in a function call (callee + arguments).
refsInCallLike
  :: Set ByteString -> JSExpression -> JSCommaList JSExpression -> Set ByteString
refsInCallLike bound callee args = refsInExpr bound callee <> refsInArgs bound args

-- | References in a comma-separated argument list.
refsInArgs :: Set ByteString -> JSCommaList JSExpression -> Set ByteString
refsInArgs bound = foldMap (refsInExpr bound) . commaListToList

-- | References in an anonymous or named function body (scope-aware).
--
-- Computes the inner bound set as the union of the outer bound set,
-- parameter names, and all @var@-hoisted names in the function body.
-- This prevents local variable names from being treated as free variables
-- even when identically-named top-level declarations exist elsewhere.
refsInFunctionBody
  :: Set ByteString -> JSCommaList JSExpression -> JSBlock -> Set ByteString
refsInFunctionBody bound params (JSBlock _ body _) =
  refsInStmts innerBound body
  where
    innerBound = Set.unions [bound, paramNamesFromExprs params, hoistVarNames body]

-- | References in a @JSVarInitExpression@ (skips the declared name).
refsInVarInitExpr :: Set ByteString -> JSExpression -> Set ByteString
refsInVarInitExpr bound = \case
  JSVarInitExpression _ varInit -> refsInVarInit bound varInit
  _ -> Set.empty

-- | References in a variable initializer (@= expr@ or absent).
refsInVarInit :: Set ByteString -> JSVarInitializer -> Set ByteString
refsInVarInit bound = \case
  JSVarInit _ e -> refsInExpr bound e
  JSVarInitNone -> Set.empty

-- | References in an object property (only values; keys are not variable refs).
refsInObjProp :: Set ByteString -> JSObjectProperty -> Set ByteString
refsInObjProp bound = \case
  JSPropertyNameandValue _ _ exprs -> foldMap (refsInExpr bound) exprs
  JSPropertyIdentRef _ name -> identRef bound name
  JSObjectSpread _ e -> refsInExpr bound e
  _ -> Set.empty

-- | References in an array element.
refsInArrayElem :: Set ByteString -> JSArrayElement -> Set ByteString
refsInArrayElem bound = \case
  JSArrayElement e -> refsInExpr bound e
  JSArrayComma _ -> Set.empty

-- | Single identifier reference, filtered by bound set.
identRef :: Set ByteString -> ByteString -> Set ByteString
identRef bound name
  | Set.member name bound = Set.empty
  | otherwise = Set.singleton name


-- SCOPE HELPERS

-- | Collect @var@-hoisted names from a statement list.
--
-- Does NOT descend into nested function bodies — ES5 @var@ hoisting
-- stops at function boundaries.
hoistVarNames :: [JSStatement] -> Set ByteString
hoistVarNames = foldMap hoistInStmt

-- | Collect @var@-hoisted names from a single statement.
hoistInStmt :: JSStatement -> Set ByteString
hoistInStmt = \case
  JSVariable _ declList _ -> Set.fromList (varDeclAllNames declList)
  JSStatementBlock _ ss _ _ -> hoistVarNames ss
  JSIf _ _ _ _ body -> hoistInStmt body
  JSIfElse _ _ _ _ t _ e -> hoistInStmt t <> hoistInStmt e
  JSWhile _ _ _ _ body -> hoistInStmt body
  JSDoWhile _ body _ _ _ _ _ -> hoistInStmt body
  JSForVar _ _ _ declList _ _ _ _ _ body ->
    Set.fromList (varDeclAllNames declList) <> hoistInStmt body
  JSTry _ (JSBlock _ ss _) _ _ -> hoistVarNames ss
  JSSwitch _ _ _ _ _ cases _ _ -> foldMap hoistInSwitchPart cases
  _ -> Set.empty

-- | Collect @var@-hoisted names from a switch arm.
hoistInSwitchPart :: JSSwitchParts -> Set ByteString
hoistInSwitchPart = \case
  JSCase _ _ _ stmts -> hoistVarNames stmts
  JSDefault _ _ stmts -> hoistVarNames stmts

-- | Extract parameter names from a @JSCommaList JSExpression@ param list.
--
-- Function parameters are @JSIdentifier@ nodes in this AST representation.
paramNamesFromExprs :: JSCommaList JSExpression -> Set ByteString
paramNamesFromExprs params =
  Set.fromList [nm | JSIdentifier _ nm <- commaListToList params]

-- | Extract the first declared name from a @var@ declarator list.
varDeclFirstName :: JSCommaList JSExpression -> Maybe ByteString
varDeclFirstName declList =
  case commaListToList declList of
    (JSVarInitExpression (JSIdentifier _ nm) _ : _) -> Just nm
    _ -> Nothing

-- | Extract all declared names from a @var@ declarator list.
--
-- For @var A = 0, B = 1, C = 2@, returns @[\"A\", \"B\", \"C\"]@.
varDeclAllNames :: JSCommaList JSExpression -> [ByteString]
varDeclAllNames declList =
  [nm | JSVarInitExpression (JSIdentifier _ nm) _ <- commaListToList declList]


-- GROUP UTILITIES

-- | All declared names for a group (primary + comma-separated aliases).
--
-- For a @var A = 0, B = 1@ declaration, returns @[\"A\", \"B\"]@.
-- For a @function F(...)@ declaration, returns @[\"F\"]@.
-- Used to build the alias map and the global name set.
groupDeclNames :: BlockGroup -> [ByteString]
groupDeclNames bg =
  case _bgStatements bg of
    (JSVariable _ declList _ : _) -> varDeclAllNames declList
    _ -> [_bgName bg]


-- ARITY ANALYSIS

-- | Compute the set of F\/A arities referenced in a list of statements.
--
-- Scans for calls to @F2@–@F9@ and @A2@–@A9@ in the AST. An arity @n@
-- is present in the result if the identifier @Fn@ or @An@ appears as
-- the callee of a call expression anywhere in the statement list.
--
-- Used by the runtime registry to determine which F\/A wrappers each
-- runtime function depends on, enabling precise arity tree-shaking.
--
-- @since 0.20.4
aritiesInGroup :: [JSStatement] -> Set.Set Int
aritiesInGroup = foldMap aritiesInStmt

-- | Collect arity usages from a single statement.
aritiesInStmt :: JSStatement -> Set.Set Int
aritiesInStmt = \case
  JSVariable _ declList _ ->
    foldMap aritiesInVarInit (commaListToList declList)
  JSFunction _ _ _ _ _ (JSBlock _ ss _) _ ->
    foldMap aritiesInStmt ss
  JSExpressionStatement expr _ -> aritiesInExpr expr
  JSAssignStatement lhs _ rhs _ -> aritiesInExpr lhs <> aritiesInExpr rhs
  JSMethodCall callee _ args _ _ ->
    aritiesInExpr callee <> foldMap aritiesInExpr (commaListToList args)
  JSReturn _ mexpr _ -> foldMap aritiesInExpr mexpr
  JSStatementBlock _ ss _ _ -> foldMap aritiesInStmt ss
  JSIf _ _ cond _ body -> aritiesInExpr cond <> aritiesInStmt body
  JSIfElse _ _ cond _ t _ e ->
    aritiesInExpr cond <> aritiesInStmt t <> aritiesInStmt e
  JSWhile _ _ cond _ body -> aritiesInExpr cond <> aritiesInStmt body
  JSDoWhile _ body _ _ cond _ _ -> aritiesInStmt body <> aritiesInExpr cond
  JSTry _ (JSBlock _ ss _) catches _ ->
    foldMap aritiesInStmt ss <> foldMap aritiesInCatch catches
  _ -> Set.empty

-- | Collect arity usages from a catch clause.
aritiesInCatch :: JSAST.JSTryCatch -> Set.Set Int
aritiesInCatch (JSAST.JSCatch _ _ _ _ (JSBlock _ ss _)) = foldMap aritiesInStmt ss
aritiesInCatch _ = Set.empty

-- | Collect arity usages from a variable initializer expression.
aritiesInVarInit :: JSExpression -> Set.Set Int
aritiesInVarInit = \case
  JSVarInitExpression _ (JSVarInit _ e) -> aritiesInExpr e
  _ -> Set.empty

-- | Collect arity usages from an expression.
--
-- Detects @F2@–@F9@ and @A2@–@A9@ as callees in call expressions.
aritiesInExpr :: JSExpression -> Set.Set Int
aritiesInExpr = \case
  JSCallExpression callee _ args _ ->
    arityFromCallee callee
    <> aritiesInExpr callee
    <> foldMap aritiesInExpr (commaListToList args)
  JSMemberExpression callee _ args _ ->
    arityFromCallee callee
    <> aritiesInExpr callee
    <> foldMap aritiesInExpr (commaListToList args)
  JSFunctionExpression _ _ _ _ _ (JSBlock _ ss _) ->
    foldMap aritiesInStmt ss
  JSAssignExpression l _ r -> aritiesInExpr l <> aritiesInExpr r
  JSExpressionBinary l _ r -> aritiesInExpr l <> aritiesInExpr r
  JSExpressionTernary c _ t _ e ->
    aritiesInExpr c <> aritiesInExpr t <> aritiesInExpr e
  JSExpressionParen _ e _ -> aritiesInExpr e
  JSObjectLiteral _ propList _ ->
    foldMap aritiesInObjProp (trailingListToList propList)
  JSArrayLiteral _ elems _ -> foldMap aritiesInArrayElem elems
  _ -> Set.empty

-- | Check if an expression is an F\/A arity callee and return its arity.
arityFromCallee :: JSExpression -> Set.Set Int
arityFromCallee (JSIdentifier _ name) = arityFromName name
arityFromCallee _ = Set.empty

-- | Extract arity from an identifier name matching @F[2-9]@ or @A[2-9]@.
arityFromName :: ByteString -> Set.Set Int
arityFromName name =
  case name of
    "F2" -> Set.singleton 2
    "F3" -> Set.singleton 3
    "F4" -> Set.singleton 4
    "F5" -> Set.singleton 5
    "F6" -> Set.singleton 6
    "F7" -> Set.singleton 7
    "F8" -> Set.singleton 8
    "F9" -> Set.singleton 9
    "A2" -> Set.singleton 2
    "A3" -> Set.singleton 3
    "A4" -> Set.singleton 4
    "A5" -> Set.singleton 5
    "A6" -> Set.singleton 6
    "A7" -> Set.singleton 7
    "A8" -> Set.singleton 8
    "A9" -> Set.singleton 9
    _ -> Set.empty

-- | Collect arity usages from an object property.
aritiesInObjProp :: JSObjectProperty -> Set.Set Int
aritiesInObjProp = \case
  JSPropertyNameandValue _ _ exprs -> foldMap aritiesInExpr exprs
  JSObjectSpread _ e -> aritiesInExpr e
  _ -> Set.empty

-- | Collect arity usages from an array element.
aritiesInArrayElem :: JSArrayElement -> Set.Set Int
aritiesInArrayElem = \case
  JSArrayElement e -> aritiesInExpr e
  JSArrayComma _ -> Set.empty
