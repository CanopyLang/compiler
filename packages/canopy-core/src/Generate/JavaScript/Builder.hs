{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MagicHash #-}
-- | JavaScript AST builder and renderer for the Canopy code generator.
--
-- This module provides the bridge between Canopy's internal expression and
-- statement representations and the @language-javascript@ AST. It converts
-- Canopy @Expr@ and @Stmt@ values to @language-javascript@ AST nodes and
-- then renders them to 'Data.ByteString.Builder.Builder' output.
--
-- The rendering pipeline is zero-copy where possible:
--
--   1. 'Name' values are converted to 'ByteString' via 'nameToByteString',
--      avoiding the intermediate @[Char]@ allocation.
--   2. 'Builder' values are converted to 'ByteString' via 'builderToByteString'.
--   3. The @language-javascript@ pretty printer returns a 'Blaze.Builder',
--      which is bridged to 'Data.ByteString.Builder.Builder' via
--      @lazyByteString . Blaze.toLazyByteString@.
--
-- @since 0.19.1
module Generate.JavaScript.Builder
  ( stmtToBuilder
  , exprToBuilder
  , stmtToBuilderWithMode
  , exprToBuilderWithMode
  , Expr(..), LValue(..)
  , Stmt(..), Case(..)
  , InfixOp(..), PrefixOp(..)
  , ModuleItem(..)
  , moduleToBuilder
  , moduleToFormattedBuilder
  , moduleItemToBuilder
  , nameToByteString
  , shorthandObjectExpr
  , sanitizeScriptElementString
  )
  where

import qualified Blaze.ByteString.Builder as Blaze
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.ByteString.Builder as B
import qualified Generate.JavaScript.Name as Name
import Generate.JavaScript.Name (Name)
import qualified Json.Encode as Json
import qualified Canopy.String as ES
import qualified Canopy.Data.Utf8 as Utf8
import qualified GHC.Word
import qualified Generate.Mode as Mode

import qualified Language.JavaScript.Parser.AST as JS
import Language.JavaScript.Parser.AST (JSAnnot(..), JSAST(..), JSExpression, JSStatement)
import Language.JavaScript.Parser.SrcLocation (TokenPosn(..))
import Language.JavaScript.Parser.Token (CommentAnnotation(..))
import qualified Language.JavaScript.Pretty.Formatted as JSFmt
import qualified Language.JavaScript.Pretty.Printer as JSP


backslash :: GHC.Word.Word8
backslash = 0x5c

forwardslash :: GHC.Word.Word8
forwardslash = 0x2f

exclamationMark :: GHC.Word.Word8
exclamationMark = 0x21


-- | Sanitize a string for safe embedding inside an HTML @\<script\>@ element.
--
-- Applies both @\<\/script\>@ and @\<!--@ sanitization per the HTML living standard:
-- <https://html.spec.whatwg.org/multipage/scripting.html#restrictions-for-contents-of-script-elements>
--
-- This is only required for @.html@ output, not @.js@ output.
sanitizeScriptElementString :: ES.String -> ES.String
sanitizeScriptElementString = sanitizeHtmlComment . sanitizeScriptTag

-- | Escape forward-slashes to prevent @\<\/script\>@ from terminating the script element.
sanitizeScriptTag :: ES.String -> ES.String
sanitizeScriptTag str = Utf8.joinConsecutivePairSep (backslash, forwardslash) (Utf8.split forwardslash str)

-- | Escape exclamation marks to prevent @\<!--@ from starting an HTML comment.
sanitizeHtmlComment :: ES.String -> ES.String
sanitizeHtmlComment str = Utf8.joinConsecutivePairSep (backslash, exclamationMark) (Utf8.split exclamationMark str)


-- EXPRESSIONS


-- NOTE: I tried making this create a B.Builder directly.
--
-- The hope was that it'd allocate less and speed things up, but it seemed
-- to be neutral for perf.
--
-- The downside is that Generate.JavaScript.Expression inspects the
-- structure of Expr and Stmt on some occassions to try to strip out
-- unnecessary closures. I think these closures are already avoided
-- by other logic in code gen these days, but I am not 100% certain.
--
-- For this to be worth it, I think it would be necessary to avoid
-- returning tuples when generating expressions.
--

-- | A JavaScript expression node in Canopy's internal representation.
--
-- This is converted to a @language-javascript@ AST node for rendering.
data Expr
  = String Builder
  | Float Builder
  | Int Int
  | Bool Bool
  | Null
  | Json Json.Value
  | Array [Expr]
  | Object [(Name, Expr)]
  | Ref Name
  | Access Expr Name -- foo.bar
  | Index  Expr Expr -- foo[bar]
  | Prefix PrefixOp Expr
  | Infix InfixOp Expr Expr
  | If Expr Expr Expr
  | Assign LValue Expr
  | Call Expr [Expr]
  | Function (Maybe Name) [Name] [Stmt]
  deriving Show

-- | An assignable left-hand side in a JavaScript assignment expression.
data LValue
  = LRef Name
  | LDot Expr Name
  | LBracket Expr Expr
  deriving Show


-- STATEMENTS


-- | A JavaScript statement node in Canopy's internal representation.
data Stmt
  = Block [Stmt]
  | EmptyStmt
  | ExprStmt Expr
  | ExprStmtWithSemi Expr
  | IfStmt Expr Stmt Stmt
  | Switch Expr [Case]
  | While Expr Stmt
  | Break (Maybe Name)
  | Continue (Maybe Name)
  | Labelled Name Stmt
  | Try Stmt Name Stmt
  | Throw Expr
  | Return Expr
  | Var Name Expr
  | Vars [(Name, Expr)]
  | Const Name Expr
  | ConstPure Name Expr
  | FunctionStmt Name [Name] [Stmt]
  deriving Show

-- | A case arm in a JavaScript @switch@ statement.
data Case
  = Case Expr [Stmt]
  | Default [Stmt]
  deriving Show


-- OPERATORS


-- | Binary infix operators for JavaScript expressions.
data InfixOp
  = OpAdd -- +
  | OpSub -- -
  | OpMul -- *
  | OpDiv -- /
  | OpMod -- %
  | OpEq -- ===
  | OpNe -- !==
  | OpLt -- <
  | OpLe -- <=
  | OpGt -- >
  | OpGe -- >=
  | OpAnd -- &&
  | OpOr  -- ||
  | OpBitwiseAnd -- &
  | OpBitwiseXor -- ^
  | OpBitwiseOr  -- |
  | OpLShift     -- <<
  | OpSpRShift   -- >>
  | OpZfRShift   -- >>>
  deriving Show

-- | Unary prefix operators for JavaScript expressions.
data PrefixOp
  = PrefixNot        -- !
  | PrefixNegate     -- -
  | PrefixComplement -- ~
  deriving Show


-- LANGUAGE-JAVASCRIPT CONVERSION

-- | Annotation with no position or whitespace information.
noAnnot :: JSAnnot
noAnnot = JSNoAnnot

-- | Annotation with a single leading space character.
spaceAnnot :: JSAnnot
spaceAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) " "]

