{-# LANGUAGE OverloadedStrings #-}

-- | FFI content minification for production builds.
--
-- Applies basic JavaScript minification to FFI file content:
--
--   * Strip single-line comments (@\/\/@) that start a line
--   * Strip multi-line comments (@\/* ... *\/@) except JSDoc with \@canopy-type
--   * Remove blank lines
--   * Remove @if (__canopy_debug)@ branches via AST transformation
--
-- Debug branch elimination uses the @language-javascript@ AST to correctly
-- handle ternaries, if\/else blocks, and nested expressions without the
-- fragility of string-based brace counting.
--
-- @since 0.20.2
module Generate.JavaScript.FFI.Minify
  ( minifyFFI
  , stripDebugBranches
  ) where

import Data.ByteString (ByteString)
import qualified Blaze.ByteString.Builder as Blaze
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Maybe as Maybe
import qualified Language.JavaScript.Parser as JSParser
import qualified Language.JavaScript.Parser.AST as JS
import qualified Language.JavaScript.Pretty.Printer as JSPrint


-- | Apply basic minification to FFI JavaScript content.
--
-- Strips line-leading comments and removes blank lines.
minifyFFI :: ByteString -> ByteString
minifyFFI content =
  BS8.unlines (filter keepLine processedLines)
  where
    rawLines = BS8.lines content
    processedLines = stripBlockComments rawLines
    keepLine line =
      let stripped = BS8.strip line
       in not (BS.null stripped)
            && not (isFullLineComment stripped)

-- | Check if a line is purely a comment (@\/\/@ at start).
isFullLineComment :: ByteString -> Bool
isFullLineComment line =
  BS8.isPrefixOf "//" line

-- | Remove multi-line comment blocks, preserving JSDoc with \@canopy-type.
stripBlockComments :: [ByteString] -> [ByteString]
stripBlockComments [] = []
stripBlockComments (line : rest)
  | isBlockCommentStart (BS8.strip line)
  , not (hasCanopyType (line : rest)) =
      stripBlockComments (dropUntilCommentEnd rest)
  | otherwise = line : stripBlockComments rest

-- | Check if a line starts a block comment (@\/*@).
isBlockCommentStart :: ByteString -> Bool
isBlockCommentStart line =
  BS8.isPrefixOf "/*" line || BS8.isPrefixOf "/**" line

-- | Check if a block comment contains \@canopy-type.
hasCanopyType :: [ByteString] -> Bool
hasCanopyType [] = False
hasCanopyType (line : rest)
  | BS8.isInfixOf "@canopy-type" line = True
  | BS8.isInfixOf "*/" line = False
  | otherwise = hasCanopyType rest

-- | Drop lines until end of block comment (@*\/@).
dropUntilCommentEnd :: [ByteString] -> [ByteString]
dropUntilCommentEnd [] = []
dropUntilCommentEnd (line : rest)
  | BS8.isInfixOf "*/" line = rest
  | otherwise = dropUntilCommentEnd rest


-- AST-LEVEL DEBUG BRANCH ELIMINATION

-- | Strip @__canopy_debug@ branches from JavaScript content.
--
-- Parses the JavaScript into an AST using @language-javascript@, then
-- recursively eliminates debug-conditional patterns:
--
--   * @__canopy_debug ? debugExpr : prodExpr@ becomes @prodExpr@
--   * @if (__canopy_debug) { ... } else { ... }@ becomes the else body
--   * @if (__canopy_debug) { ... }@ is removed entirely
--
-- On parse failure, returns the input unchanged as a defensive fallback.
stripDebugBranches :: ByteString -> ByteString
stripDebugBranches content =
  case JSParser.parseModule (BS8.unpack content) "<ffi>" of
    Left _ -> content
    Right ast -> renderAST (transformAST ast)

-- | Render a transformed AST back to a strict 'ByteString'.
renderAST :: JS.JSAST -> ByteString
renderAST ast =
  Blaze.toByteString (JSPrint.renderJS ast)

-- | Transform the top-level AST, dispatching on constructor.
transformAST :: JS.JSAST -> JS.JSAST
transformAST (JS.JSAstProgram stmts ann) =
  JS.JSAstProgram (transformStmts stmts) ann
transformAST (JS.JSAstModule items ann) =
  JS.JSAstModule (transformModuleItems items) ann
transformAST (JS.JSAstStatement stmt ann) =
  JS.JSAstStatement (Maybe.fromMaybe emptyStmt (transformStmt stmt)) ann
transformAST (JS.JSAstExpression expr ann) =
  JS.JSAstExpression (transformExpr expr) ann
transformAST (JS.JSAstLiteral expr ann) =
  JS.JSAstLiteral (transformExpr expr) ann

-- | Transform module items, filtering out eliminated debug statements.
transformModuleItems :: [JS.JSModuleItem] -> [JS.JSModuleItem]
transformModuleItems = Maybe.mapMaybe transformModuleItem

-- | Transform a single module item.
transformModuleItem :: JS.JSModuleItem -> Maybe JS.JSModuleItem
transformModuleItem (JS.JSModuleStatementListItem stmt) =
  fmap JS.JSModuleStatementListItem (transformStmt stmt)
transformModuleItem item = Just item

-- | Transform a list of statements, filtering out eliminated ones.
transformStmts :: [JS.JSStatement] -> [JS.JSStatement]
transformStmts = Maybe.mapMaybe transformStmt

-- | Transform a single statement, returning 'Nothing' to remove it.
--
-- Handles if\/else with debug condition by extracting the production
-- branch, and if-without-else by removing entirely.
transformStmt :: JS.JSStatement -> Maybe JS.JSStatement
transformStmt (JS.JSIf _ann _lp cond _rp body)
  | isDebugCondition cond = Nothing
  | otherwise = Just (JS.JSIf _ann _lp (transformExpr cond) _rp (transformStmtKeep body))
transformStmt (JS.JSIfElse _ann _lp cond _rp thenS _elseAnn elseS)
  | isDebugCondition cond = Just (unwrapBlock (transformStmtKeep elseS))
  | otherwise =
      Just (JS.JSIfElse _ann _lp (transformExpr cond) _rp (transformStmtKeep thenS) _elseAnn (transformStmtKeep elseS))
transformStmt stmt = Just (transformStmtKeep stmt)

-- | Transform a statement that is kept (not eliminated).
--
-- Recursively walks into nested statements to find debug branches deeper
-- in the tree (switch cases, function bodies, blocks, etc.).
transformStmtKeep :: JS.JSStatement -> JS.JSStatement
transformStmtKeep (JS.JSStatementBlock lbrace stmts rbrace semi) =
  JS.JSStatementBlock lbrace (transformStmts stmts) rbrace semi
transformStmtKeep (JS.JSIf ann lp cond rp body) =
  Maybe.fromMaybe emptyStmt (transformStmt (JS.JSIf ann lp cond rp body))
transformStmtKeep (JS.JSIfElse ann lp cond rp thenS elseAnn elseS) =
  Maybe.fromMaybe emptyStmt (transformStmt (JS.JSIfElse ann lp cond rp thenS elseAnn elseS))
transformStmtKeep (JS.JSSwitch ann lp expr rp lbrace parts rbrace semi) =
  JS.JSSwitch ann lp (transformExpr expr) rp lbrace (fmap transformSwitchPart parts) rbrace semi
transformStmtKeep (JS.JSReturn ann mexpr semi) =
  JS.JSReturn ann (fmap transformExpr mexpr) semi
transformStmtKeep (JS.JSVariable ann cslist semi) =
  JS.JSVariable ann (transformCommaList cslist) semi
transformStmtKeep (JS.JSLet ann cslist semi) =
  JS.JSLet ann (transformCommaList cslist) semi
transformStmtKeep (JS.JSConstant ann cslist semi) =
  JS.JSConstant ann (transformCommaList cslist) semi
transformStmtKeep (JS.JSExpressionStatement expr semi) =
  JS.JSExpressionStatement (transformExpr expr) semi
transformStmtKeep (JS.JSAssignStatement lhs op rhs semi) =
  JS.JSAssignStatement (transformExpr lhs) op (transformExpr rhs) semi
transformStmtKeep (JS.JSFunction ann name lp params rp body semi) =
  JS.JSFunction ann name lp params rp (transformBlock body) semi
transformStmtKeep (JS.JSAsyncFunction ann asyncAnn name lp params rp body semi) =
  JS.JSAsyncFunction ann asyncAnn name lp params rp (transformBlock body) semi
transformStmtKeep (JS.JSGenerator ann star name lp params rp body semi) =
  JS.JSGenerator ann star name lp params rp (transformBlock body) semi
transformStmtKeep (JS.JSWhile ann lp cond rp body) =
  JS.JSWhile ann lp (transformExpr cond) rp (transformStmtKeep body)
transformStmtKeep (JS.JSDoWhile ann body whileAnn lp cond rp semi) =
  JS.JSDoWhile ann (transformStmtKeep body) whileAnn lp (transformExpr cond) rp semi
transformStmtKeep (JS.JSFor ann lp e1 s1 e2 s2 e3 rp body) =
  JS.JSFor ann lp (transformCommaList e1) s1 (transformCommaList e2) s2 (transformCommaList e3) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForIn ann lp e1 binOp e2 rp body) =
  JS.JSForIn ann lp (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForVar ann lp var vars s1 e2 s2 e3 rp body) =
  JS.JSForVar ann lp var (transformCommaList vars) s1 (transformCommaList e2) s2 (transformCommaList e3) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForVarIn ann lp var e1 binOp e2 rp body) =
  JS.JSForVarIn ann lp var (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForLet ann lp letAnn vars s1 e2 s2 e3 rp body) =
  JS.JSForLet ann lp letAnn (transformCommaList vars) s1 (transformCommaList e2) s2 (transformCommaList e3) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForLetIn ann lp letAnn e1 binOp e2 rp body) =
  JS.JSForLetIn ann lp letAnn (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForLetOf ann lp letAnn e1 binOp e2 rp body) =
  JS.JSForLetOf ann lp letAnn (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForConst ann lp constAnn vars s1 e2 s2 e3 rp body) =
  JS.JSForConst ann lp constAnn (transformCommaList vars) s1 (transformCommaList e2) s2 (transformCommaList e3) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForConstIn ann lp constAnn e1 binOp e2 rp body) =
  JS.JSForConstIn ann lp constAnn (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForConstOf ann lp constAnn e1 binOp e2 rp body) =
  JS.JSForConstOf ann lp constAnn (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForOf ann lp e1 binOp e2 rp body) =
  JS.JSForOf ann lp (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSForVarOf ann lp varAnn e1 binOp e2 rp body) =
  JS.JSForVarOf ann lp varAnn (transformExpr e1) binOp (transformExpr e2) rp (transformStmtKeep body)
