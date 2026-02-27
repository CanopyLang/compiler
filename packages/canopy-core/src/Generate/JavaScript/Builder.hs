{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MagicHash #-}
module Generate.JavaScript.Builder
  ( stmtToBuilder
  , exprToBuilder
  , stmtToBuilderWithMode
  , exprToBuilderWithMode
  , Expr(..), LValue(..)
  , Stmt(..), Case(..)
  , InfixOp(..), PrefixOp(..)
  , sanitizeScriptElementString
  )
  where

-- Using language-javascript 0.8.0.0 with modern JavaScript support
-- https://github.com/quintenkasteel/language-javascript
--
-- NOTE: String intermediates in nameToString/builderToString are required
-- because language-javascript's AST types (JSDecimal, JSIdentifier,
-- JSStringLiteral) all take String arguments. Eliminating these allocations
-- would require forking language-javascript to accept Builder directly.

import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.ByteString.Builder as B
import qualified Generate.JavaScript.Name as Name
import Generate.JavaScript.Name (Name)
import qualified Json.Encode as Json
import qualified Canopy.String as ES
import qualified Canopy.Data.Utf8 as Utf8
import qualified GHC.Word
import qualified Generate.Mode as Mode

-- Language JavaScript 0.8.0.0 imports
import qualified Language.JavaScript.Parser.AST as JS
import Language.JavaScript.Parser.AST (JSAnnot(..), JSAST(..), JSExpression, JSStatement)
import Language.JavaScript.Parser.SrcLocation (TokenPosn(..))
import Language.JavaScript.Parser.Token (CommentAnnotation(..))
import qualified Language.JavaScript.Pretty.Printer as JSP


backslash :: GHC.Word.Word8
backslash = 0x5c

forwardslash :: GHC.Word.Word8
forwardslash = 0x2f

exclamationMark :: GHC.Word.Word8
exclamationMark = 0x21



-- We need to remove escape / because otherwise we can end up with
-- https://github.com/canopy-lang/canopy-make/issues/174 Which is tracked from
-- https://github.com/canopy/compiler/issues/1377
--
-- In particular we are trying to solve problems where string literals are
-- </script> or <!-- Note that this is only a problem for string literals, and
-- in HTML tags, so for efficiency's sake we might choose to only use this where
-- there are indeed string literals and when we are generating a full HTML file
-- (this is not required for script.js as the HTML parser does not run in those)
--
-- We are following the recommendations laid out in the living standard here:
-- https://html.spec.whatwg.org/multipage/scripting.html#restrictions-for-contents-of-script-elements
sanitizeScriptElementString :: ES.String -> ES.String
sanitizeScriptElementString = sanitizeHtmlComment . sanitizeScriptTag

sanitizeScriptTag :: ES.String -> ES.String
sanitizeScriptTag str = Utf8.joinConsecutivePairSep (backslash, forwardslash) (Utf8.split forwardslash str)

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


data LValue
  = LRef Name
  | LDot Expr Name
  | LBracket Expr Expr
  deriving Show



-- STATEMENTS


data Stmt
  = Block [Stmt]
  | EmptyStmt
  | ExprStmt Expr
  | ExprStmtWithSemi Expr  -- Expression statement with explicit semicolon
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
  | FunctionStmt Name [Name] [Stmt]
  deriving Show


data Case
  = Case Expr [Stmt]
  | Default [Stmt]
  deriving Show



-- OPERATORS


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


data PrefixOp
  = PrefixNot        -- !
  | PrefixNegate     -- -
  | PrefixComplement -- ~
  deriving Show



-- LANGUAGE-JAVASCRIPT CONVERSION

-- Convert custom AST to language-javascript AST with proper formatting annotations
noAnnot :: JSAnnot
noAnnot = JSNoAnnot

-- Create annotation with surrounding whitespace for operators and keywords
spaceAnnot :: JSAnnot
spaceAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) " "]

-- Create annotation with leading space for identifiers after operators
leadingSpaceAnnot :: JSAnnot
leadingSpaceAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) " "]

-- Create annotation with newline for statement separation  
newlineAnnot :: JSAnnot
newlineAnnot = JSAnnot (TokenPn 0 0 0) [WhiteSpace (TokenPn 0 0 0) "\n"]