-- | Annotation with a single leading space, for identifiers after operators.
leadingSpaceAnnot :: JSAnnot
leadingSpaceAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) " "]

-- | Annotation with a trailing newline, for statement separation.
newlineAnnot :: JSAnnot
newlineAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) "\n"]

-- | Annotation with a @\/\*#__PURE__\*\/@ comment for tree-shaking hints.
--
-- Renders as @\/\*#__PURE__\*\/ @ (with trailing space before @const@).
pureAnnot :: JSAnnot
pureAnnot = JSAnnot (TokenPn 0 0 0)
  [CommentA (TokenPn 0 0 0) "/*#__PURE__*/ "]

-- | Select an annotation based on the current compilation mode.
annotForMode :: Mode.Mode -> JSAnnot -> JSAnnot
annotForMode mode defaultAnnot =
  if Mode.isElmCompatible mode
    then spaceAnnot
    else defaultAnnot

-- | Choose parameter annotation for the current compilation mode.
paramAnnotForMode :: Mode.Mode -> JSAnnot
paramAnnotForMode mode = annotForMode mode noAnnot

-- | Convert a 'Name' to a strict 'ByteString' for use in the JS AST.
--
-- Replaces the old @nameToString@ which allocated an intermediate @[Char]@.
nameToByteString :: Name -> ByteString
nameToByteString = LBS.toStrict . B.toLazyByteString . Name.toBuilder

-- | Convert a 'Data.ByteString.Builder.Builder' to a strict 'ByteString'.
--
-- Replaces the old @builderToString@ which allocated an intermediate @[Char]@.
builderToByteString :: Builder -> ByteString
builderToByteString = LBS.toStrict . B.toLazyByteString

-- | Wrap an expression in parentheses for precedence disambiguation.
wrapInParens :: Expr -> JSExpression
wrapInParens expr = JS.JSExpressionParen noAnnot (exprToJS expr) noAnnot

-- | Convert the operand of a negate prefix, parenthesizing when the
-- operand is itself a unary minus or complement to avoid generating
-- @--x@ (JS decrement) or @-~x@ ambiguity.
negateOperand :: Expr -> JSExpression
negateOperand expr = case expr of
  Prefix PrefixNegate _ -> wrapInParens expr
  Prefix PrefixComplement _ -> wrapInParens expr
  Infix _ _ _ -> wrapInParens expr
  _ -> exprToJS expr

-- | Return 'True' if the expression requires parentheses inside a ternary.
needsParensInTernary :: Expr -> Bool
needsParensInTernary expr = case expr of
  Infix _ _ _ -> True
  Prefix _ _ -> True
  _ -> False

-- | JavaScript operator precedence levels (higher binds tighter).
--
-- Based on the MDN operator precedence table. Used to determine when
-- child expressions in an 'Infix' node need parenthesization.
jsOpPrecedence :: InfixOp -> Int
jsOpPrecedence op = case op of
  OpMul -> 13
  OpDiv -> 13
  OpMod -> 13
  OpAdd -> 12
  OpSub -> 12
  OpLShift -> 11
  OpSpRShift -> 11
  OpZfRShift -> 11
  OpLt -> 10
  OpLe -> 10
  OpGt -> 10
  OpGe -> 10
  OpEq -> 9
  OpNe -> 9
  OpBitwiseAnd -> 8
  OpBitwiseXor -> 7
  OpBitwiseOr -> 6
  OpAnd -> 5
  OpOr -> 4

