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

    -- * Free-variable analysis
  , freeVarsInGroup
  , allFreeVarsInGroup

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

-- | Parse an FFI JavaScript file into a list of top-level declaration groups.
--
-- Returns 'Nothing' on parse failure; the caller degrades gracefully by
-- emitting the full file without tree-shaking.
--
-- Each top-level @var@ or @function@ declaration starts a new group.
-- Statements between two consecutive declarations belong to the preceding
-- group.
parseBlockGroups :: Text.Text -> Maybe [BlockGroup]
parseBlockGroups content =
  case JS.parse (Text.unpack content) "<ffi>" of
    Left _                    -> Nothing
    Right (JSAstProgram ss _) -> Just (groupStmts ss)
    Right _                   -> Nothing

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
  stmt -> refsInForLike bound stmt

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
  _ -> Set.empty

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