-- Mode-aware annotation functions
annotForMode :: Mode.Mode -> JSAnnot -> JSAnnot
annotForMode mode defaultAnnot = 
  if Mode.isElmCompatible mode 
    then spaceAnnot  -- Use space for elm-compatibility
    else defaultAnnot -- Use original annotation for optimized mode

paramAnnotForMode :: Mode.Mode -> JSAnnot
paramAnnotForMode mode = annotForMode mode noAnnot

-- Note: newlineAfterAnnot was removed as unused

-- Convert Name to String
nameToString :: Name -> String
nameToString = LBS.unpack . B.toLazyByteString . Name.toBuilder

-- Convert Builder to String
builderToString :: Builder -> String
builderToString = LBS.unpack . B.toLazyByteString

-- Wrap expression in parentheses like Elm does for precedence
wrapInParens :: Expr -> JSExpression
wrapInParens expr = JS.JSExpressionParen noAnnot (exprToJS expr) noAnnot

-- Check if expression needs parentheses in ternary context
needsParensInTernary :: Expr -> Bool
needsParensInTernary expr = case expr of
  Infix _ _ _ -> True
  Prefix _ _ -> True
  _ -> False

-- Check if expression needs parentheses as right operand in binary operation
needsParensAsRightOperand :: Expr -> Bool
needsParensAsRightOperand expr = case expr of
  Infix OpAdd _ _ -> True  -- a + (b + c)
  Infix OpSub _ _ -> True  -- a + (b - c) 
  _ -> False

-- Convert custom Expr to JSExpression
exprToJS :: Expr -> JSExpression
exprToJS expr = case expr of
  String builder -> JS.JSStringLiteral noAnnot ("'" ++ builderToString builder ++ "'")
  Float builder -> JS.JSDecimal noAnnot (builderToString builder) 
  Int n -> JS.JSDecimal noAnnot (show n)
  Bool True -> JS.JSLiteral noAnnot "true"
  Bool False -> JS.JSLiteral noAnnot "false"  
  Null -> JS.JSLiteral noAnnot "null"
  Json jsonValue -> JS.JSLiteral noAnnot (LBS.unpack $ B.toLazyByteString $ Json.encodeUgly jsonValue)
  Array exprs -> JS.JSArrayLiteral noAnnot (exprToJSArrayElementsWithCommas exprs) noAnnot
  Object fields -> JS.JSObjectLiteral noAnnot (fieldsToJSCommaTrailingList fields) noAnnot  
  Ref name -> JS.JSIdentifier leadingSpaceAnnot (nameToString name)
  Access obj field -> JS.JSMemberDot (exprToJS obj) noAnnot (JS.JSIdentifier noAnnot (nameToString field))
  Index obj key -> JS.JSMemberSquare (exprToJS obj) noAnnot (exprToJS key) noAnnot
  Prefix PrefixNot e -> JS.JSUnaryExpression (JS.JSUnaryOpNot noAnnot) (exprToJS e)
  Prefix PrefixNegate e -> JS.JSUnaryExpression (JS.JSUnaryOpMinus noAnnot) (exprToJS e)  
  Prefix PrefixComplement e -> JS.JSUnaryExpression (JS.JSUnaryOpTilde noAnnot) (exprToJS e)
  Infix op left right -> 
    let leftJS = exprToJS left
        rightJS = if needsParensAsRightOperand right then wrapInParens right else exprToJS right
    in JS.JSExpressionBinary leftJS (infixOpToJS op) rightJS
  If cond thenExpr elseExpr -> 
    let condJS = if needsParensInTernary cond then wrapInParens cond else exprToJS cond
        thenJS = if needsParensInTernary thenExpr then wrapInParens thenExpr else exprToJS thenExpr
        elseJS = exprToJS elseExpr
    in JS.JSExpressionTernary condJS noAnnot thenJS noAnnot elseJS
  Assign lval e -> JS.JSAssignExpression (lvalueToJS lval) (JS.JSAssign spaceAnnot) (exprToJS e)  
  Call func args -> JS.JSCallExpression (exprToJS func) noAnnot (argsToJSCommaList args) noAnnot
  Function maybeName params body -> 
    JS.JSFunctionExpression 
      leadingSpaceAnnot 
      (maybe JS.JSIdentNone (JS.JSIdentName noAnnot . nameToString) maybeName)
      noAnnot
      (paramsToJSCommaList params)
      noAnnot
      (JS.JSBlock noAnnot (map stmtToJS body) noAnnot)