-- | Convert a Canopy 'Expr' to a @language-javascript@ 'JSExpression'.
exprToJS :: Expr -> JSExpression
exprToJS expr = case expr of
  String builder ->
    JS.JSStringLiteral noAnnot ("'" <> builderToByteString builder <> "'")
  Float builder ->
    JS.JSLiteral noAnnot (builderToByteString builder)
  Int n ->
    JS.JSLiteral noAnnot (BS8.pack (show n))
  Bool True ->
    JS.JSLiteral noAnnot "true"
  Bool False ->
    JS.JSLiteral noAnnot "false"
  Null ->
    JS.JSLiteral noAnnot "null"
  Json jsonValue ->
    JS.JSLiteral noAnnot (LBS.toStrict (B.toLazyByteString (Json.encodeUgly jsonValue)))
  Array exprs ->
    JS.JSArrayLiteral noAnnot (exprToJSArrayElementsWithCommas exprs) noAnnot
  Object fields ->
    JS.JSObjectLiteral noAnnot (fieldsToJSCommaTrailingList fields) noAnnot
  Ref name ->
    JS.JSIdentifier leadingSpaceAnnot (nameToByteString name)
  Access obj field ->
    JS.JSMemberDot (exprToJS obj) noAnnot (JS.JSIdentifier noAnnot (nameToByteString field))
  Index obj key ->
    JS.JSMemberSquare (exprToJS obj) noAnnot (exprToJS key) noAnnot
  Prefix PrefixNot e ->
    JS.JSUnaryExpression (JS.JSUnaryOpNot noAnnot) (exprToJS e)
  Prefix PrefixNegate e ->
    JS.JSUnaryExpression (JS.JSUnaryOpMinus noAnnot) (negateOperand e)
  Prefix PrefixComplement e ->
    JS.JSUnaryExpression (JS.JSUnaryOpTilde noAnnot) (exprToJS e)
  Infix op left right ->
    JS.JSExpressionBinary leftJS (infixOpToJS op) rightJS
    where
      parentPrec = jsOpPrecedence op
      leftJS = case left of
        If _ _ _ -> wrapInParens left
        Infix childOp _ _ | jsOpPrecedence childOp < parentPrec -> wrapInParens left
        _ -> exprToJS left
      rightJS = case right of
        If _ _ _ -> wrapInParens right
        Infix childOp _ _ | jsOpPrecedence childOp <= parentPrec -> wrapInParens right
        _ -> exprToJS right
  If cond thenExpr elseExpr ->
    JS.JSExpressionTernary condJS noAnnot thenJS noAnnot elseJS
    where
      condJS = if needsParensInTernary cond then wrapInParens cond else exprToJS cond
      thenJS = if needsParensInTernary thenExpr then wrapInParens thenExpr else exprToJS thenExpr
      elseJS = if needsParensInTernary elseExpr then wrapInParens elseExpr else exprToJS elseExpr
  Assign lval e ->
    JS.JSAssignExpression (lvalueToJS lval) (JS.JSAssign spaceAnnot) (exprToJS e)
  Call func args ->
    JS.JSCallExpression (exprToJS func) noAnnot (argsToJSCommaList args) noAnnot
  Function maybeName params body ->
    JS.JSFunctionExpression
      leadingSpaceAnnot
      (maybe JS.JSIdentNone (JS.JSIdentName noAnnot . nameToByteString) maybeName)
      noAnnot
      (paramsToJSCommaList params)
      noAnnot
      (JS.JSBlock noAnnot (map stmtToJS body) noAnnot)