transformStmtKeep (JS.JSTry ann body catches finally) =
  JS.JSTry ann (transformBlock body) (fmap transformCatch catches) (transformFinally finally)
transformStmtKeep (JS.JSThrow ann expr semi) =
  JS.JSThrow ann (transformExpr expr) semi
transformStmtKeep (JS.JSLabelled ident colon stmt) =
  JS.JSLabelled ident colon (transformStmtKeep stmt)
transformStmtKeep (JS.JSWith ann lp expr rp body semi) =
  JS.JSWith ann lp (transformExpr expr) rp (transformStmtKeep body) semi
transformStmtKeep (JS.JSMethodCall expr lp args rp semi) =
  JS.JSMethodCall (transformExpr expr) lp (transformCommaList args) rp semi
transformStmtKeep stmt = stmt

-- | Transform an expression, replacing debug ternaries with prod values.
transformExpr :: JS.JSExpression -> JS.JSExpression
transformExpr (JS.JSExpressionTernary cond _q _thenE _c elseE)
  | isDebugCondition cond = transformExpr elseE
transformExpr (JS.JSExpressionTernary cond q thenE c elseE) =
  JS.JSExpressionTernary (transformExpr cond) q (transformExpr thenE) c (transformExpr elseE)
transformExpr (JS.JSExpressionBinary lhs op rhs) =
  JS.JSExpressionBinary (transformExpr lhs) op (transformExpr rhs)