-- Convert custom Stmt to JSStatement  
stmtToJS :: Stmt -> JSStatement
stmtToJS stmt = case stmt of
  Block [] -> JS.JSEmptyStatement noAnnot
  Block [singleStmt] -> stmtToJS singleStmt  -- Avoid unnecessary block wrapper for single statements
  Block stmts -> JS.JSStatementBlock noAnnot (map stmtToJS stmts) noAnnot (JS.JSSemiAuto)
  EmptyStmt -> JS.JSEmptyStatement noAnnot
  ExprStmt e -> JS.JSExpressionStatement (exprToJS e) (JS.JSSemiAuto)
  ExprStmtWithSemi e -> JS.JSExpressionStatement (exprToJS e) (JS.JSSemi noAnnot)  
  IfStmt cond thenStmt elseStmt ->
    JS.JSIfElse noAnnot leadingSpaceAnnot (exprToJS cond) leadingSpaceAnnot (ensureBlock thenStmt) leadingSpaceAnnot (ensureBlock elseStmt)
    where
      ensureBlock blockStmt = case blockStmt of
        Block _ -> stmtToJS blockStmt
        _ -> JS.JSStatementBlock noAnnot [stmtToJS blockStmt] noAnnot (JS.JSSemiAuto)
  Switch e cases -> JS.JSSwitch leadingSpaceAnnot noAnnot (exprToJS e) noAnnot noAnnot (map caseToJS cases) noAnnot (JS.JSSemiAuto)
  While cond body -> JS.JSWhile leadingSpaceAnnot leadingSpaceAnnot (exprToJS cond) leadingSpaceAnnot (stmtToJS body)
  Break Nothing -> JS.JSBreak leadingSpaceAnnot JS.JSIdentNone (JS.JSSemi noAnnot)
  Break (Just label) -> JS.JSBreak leadingSpaceAnnot (JS.JSIdentName leadingSpaceAnnot (nameToString label)) (JS.JSSemi noAnnot)
  Continue Nothing -> JS.JSContinue leadingSpaceAnnot JS.JSIdentNone (JS.JSSemi noAnnot)
  Continue (Just label) -> JS.JSContinue leadingSpaceAnnot (JS.JSIdentName leadingSpaceAnnot (nameToString label)) (JS.JSSemi noAnnot)
  Labelled label s -> JS.JSLabelled (JS.JSIdentName noAnnot (nameToString label)) noAnnot (stmtToJS s)
  Try tryStmt errName catchStmt ->
    JS.JSTry leadingSpaceAnnot (blockFromStmt tryStmt)
      [JS.JSCatch noAnnot noAnnot (JS.JSIdentifier noAnnot (nameToString errName)) noAnnot (blockFromStmt catchStmt)]
      JS.JSNoFinally
  Throw e -> JS.JSThrow leadingSpaceAnnot (exprToJS e) (JS.JSSemiAuto)
  Return e -> JS.JSReturn leadingSpaceAnnot (Just $ exprToJSWithSpace e) (JS.JSSemi noAnnot)
  Var name e -> JS.JSVariable noAnnot (JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier leadingSpaceAnnot (nameToString name)) (JS.JSVarInit spaceAnnot (exprToJS e)))) (JS.JSSemi noAnnot)
  Vars pairs -> JS.JSVariable noAnnot (varsToJSCommaList pairs) (JS.JSSemi newlineAnnot)
  FunctionStmt name params body ->
    JS.JSFunction noAnnot (JS.JSIdentName leadingSpaceAnnot (nameToString name)) noAnnot (paramsToJSCommaList params) noAnnot (JS.JSBlock noAnnot (map stmtToJS body) noAnnot) (JS.JSSemiAuto)

-- Helper conversion functions
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