-- | Convert a Canopy 'Stmt' to a @language-javascript@ 'JSStatement'.
stmtToJS :: Stmt -> JSStatement
stmtToJS stmt = case stmt of
  Block [] ->
    JS.JSEmptyStatement noAnnot
  Block [singleStmt] ->
    stmtToJS singleStmt
  Block stmts ->
    JS.JSStatementBlock noAnnot (map stmtToJS stmts) noAnnot JS.JSSemiAuto
  EmptyStmt ->
    JS.JSEmptyStatement noAnnot
  ExprStmt e ->
    JS.JSExpressionStatement (exprToJS e) JS.JSSemiAuto
  ExprStmtWithSemi e ->
    JS.JSExpressionStatement (exprToJS e) (JS.JSSemi noAnnot)
  IfStmt cond thenStmt elseStmt ->
    JS.JSIfElse noAnnot leadingSpaceAnnot (exprToJS cond) leadingSpaceAnnot
      (ensureBlock thenStmt) leadingSpaceAnnot (ensureBlock elseStmt)
    where
      ensureBlock blockStmt = case blockStmt of
        Block _ -> stmtToJS blockStmt
        _ -> JS.JSStatementBlock noAnnot [stmtToJS blockStmt] noAnnot JS.JSSemiAuto
  Switch e cases ->
    JS.JSSwitch leadingSpaceAnnot noAnnot (exprToJS e) noAnnot noAnnot
      (map caseToJS cases) noAnnot JS.JSSemiAuto
  While cond body ->
    JS.JSWhile leadingSpaceAnnot leadingSpaceAnnot (exprToJS cond) leadingSpaceAnnot (stmtToJS body)
  Break Nothing ->
    JS.JSBreak leadingSpaceAnnot JS.JSIdentNone (JS.JSSemi noAnnot)
  Break (Just label) ->
    JS.JSBreak leadingSpaceAnnot (JS.JSIdentName leadingSpaceAnnot (nameToByteString label)) (JS.JSSemi noAnnot)
  Continue Nothing ->
    JS.JSContinue leadingSpaceAnnot JS.JSIdentNone (JS.JSSemi noAnnot)
  Continue (Just label) ->
    JS.JSContinue leadingSpaceAnnot (JS.JSIdentName leadingSpaceAnnot (nameToByteString label)) (JS.JSSemi noAnnot)
  Labelled label s ->
    JS.JSLabelled (JS.JSIdentName noAnnot (nameToByteString label)) noAnnot (stmtToJS s)
  Try tryStmt errName catchStmt ->
    JS.JSTry leadingSpaceAnnot (blockFromStmt tryStmt)
      [JS.JSCatch noAnnot noAnnot (JS.JSIdentifier noAnnot (nameToByteString errName)) noAnnot (blockFromStmt catchStmt)]
      JS.JSNoFinally
  Throw e ->
    JS.JSThrow leadingSpaceAnnot (exprToJS e) JS.JSSemiAuto
  Return e ->
    JS.JSReturn leadingSpaceAnnot (Just (exprToJSWithSpace e)) (JS.JSSemi noAnnot)
  Var name e ->
    JS.JSVariable noAnnot
      (JS.JSLOne (JS.JSVarInitExpression
        (JS.JSIdentifier leadingSpaceAnnot (nameToByteString name))
        (JS.JSVarInit spaceAnnot (exprToJS e))))
      (JS.JSSemi noAnnot)
  Vars pairs ->
    JS.JSVariable noAnnot (varsToJSCommaList pairs) (JS.JSSemi newlineAnnot)
  Const name e ->
    JS.JSConstant noAnnot
      (JS.JSLOne (JS.JSVarInitExpression
        (JS.JSIdentifier leadingSpaceAnnot (nameToByteString name))
        (JS.JSVarInit spaceAnnot (exprToJS e))))
      (JS.JSSemi noAnnot)
  ConstPure name e ->
    JS.JSConstant pureAnnot
      (JS.JSLOne (JS.JSVarInitExpression
        (JS.JSIdentifier leadingSpaceAnnot (nameToByteString name))
        (JS.JSVarInit spaceAnnot (exprToJS e))))
      (JS.JSSemi noAnnot)
  FunctionStmt name params body ->
    JS.JSFunction noAnnot
      (JS.JSIdentName leadingSpaceAnnot (nameToByteString name))
      noAnnot
      (paramsToJSCommaList params)
      noAnnot
      (JS.JSBlock noAnnot (map stmtToJS body) noAnnot)
      JS.JSSemiAuto

-- | Convert an 'InfixOp' to a @language-javascript@ binary operator node.
infixOpToJS :: InfixOp -> JS.JSBinOp
infixOpToJS op = case op of
  OpAdd -> JS.JSBinOpPlus spaceAnnot
  OpSub -> JS.JSBinOpMinus spaceAnnot
  OpMul -> JS.JSBinOpTimes spaceAnnot
  OpDiv -> JS.JSBinOpDivide spaceAnnot
  OpMod -> JS.JSBinOpMod spaceAnnot
  OpEq -> JS.JSBinOpStrictEq spaceAnnot
  OpNe -> JS.JSBinOpStrictNeq spaceAnnot
  OpLt -> JS.JSBinOpLt spaceAnnot
  OpLe -> JS.JSBinOpLe spaceAnnot
  OpGt -> JS.JSBinOpGt spaceAnnot
  OpGe -> JS.JSBinOpGe spaceAnnot
  OpAnd -> JS.JSBinOpAnd spaceAnnot
  OpOr -> JS.JSBinOpOr spaceAnnot
  OpBitwiseAnd -> JS.JSBinOpBitAnd spaceAnnot
  OpBitwiseXor -> JS.JSBinOpBitXor spaceAnnot
  OpBitwiseOr -> JS.JSBinOpBitOr spaceAnnot
  OpLShift -> JS.JSBinOpLsh spaceAnnot
  OpSpRShift -> JS.JSBinOpRsh spaceAnnot
  OpZfRShift -> JS.JSBinOpUrsh spaceAnnot

-- | Convert an 'LValue' to a @language-javascript@ expression node.
lvalueToJS :: LValue -> JSExpression
lvalueToJS lval = case lval of
  LRef name ->
    JS.JSIdentifier noAnnot (nameToByteString name)
  LDot e field ->
    JS.JSMemberDot (exprToJS e) noAnnot (JS.JSIdentifier noAnnot (nameToByteString field))
  LBracket e key ->
    JS.JSMemberSquare (exprToJS e) noAnnot (exprToJS key) noAnnot