transformExpr (JS.JSExpressionParen lp expr rp) =
  JS.JSExpressionParen lp (transformExpr expr) rp
transformExpr (JS.JSObjectLiteral lbrace props rbrace) =
  JS.JSObjectLiteral lbrace (transformPropertyList props) rbrace
transformExpr (JS.JSArrayLiteral lbr elems rbr) =
  JS.JSArrayLiteral lbr (fmap transformArrayElement elems) rbr
transformExpr (JS.JSCallExpression fn lp args rp) =
  JS.JSCallExpression (transformExpr fn) lp (transformCommaList args) rp
transformExpr (JS.JSCallExpressionDot expr ann ident) =
  JS.JSCallExpressionDot (transformExpr expr) ann ident
transformExpr (JS.JSCallExpressionSquare expr lbr idx rbr) =
  JS.JSCallExpressionSquare (transformExpr expr) lbr (transformExpr idx) rbr
transformExpr (JS.JSAssignExpression lhs op rhs) =
  JS.JSAssignExpression (transformExpr lhs) op (transformExpr rhs)
transformExpr (JS.JSCommaExpression lhs ann rhs) =
  JS.JSCommaExpression (transformExpr lhs) ann (transformExpr rhs)
transformExpr (JS.JSMemberDot obj ann member) =
  JS.JSMemberDot (transformExpr obj) ann member