lvalueToJS :: LValue -> JSExpression  
lvalueToJS lval = case lval of
  LRef name -> JS.JSIdentifier noAnnot (nameToString name)
  LDot e field -> JS.JSMemberDot (exprToJS e) noAnnot (JS.JSIdentifier noAnnot (nameToString field))
  LBracket e key -> JS.JSMemberSquare (exprToJS e) noAnnot (exprToJS key) noAnnot

caseToJS :: Case -> JS.JSSwitchParts
caseToJS c = case c of
  Case e stmts -> JS.JSCase leadingSpaceAnnot (exprToJSWithSpace e) leadingSpaceAnnot (map stmtToJS stmts)
  Default stmts -> JS.JSDefault leadingSpaceAnnot leadingSpaceAnnot (map stmtToJS stmts)

-- Generate expression with leading space for case statements and return statements
exprToJSWithSpace :: Expr -> JSExpression
exprToJSWithSpace expr = case expr of
  Int n -> JS.JSDecimal leadingSpaceAnnot (show n)
  String builder -> JS.JSStringLiteral leadingSpaceAnnot ("'" ++ builderToString builder ++ "'")
  Bool True -> JS.JSLiteral leadingSpaceAnnot "true"
  Bool False -> JS.JSLiteral leadingSpaceAnnot "false"
  _ -> JS.JSExpressionParen leadingSpaceAnnot (exprToJS expr) noAnnot

-- varPairToJS not needed - using varsToJSCommaList instead

paramsToJSCommaList :: [Name] -> JS.JSCommaList JSExpression
paramsToJSCommaList [] = JS.JSLNil
paramsToJSCommaList names = 
  let nameToIdent name = JS.JSIdentifier noAnnot (nameToString name)
      buildList [n] = JS.JSLOne (nameToIdent n)
      buildList (n:ns) = JS.JSLCons (buildList ns) noAnnot (nameToIdent n)
      buildList [] = JS.JSLNil
  in buildList (reverse names)

-- Proper comma-separated array elements using JSArrayComma
exprToJSArrayElementsWithCommas :: [Expr] -> [JS.JSArrayElement]
exprToJSArrayElementsWithCommas [] = []
exprToJSArrayElementsWithCommas [e] = [JS.JSArrayElement (exprToJS e)]
exprToJSArrayElementsWithCommas (e:es) =
  JS.JSArrayElement (exprToJS e) : concatMap (\expr -> [JS.JSArrayComma leadingSpaceAnnot, JS.JSArrayElement (exprToJS expr)]) es

argsToJSCommaList :: [Expr] -> JS.JSCommaList JSExpression
argsToJSCommaList [] = JS.JSLNil  
argsToJSCommaList [e] = JS.JSLOne (exprToJS e)
argsToJSCommaList args = 
  let reversedArgs = reverse args
  in foldr (\expr acc -> JS.JSLCons acc noAnnot (exprToJS expr)) 
           (JS.JSLOne (exprToJS $ last reversedArgs)) 
           (init reversedArgs)

fieldsToJSCommaTrailingList :: [(Name, Expr)] -> JS.JSCommaTrailingList JS.JSObjectProperty
fieldsToJSCommaTrailingList fields = JS.JSCTLNone (fieldsToJSCommaList fields)

fieldsToJSCommaList :: [(Name, Expr)] -> JS.JSCommaList JS.JSObjectProperty
fieldsToJSCommaList [] = JS.JSLNil
fieldsToJSCommaList [f] = JS.JSLOne (fieldToJSProperty f)
fieldsToJSCommaList (f:fs) =
  foldr (\field acc -> JS.JSLCons acc noAnnot (fieldToJSProperty field))
        (JS.JSLOne (fieldToJSProperty $ last (f:fs)))
        (init (f:fs))

fieldToJSProperty :: (Name, Expr) -> JS.JSObjectProperty  
fieldToJSProperty (key, value) =
  JS.JSPropertyNameandValue
    (JS.JSPropertyIdent noAnnot (nameToString key))
    leadingSpaceAnnot
    [exprToJS value]

blockFromStmt :: Stmt -> JS.JSBlock
blockFromStmt (Block stmts) = JS.JSBlock noAnnot (map stmtToJS stmts) noAnnot
blockFromStmt stmt = JS.JSBlock noAnnot [stmtToJS stmt] noAnnot