-- | Convert a 'Case' arm to a @language-javascript@ switch parts node.
caseToJS :: Case -> JS.JSSwitchParts
caseToJS c = case c of
  Case e stmts ->
    JS.JSCase leadingSpaceAnnot (exprToJSWithSpace e) leadingSpaceAnnot (map stmtToJS stmts)
  Default stmts ->
    JS.JSDefault leadingSpaceAnnot leadingSpaceAnnot (map stmtToJS stmts)

-- | Convert an expression for use in a leading-space context (case/return).
--
-- Simple literal expressions get a leading-space annotation directly;
-- complex expressions are wrapped in parentheses.
exprToJSWithSpace :: Expr -> JSExpression
exprToJSWithSpace expr = case expr of
  Int n ->
    JS.JSLiteral leadingSpaceAnnot (BS8.pack (show n))
  String builder ->
    JS.JSStringLiteral leadingSpaceAnnot ("'" <> builderToByteString builder <> "'")
  Bool True ->
    JS.JSLiteral leadingSpaceAnnot "true"
  Bool False ->
    JS.JSLiteral leadingSpaceAnnot "false"
  _ ->
    JS.JSExpressionParen leadingSpaceAnnot (exprToJS expr) noAnnot

-- | Build a comma-separated parameter list from a list of 'Name' values.
paramsToJSCommaList :: [Name] -> JS.JSCommaList JSExpression
paramsToJSCommaList [] = JS.JSLNil
paramsToJSCommaList names =
  buildList (reverse names)
  where
    nameToIdent name = JS.JSIdentifier noAnnot (nameToByteString name)
    buildList [n] = JS.JSLOne (nameToIdent n)
    buildList (n:ns) = JS.JSLCons (buildList ns) noAnnot (nameToIdent n)
    buildList [] = JS.JSLNil

-- | Build array element nodes with proper comma separators.
exprToJSArrayElementsWithCommas :: [Expr] -> [JS.JSArrayElement]
exprToJSArrayElementsWithCommas [] = []
exprToJSArrayElementsWithCommas [e] = [JS.JSArrayElement (exprToJS e)]
exprToJSArrayElementsWithCommas (e:es) =
  JS.JSArrayElement (exprToJS e) :
    concatMap (\expr -> [JS.JSArrayComma leadingSpaceAnnot, JS.JSArrayElement (exprToJS expr)]) es

-- | Build a comma-separated argument list from a list of expressions.
argsToJSCommaList :: [Expr] -> JS.JSCommaList JSExpression
argsToJSCommaList [] = JS.JSLNil
argsToJSCommaList [e] = JS.JSLOne (exprToJS e)
argsToJSCommaList args =
  foldr (\expr acc -> JS.JSLCons acc noAnnot (exprToJS expr))
        (JS.JSLOne (exprToJS (last reversedArgs)))
        (init reversedArgs)
  where
    reversedArgs = reverse args

-- | Wrap object fields in a comma-trailing list.
fieldsToJSCommaTrailingList :: [(Name, Expr)] -> JS.JSCommaTrailingList JS.JSObjectProperty
fieldsToJSCommaTrailingList fields = JS.JSCTLNone (fieldsToJSCommaList fields)

-- | Build a comma-separated list of object property nodes.
fieldsToJSCommaList :: [(Name, Expr)] -> JS.JSCommaList JS.JSObjectProperty
fieldsToJSCommaList [] = JS.JSLNil
fieldsToJSCommaList [f] = JS.JSLOne (fieldToJSProperty f)
fieldsToJSCommaList (f:fs) =
  foldr (\field acc -> JS.JSLCons acc noAnnot (fieldToJSProperty field))
        (JS.JSLOne (fieldToJSProperty (last (f:fs))))
        (init (f:fs))

-- | Convert a @(key, value)@ pair to a @language-javascript@ property node.
fieldToJSProperty :: (Name, Expr) -> JS.JSObjectProperty
fieldToJSProperty (key, value) =
  JS.JSPropertyNameandValue
    (JS.JSPropertyIdent noAnnot (nameToByteString key))
    leadingSpaceAnnot
    [exprToJS value]

-- | Convert a 'Stmt' to a @language-javascript@ block, wrapping if needed.
blockFromStmt :: Stmt -> JS.JSBlock
blockFromStmt (Block stmts) = JS.JSBlock noAnnot (map stmtToJS stmts) noAnnot
blockFromStmt stmt = JS.JSBlock noAnnot [stmtToJS stmt] noAnnot

-- | Build a comma-separated var-init list for multiple @var@ declarations.
varsToJSCommaList :: [(Name, Expr)] -> JS.JSCommaList JSExpression
varsToJSCommaList [] = JS.JSLNil
varsToJSCommaList [(name, e)] =
  JS.JSLOne (JS.JSVarInitExpression
    (JS.JSIdentifier leadingSpaceAnnot (nameToByteString name))
    (JS.JSVarInit spaceAnnot (exprToJS e)))