transformExpr (JS.JSMemberSquare obj lbr idx rbr) =
  JS.JSMemberSquare (transformExpr obj) lbr (transformExpr idx) rbr
transformExpr (JS.JSMemberExpression fn lp args rp) =
  JS.JSMemberExpression (transformExpr fn) lp (transformCommaList args) rp
transformExpr (JS.JSUnaryExpression op expr) =
  JS.JSUnaryExpression op (transformExpr expr)
transformExpr (JS.JSExpressionPostfix expr op) =
  JS.JSExpressionPostfix (transformExpr expr) op
transformExpr (JS.JSVarInitExpression ident init') =
  JS.JSVarInitExpression (transformExpr ident) (transformVarInit init')
transformExpr (JS.JSArrowExpression params ann body) =
  JS.JSArrowExpression params ann (transformConciseBody body)
transformExpr (JS.JSFunctionExpression ann name lp params rp body) =
  JS.JSFunctionExpression ann name lp params rp (transformBlock body)
transformExpr (JS.JSGeneratorExpression ann star name lp params rp body) =
  JS.JSGeneratorExpression ann star name lp params rp (transformBlock body)
transformExpr (JS.JSSpreadExpression ann expr) =
  JS.JSSpreadExpression ann (transformExpr expr)
transformExpr (JS.JSNewExpression ann expr) =
  JS.JSNewExpression ann (transformExpr expr)
transformExpr (JS.JSMemberNew ann expr lp args rp) =
  JS.JSMemberNew ann (transformExpr expr) lp (transformCommaList args) rp
transformExpr (JS.JSYieldExpression ann mexpr) =
  JS.JSYieldExpression ann (fmap transformExpr mexpr)
transformExpr (JS.JSYieldFromExpression ann starAnn expr) =
  JS.JSYieldFromExpression ann starAnn (transformExpr expr)
transformExpr (JS.JSAwaitExpression ann expr) =
  JS.JSAwaitExpression ann (transformExpr expr)
transformExpr expr = expr

-- | Check if an expression is the @__canopy_debug@ identifier.
isDebugCondition :: JS.JSExpression -> Bool
isDebugCondition (JS.JSIdentifier _ name) = name == "__canopy_debug"
isDebugCondition (JS.JSExpressionParen _ inner _) = isDebugCondition inner
isDebugCondition _ = False

-- | An empty statement used when eliminating debug-only if blocks.
emptyStmt :: JS.JSStatement
emptyStmt = JS.JSEmptyStatement JS.JSNoAnnot

-- | Unwrap a single-statement block to avoid extra braces.
--
-- @{ stmt; }@ becomes @stmt;@ but multi-statement blocks are kept.
unwrapBlock :: JS.JSStatement -> JS.JSStatement
unwrapBlock (JS.JSStatementBlock _ [single] _ _) = single
unwrapBlock stmt = stmt

-- | Transform a 'JSBlock' (used in function bodies, try\/catch).
transformBlock :: JS.JSBlock -> JS.JSBlock
transformBlock (JS.JSBlock lbrace stmts rbrace) =
  JS.JSBlock lbrace (transformStmts stmts) rbrace

-- | Transform an arrow function's concise body.
transformConciseBody :: JS.JSConciseBody -> JS.JSConciseBody
transformConciseBody (JS.JSConciseFunctionBody block) =
  JS.JSConciseFunctionBody (transformBlock block)
transformConciseBody (JS.JSConciseExpressionBody expr) =
  JS.JSConciseExpressionBody (transformExpr expr)

-- | Transform an individual switch case or default clause.
transformSwitchPart :: JS.JSSwitchParts -> JS.JSSwitchParts
transformSwitchPart (JS.JSCase ann expr colon stmts) =
  JS.JSCase ann (transformExpr expr) colon (transformStmts stmts)
transformSwitchPart (JS.JSDefault ann colon stmts) =
  JS.JSDefault ann colon (transformStmts stmts)

-- | Transform a try-catch clause.
transformCatch :: JS.JSTryCatch -> JS.JSTryCatch
transformCatch (JS.JSCatch ann lp ident rp body) =
  JS.JSCatch ann lp ident rp (transformBlock body)
transformCatch (JS.JSCatchIf ann lp ident ifAnn cond rp body) =
  JS.JSCatchIf ann lp ident ifAnn (transformExpr cond) rp (transformBlock body)
transformCatch (JS.JSCatchNoParam ann body) =
  JS.JSCatchNoParam ann (transformBlock body)

-- | Transform a try-finally clause.
transformFinally :: JS.JSTryFinally -> JS.JSTryFinally
transformFinally (JS.JSFinally ann body) =
  JS.JSFinally ann (transformBlock body)
transformFinally JS.JSNoFinally = JS.JSNoFinally

-- | Transform a variable initializer.
transformVarInit :: JS.JSVarInitializer -> JS.JSVarInitializer
transformVarInit (JS.JSVarInit ann expr) =
  JS.JSVarInit ann (transformExpr expr)
transformVarInit JS.JSVarInitNone = JS.JSVarInitNone

-- | Transform elements in a 'JSCommaList'.
transformCommaList :: JS.JSCommaList JS.JSExpression -> JS.JSCommaList JS.JSExpression
transformCommaList (JS.JSLCons rest comma item) =
  JS.JSLCons (transformCommaList rest) comma (transformExpr item)
transformCommaList (JS.JSLOne item) =
  JS.JSLOne (transformExpr item)
transformCommaList JS.JSLNil = JS.JSLNil

-- | Transform an object property list (with optional trailing comma).
transformPropertyList :: JS.JSObjectPropertyList -> JS.JSObjectPropertyList
transformPropertyList (JS.JSCTLComma props ann) =
  JS.JSCTLComma (transformPropCommaList props) ann
transformPropertyList (JS.JSCTLNone props) =
  JS.JSCTLNone (transformPropCommaList props)

-- | Transform a comma-separated list of object properties.
transformPropCommaList :: JS.JSCommaList JS.JSObjectProperty -> JS.JSCommaList JS.JSObjectProperty
transformPropCommaList (JS.JSLCons rest comma item) =
  JS.JSLCons (transformPropCommaList rest) comma (transformObjectProp item)
transformPropCommaList (JS.JSLOne item) =
  JS.JSLOne (transformObjectProp item)
transformPropCommaList JS.JSLNil = JS.JSLNil

-- | Transform a single object property value.
transformObjectProp :: JS.JSObjectProperty -> JS.JSObjectProperty
transformObjectProp (JS.JSPropertyNameandValue name colon vals) =
  JS.JSPropertyNameandValue name colon (fmap transformExpr vals)
transformObjectProp (JS.JSObjectMethod method) =
  JS.JSObjectMethod (transformMethodDef method)
transformObjectProp prop = prop

-- | Transform a method definition body.
transformMethodDef :: JS.JSMethodDefinition -> JS.JSMethodDefinition
transformMethodDef (JS.JSMethodDefinition name lp params rp body) =
  JS.JSMethodDefinition name lp params rp (transformBlock body)
transformMethodDef (JS.JSGeneratorMethodDefinition star name lp params rp body) =
  JS.JSGeneratorMethodDefinition star name lp params rp (transformBlock body)
transformMethodDef (JS.JSPropertyAccessor acc name lp params rp body) =
  JS.JSPropertyAccessor acc name lp params rp (transformBlock body)
transformMethodDef (JS.JSAsyncMethodDefinition asyncAnn name lp params rp body) =
  JS.JSAsyncMethodDefinition asyncAnn name lp params rp (transformBlock body)

-- | Transform an array element.
transformArrayElement :: JS.JSArrayElement -> JS.JSArrayElement
transformArrayElement (JS.JSArrayElement expr) =
  JS.JSArrayElement (transformExpr expr)
transformArrayElement (JS.JSArrayComma ann) = JS.JSArrayComma ann