varsToJSCommaList :: [(Name, Expr)] -> JS.JSCommaList JSExpression
varsToJSCommaList [] = JS.JSLNil
varsToJSCommaList [(name, e)] = JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier leadingSpaceAnnot (nameToString name)) (JS.JSVarInit spaceAnnot (exprToJS e)))
varsToJSCommaList ((name, e):rest) = 
  foldr (\(n, expr) acc -> JS.JSLCons acc noAnnot (JS.JSVarInitExpression (JS.JSIdentifier leadingSpaceAnnot (nameToString n)) (JS.JSVarInit spaceAnnot (exprToJS expr)))) 
        (JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier leadingSpaceAnnot (nameToString $ fst $ last ((name, e):rest))) (JS.JSVarInit spaceAnnot (exprToJS $ snd $ last ((name, e):rest))))) 
        (init ((name, e):rest))


-- ENCODE USING LANGUAGE-JAVASCRIPT

stmtToBuilder :: Stmt -> Builder
stmtToBuilder stmt = B.stringUtf8 (JSP.renderToString (JSAstStatement (stmtToJS stmt) noAnnot)) <> B.stringUtf8 "\n"


exprToBuilder :: Expr -> Builder
exprToBuilder expr = B.stringUtf8 $ JSP.renderToString $ JSAstExpression (exprToJS expr) noAnnot

-- Mode-aware versions for elm-compatibility
stmtToBuilderWithMode :: Mode.Mode -> Stmt -> Builder
stmtToBuilderWithMode mode stmt = B.stringUtf8 (JSP.renderToString (JSAstStatement (stmtToJSWithMode mode stmt) noAnnot)) <> B.stringUtf8 "\n"

exprToBuilderWithMode :: Mode.Mode -> Expr -> Builder
exprToBuilderWithMode mode expr = B.stringUtf8 $ JSP.renderToString $ JSAstExpression (exprToJSWithMode mode expr) noAnnot

-- Mode-aware AST conversion functions
stmtToJSWithMode :: Mode.Mode -> Stmt -> JSStatement
stmtToJSWithMode mode stmt = case stmt of
  Block [] -> JS.JSEmptyStatement noAnnot
  Block [singleStmt] -> stmtToJSWithMode mode singleStmt  -- Avoid unnecessary block wrapper for single statements
  Block stmts -> JS.JSStatementBlock noAnnot (map (stmtToJSWithMode mode) stmts) noAnnot (JS.JSSemiAuto)
  FunctionStmt name params body ->
    JS.JSFunction noAnnot (JS.JSIdentName noAnnot (nameToString name)) noAnnot (paramsToJSCommaListWithMode mode params) noAnnot (JS.JSBlock noAnnot (map (stmtToJSWithMode mode) body) noAnnot) (JS.JSSemiAuto)
  _ -> stmtToJS stmt -- Use original for other statements

exprToJSWithMode :: Mode.Mode -> Expr -> JSExpression  
exprToJSWithMode mode expr = case expr of
  Function maybeName params body -> 
    JS.JSFunctionExpression 
      leadingSpaceAnnot 
      (maybe JS.JSIdentNone (JS.JSIdentName noAnnot . nameToString) maybeName)
      noAnnot
      (paramsToJSCommaListWithMode mode params)
      noAnnot
      (JS.JSBlock noAnnot (map (stmtToJSWithMode mode) body) noAnnot)
  _ -> exprToJS expr -- Use original for other expressions

-- Mode-aware parameter list conversion  
paramsToJSCommaListWithMode :: Mode.Mode -> [Name] -> JS.JSCommaList JSExpression
paramsToJSCommaListWithMode mode params = 
  case params of
    [] -> JS.JSLNil
    [param] -> JS.JSLOne (JS.JSIdentifier (paramAnnotForMode mode) (nameToString param))
    (firstParam:restParams) -> 
      let paramAnnot = paramAnnotForMode mode
      in foldr (\param acc -> JS.JSLCons acc (paramAnnotForMode mode) (JS.JSIdentifier paramAnnot (nameToString param))) 
               (JS.JSLOne (JS.JSIdentifier paramAnnot (nameToString firstParam)))
               restParams

-- Old implementation removed - now using language-javascript 0.8.0.0 for all rendering