varsToJSCommaList ((name, e):rest) =
  foldr addVar
        (JS.JSLOne (JS.JSVarInitExpression
          (JS.JSIdentifier leadingSpaceAnnot (nameToByteString (fst lastPair)))
          (JS.JSVarInit spaceAnnot (exprToJS (snd lastPair)))))
        (init allPairs)
  where
    allPairs = (name, e) : rest
    lastPair = last allPairs
    addVar (n, expr) acc =
      JS.JSLCons acc noAnnot
        (JS.JSVarInitExpression
          (JS.JSIdentifier leadingSpaceAnnot (nameToByteString n))
          (JS.JSVarInit spaceAnnot (exprToJS expr)))


-- ENCODE USING LANGUAGE-JAVASCRIPT

-- | Render a 'Blaze.Builder' to a 'Data.ByteString.Builder.Builder'.
--
-- Bridges the @blaze-builder@ type returned by 'JSP.renderJS' to the
-- standard @bytestring@ 'Builder' used throughout the Canopy pipeline.
blazeToBuilder :: Blaze.Builder -> Builder
blazeToBuilder = B.lazyByteString . Blaze.toLazyByteString

-- | Render a 'Stmt' to a 'Builder', appending a trailing newline.
stmtToBuilder :: Stmt -> Builder
stmtToBuilder stmt =
  blazeToBuilder (JSP.renderJS (JSAstStatement (stmtToJS stmt) noAnnot))
    <> B.char7 '\n'

-- | Render an 'Expr' to a 'Builder'.
exprToBuilder :: Expr -> Builder
exprToBuilder expr =
  blazeToBuilder (JSP.renderJS (JSAstExpression (exprToJS expr) noAnnot))

-- | Render a 'Stmt' to a 'Builder' using a mode-aware conversion.
stmtToBuilderWithMode :: Mode.Mode -> Stmt -> Builder
stmtToBuilderWithMode mode stmt =
  blazeToBuilder (JSP.renderJS (JSAstStatement (stmtToJSWithMode mode stmt) noAnnot))
    <> B.char7 '\n'

-- | Render an 'Expr' to a 'Builder' using a mode-aware conversion.
exprToBuilderWithMode :: Mode.Mode -> Expr -> Builder
exprToBuilderWithMode mode expr =
  blazeToBuilder (JSP.renderJS (JSAstExpression (exprToJSWithMode mode expr) noAnnot))


-- MODE-AWARE CONVERSION

-- | Convert a 'Stmt' to a JS AST node with mode-specific formatting.
stmtToJSWithMode :: Mode.Mode -> Stmt -> JSStatement
stmtToJSWithMode mode stmt = case stmt of
  Block [] ->
    JS.JSEmptyStatement noAnnot
  Block [singleStmt] ->
    stmtToJSWithMode mode singleStmt
  Block stmts ->
    JS.JSStatementBlock noAnnot (map (stmtToJSWithMode mode) stmts) noAnnot JS.JSSemiAuto
  FunctionStmt name params body ->
    JS.JSFunction noAnnot
      (JS.JSIdentName noAnnot (nameToByteString name))
      noAnnot
      (paramsToJSCommaListWithMode mode params)
      noAnnot
      (JS.JSBlock noAnnot (map (stmtToJSWithMode mode) body) noAnnot)
      JS.JSSemiAuto
  _ ->
    stmtToJS stmt

-- | Convert an 'Expr' to a JS AST node with mode-specific formatting.
exprToJSWithMode :: Mode.Mode -> Expr -> JSExpression
exprToJSWithMode mode expr = case expr of
  Function maybeName params body ->
    JS.JSFunctionExpression
      leadingSpaceAnnot
      (maybe JS.JSIdentNone (JS.JSIdentName noAnnot . nameToByteString) maybeName)
      noAnnot
      (paramsToJSCommaListWithMode mode params)
      noAnnot
      (JS.JSBlock noAnnot (map (stmtToJSWithMode mode) body) noAnnot)
  _ ->
    exprToJS expr

-- | Build a mode-aware comma-separated parameter list.
paramsToJSCommaListWithMode :: Mode.Mode -> [Name] -> JS.JSCommaList JSExpression
paramsToJSCommaListWithMode _ [] = JS.JSLNil
paramsToJSCommaListWithMode mode [param] =
  JS.JSLOne (JS.JSIdentifier (paramAnnotForMode mode) (nameToByteString param))
paramsToJSCommaListWithMode mode (firstParam:restParams) =
  foldr addParam
        (JS.JSLOne (JS.JSIdentifier paramAnnot (nameToByteString firstParam)))
        restParams
  where
    paramAnnot = paramAnnotForMode mode
    addParam param acc =
      JS.JSLCons acc paramAnnot (JS.JSIdentifier paramAnnot (nameToByteString param))


-- ESM MODULE ITEMS


-- | An ESM module-level item.
--
-- Represents constructs that appear at the top level of an ES module:
-- imports, exports, statements, and raw pre-built JavaScript.
--
-- @since 0.20.0
data ModuleItem
  = ImportBare !ByteString
  | ImportNamed ![Name] !ByteString
  | ImportNamedRaw ![ByteString] !ByteString
  | ExportLocals ![Name]
  | ExportLocalsRaw ![ByteString]
  | VarShorthandObject !ByteString ![ByteString]
  | GlobalThisAssignRaw ![ByteString]
  | ModuleStmt !Stmt
  | RawJS !Builder

instance Show ModuleItem where
  show (ImportBare path) = "ImportBare " <> show path
  show (ImportNamed names path) = "ImportNamed " <> show names <> " " <> show path
  show (ImportNamedRaw names path) = "ImportNamedRaw " <> show names <> " " <> show path
  show (ExportLocals names) = "ExportLocals " <> show names
  show (ExportLocalsRaw names) = "ExportLocalsRaw " <> show names
  show (VarShorthandObject name props) = "VarShorthandObject " <> show name <> " " <> show props
  show (GlobalThisAssignRaw names) = "GlobalThisAssignRaw " <> show names
  show (ModuleStmt stmt) = "ModuleStmt " <> show stmt
  show (RawJS _) = "RawJS <builder>"

-- | Render a list of 'ModuleItem' values as ESM module content.
--
-- Each item is rendered individually and concatenated. AST-convertible
-- items go through @language-javascript@ rendering; 'RawJS' items are
-- emitted verbatim.
--
-- @since 0.20.0
moduleToBuilder :: [ModuleItem] -> Builder
moduleToBuilder = mconcat . map moduleItemToBuilder

-- | Render a list of 'ModuleItem' values as formatted, readable ESM content.
--
-- Uses the @language-javascript@ formatted pretty printer with 2-space
-- indentation for human-readable output. Suitable for dev mode where
-- readability of generated JS is important.
--
-- 'RawJS' items are emitted verbatim between formatted AST groups.
-- AST-convertible items are collected into batches and formatted together
-- for consistent indentation.
--
-- @since 0.20.1
moduleToFormattedBuilder :: [ModuleItem] -> Builder
moduleToFormattedBuilder = mconcat . map formatItem
  where
    formatItem (RawJS raw) = raw
    formatItem item =
      blazeToBuilder (JSFmt.formatToBuilder JSFmt.twoSpaceStyle (JS.JSAstModule [toJSModuleItem item] noAnnot))

    toJSModuleItem (ImportBare path) = importBareToJS path
    toJSModuleItem (ImportNamed names path) = importNamedToJS (namesToImportSpecifiers names) path
    toJSModuleItem (ImportNamedRaw rawNames path) = importNamedToJS (rawNamesToImportSpecifiers rawNames) path
    toJSModuleItem (ExportLocals names) = exportLocalsToJS names
    toJSModuleItem (ExportLocalsRaw names) = exportLocalsRawToJS names
    toJSModuleItem (VarShorthandObject name props) = varShorthandObjectToJS name props
    toJSModuleItem (GlobalThisAssignRaw names) = globalThisAssignRawToJS names
    toJSModuleItem (ModuleStmt stmt) = JS.JSModuleStatementListItem (stmtToJS stmt)
    toJSModuleItem (RawJS _) = JS.JSModuleStatementListItem (JS.JSEmptyStatement noAnnot)

-- | Render a single 'ModuleItem' to a 'Builder'.
--
-- 'RawJS' items are emitted verbatim. All other items are converted
-- to @language-javascript@ AST nodes and pretty-printed.
--
-- @since 0.20.0
moduleItemToBuilder :: ModuleItem -> Builder
moduleItemToBuilder (RawJS raw) = raw
moduleItemToBuilder (ImportBare path) =
  renderModuleItem (importBareToJS path)
moduleItemToBuilder (ImportNamed names path) =
  renderModuleItem (importNamedToJS (namesToImportSpecifiers names) path)
moduleItemToBuilder (ImportNamedRaw rawNames path) =
  renderModuleItem (importNamedToJS (rawNamesToImportSpecifiers rawNames) path)
moduleItemToBuilder (ExportLocals names) =
  renderModuleItem (exportLocalsToJS names)
moduleItemToBuilder (ExportLocalsRaw names) =
  renderModuleItem (exportLocalsRawToJS names)
moduleItemToBuilder (VarShorthandObject name props) =
  renderModuleItem (varShorthandObjectToJS name props)
moduleItemToBuilder (GlobalThisAssignRaw names) =
  renderModuleItem (globalThisAssignRawToJS names)
moduleItemToBuilder (ModuleStmt stmt) =
  renderModuleItem (JS.JSModuleStatementListItem (stmtToJS stmt))

-- | Render a single 'JS.JSModuleItem' through the @language-javascript@ printer.
renderModuleItem :: JS.JSModuleItem -> Builder
renderModuleItem item =
  blazeToBuilder (JSP.renderJS (JSAstModule [item] noAnnot))
    <> B.char7 '\n'

-- | Convert a bare import path to a JS AST node.
importBareToJS :: ByteString -> JS.JSModuleItem
importBareToJS path =
  JS.JSModuleImportDeclaration noAnnot
    (JS.JSImportDeclarationBare spaceAnnot path Nothing (JS.JSSemi noAnnot))

-- | Convert named imports + path to a JS AST node.
importNamedToJS :: JS.JSCommaList JS.JSImportSpecifier -> ByteString -> JS.JSModuleItem
importNamedToJS specifiers path =
  JS.JSModuleImportDeclaration noAnnot
    (JS.JSImportDeclaration
      (JS.JSImportClauseNamed
        (JS.JSImportsNamed spaceAnnot specifiers spaceAnnot))
      (JS.JSFromClause spaceAnnot spaceAnnot path)
      Nothing
      (JS.JSSemi noAnnot))

-- | Convert export-locals names to a JS AST node.
exportLocalsToJS :: [Name] -> JS.JSModuleItem
exportLocalsToJS names =
  JS.JSModuleExportDeclaration noAnnot
    (JS.JSExportLocals
      (JS.JSExportClause spaceAnnot (namesToExportSpecifiers names) spaceAnnot)
      (JS.JSSemi noAnnot))

-- | Build a comma-separated list of import specifiers from 'Name' values.
namesToImportSpecifiers :: [Name] -> JS.JSCommaList JS.JSImportSpecifier
namesToImportSpecifiers [] = JS.JSLNil
namesToImportSpecifiers names =
  buildCommaList (map toSpec names)
  where
    toSpec n = JS.JSImportSpecifier (JS.JSIdentName spaceAnnot (nameToByteString n))

-- | Build a comma-separated list of import specifiers from raw 'ByteString' values.
rawNamesToImportSpecifiers :: [ByteString] -> JS.JSCommaList JS.JSImportSpecifier
rawNamesToImportSpecifiers [] = JS.JSLNil
rawNamesToImportSpecifiers names =
  buildCommaList (map toSpec names)
  where
    toSpec n = JS.JSImportSpecifier (JS.JSIdentName spaceAnnot n)

-- | Build a comma-separated list of export specifiers from 'Name' values.
namesToExportSpecifiers :: [Name] -> JS.JSCommaList JS.JSExportSpecifier
namesToExportSpecifiers [] = JS.JSLNil
namesToExportSpecifiers names =
  buildCommaList (map toSpec names)
  where
    toSpec n = JS.JSExportSpecifier (JS.JSIdentName spaceAnnot (nameToByteString n))

-- | Build a generic comma-separated list from a list of values.
buildCommaList :: [a] -> JS.JSCommaList a
buildCommaList [] = JS.JSLNil
buildCommaList [x] = JS.JSLOne x
buildCommaList (first : rest) =
  foldl (\acc x -> JS.JSLCons acc noAnnot x) (JS.JSLOne first) rest


-- SHORTHAND OBJECT AND GLOBALTHIS HELPERS


-- | Build a shorthand object expression @{ name1, name2, ... }@ from raw 'ByteString' names.
--
-- Uses @JSPropertyIdentRef@ for ES2015 shorthand property syntax.
--
-- @since 0.20.0
shorthandObjectExpr :: [ByteString] -> JSExpression
shorthandObjectExpr props =
  JS.JSObjectLiteral spaceAnnot
    (JS.JSCTLNone (buildCommaList (map shorthandProp props)))
    spaceAnnot
  where
    shorthandProp n = JS.JSPropertyIdentRef spaceAnnot n

-- | Convert an @export { ... }@ with raw 'ByteString' names to a JS AST node.
--
-- @since 0.20.0
exportLocalsRawToJS :: [ByteString] -> JS.JSModuleItem
exportLocalsRawToJS names =
  JS.JSModuleExportDeclaration noAnnot
    (JS.JSExportLocals
      (JS.JSExportClause spaceAnnot specs spaceAnnot)
      (JS.JSSemi noAnnot))
  where
    specs = buildCommaList (map toSpec names)
    toSpec n = JS.JSExportSpecifier (JS.JSIdentName spaceAnnot n)

-- | Convert @var name = { prop1, prop2, ... }@ to a JS AST module item.
--
-- @since 0.20.0
varShorthandObjectToJS :: ByteString -> [ByteString] -> JS.JSModuleItem
varShorthandObjectToJS name props =
  JS.JSModuleStatementListItem
    (JS.JSVariable noAnnot
      (JS.JSLOne (JS.JSVarInitExpression
        (JS.JSIdentifier leadingSpaceAnnot name)
        (JS.JSVarInit spaceAnnot (shorthandObjectExpr props))))
      (JS.JSSemi noAnnot))

-- | Convert @Object.assign(globalThis, { name1, name2, ... })@ to a JS AST module item.
--
-- @since 0.20.0
globalThisAssignRawToJS :: [ByteString] -> JS.JSModuleItem
globalThisAssignRawToJS names =
  JS.JSModuleStatementListItem
    (JS.JSExpressionStatement callExpr (JS.JSSemi noAnnot))
  where
    callExpr =
      JS.JSCallExpression
        (JS.JSMemberDot (JS.JSIdentifier noAnnot "Object") noAnnot (JS.JSIdentifier noAnnot "assign"))
        noAnnot
        (JS.JSLCons (JS.JSLOne (JS.JSIdentifier noAnnot "globalThis")) noAnnot (shorthandObjectExpr names))
        noAnnot
