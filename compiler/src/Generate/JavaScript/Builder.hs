{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MagicHash #-}
module Generate.JavaScript.Builder
  ( stmtToBuilder
  , exprToBuilder
  , Expr(..), LValue(..)
  , Stmt(..), Case(..)
  , InfixOp(..), PrefixOp(..)
  , sanitizeScriptElementString
  )
  where

-- Using language-javascript 0.8.0.0 with modern JavaScript support
-- https://github.com/quintenkasteel/language-javascript

import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.ByteString.Builder as B
import qualified Generate.JavaScript.Name as Name
import Generate.JavaScript.Name (Name)
import qualified Json.Encode as Json
import qualified Canopy.String as ES
import qualified Data.Utf8 as Utf8
import qualified GHC.Word

-- Language JavaScript 0.8.0.0 imports
import qualified Language.JavaScript.Parser.AST as JS
import Language.JavaScript.Parser.AST (JSAnnot(..), JSAST(..), JSExpression, JSStatement)
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

-- Convert custom AST to language-javascript AST
noAnnot :: JSAnnot
noAnnot = JSNoAnnot

-- Convert Name to String
nameToString :: Name -> String
nameToString = LBS.unpack . B.toLazyByteString . Name.toBuilder

-- Convert Builder to String  
builderToString :: Builder -> String
builderToString = LBS.unpack . B.toLazyByteString

-- Convert custom Expr to JSExpression
exprToJS :: Expr -> JSExpression
exprToJS expr = case expr of
  String builder -> JS.JSStringLiteral noAnnot (show $ builderToString builder)
  Float builder -> JS.JSDecimal noAnnot (builderToString builder) 
  Int n -> JS.JSDecimal noAnnot (show n)
  Bool True -> JS.JSLiteral noAnnot "true"
  Bool False -> JS.JSLiteral noAnnot "false"  
  Null -> JS.JSLiteral noAnnot "null"
  Json jsonValue -> JS.JSLiteral noAnnot (LBS.unpack $ B.toLazyByteString $ Json.encodeUgly jsonValue)
  Array exprs -> JS.JSArrayLiteral noAnnot (exprToJSArrayElements exprs) noAnnot
  Object fields -> JS.JSObjectLiteral noAnnot (fieldsToJSCommaTrailingList fields) noAnnot  
  Ref name -> JS.JSIdentifier noAnnot (nameToString name)
  Access obj field -> JS.JSMemberDot (exprToJS obj) noAnnot (JS.JSIdentifier noAnnot (nameToString field))
  Index obj key -> JS.JSMemberSquare (exprToJS obj) noAnnot (exprToJS key) noAnnot
  Prefix PrefixNot e -> JS.JSUnaryExpression (JS.JSUnaryOpNot noAnnot) (exprToJS e)
  Prefix PrefixNegate e -> JS.JSUnaryExpression (JS.JSUnaryOpMinus noAnnot) (exprToJS e)  
  Prefix PrefixComplement e -> JS.JSUnaryExpression (JS.JSUnaryOpTilde noAnnot) (exprToJS e)
  Infix op left right -> JS.JSExpressionBinary (exprToJS left) (infixOpToJS op) (exprToJS right)
  If cond thenExpr elseExpr -> JS.JSExpressionTernary (exprToJS cond) noAnnot (exprToJS thenExpr) noAnnot (exprToJS elseExpr)
  Assign lval e -> JS.JSAssignExpression (lvalueToJS lval) (JS.JSAssign noAnnot) (exprToJS e)  
  Call func args -> JS.JSCallExpression (exprToJS func) noAnnot (argsToJSCommaList args) noAnnot
  Function maybeName params body -> 
    JS.JSFunctionExpression 
      noAnnot 
      (maybe JS.JSIdentNone (JS.JSIdentName noAnnot . nameToString) maybeName)
      noAnnot
      (paramsToJSCommaList params)
      noAnnot
      (JS.JSBlock noAnnot (map stmtToJS body) noAnnot)

-- Convert custom Stmt to JSStatement  
stmtToJS :: Stmt -> JSStatement
stmtToJS stmt = case stmt of
  Block stmts -> JS.JSStatementBlock noAnnot (map stmtToJS stmts) noAnnot (JS.JSSemiAuto)
  EmptyStmt -> JS.JSEmptyStatement noAnnot
  ExprStmt e -> JS.JSExpressionStatement (exprToJS e) (JS.JSSemiAuto)  
  IfStmt cond thenStmt elseStmt -> 
    JS.JSIfElse noAnnot noAnnot (exprToJS cond) noAnnot (stmtToJS thenStmt) noAnnot (stmtToJS elseStmt)
  Switch e cases -> JS.JSSwitch noAnnot noAnnot (exprToJS e) noAnnot noAnnot (map caseToJS cases) noAnnot (JS.JSSemiAuto)
  While cond body -> JS.JSWhile noAnnot noAnnot (exprToJS cond) noAnnot (stmtToJS body)
  Break Nothing -> JS.JSBreak noAnnot JS.JSIdentNone (JS.JSSemiAuto)
  Break (Just label) -> JS.JSBreak noAnnot (JS.JSIdentName noAnnot (nameToString label)) (JS.JSSemiAuto)
  Continue Nothing -> JS.JSContinue noAnnot JS.JSIdentNone (JS.JSSemiAuto)
  Continue (Just label) -> JS.JSContinue noAnnot (JS.JSIdentName noAnnot (nameToString label)) (JS.JSSemiAuto)
  Labelled label s -> JS.JSLabelled (JS.JSIdentName noAnnot (nameToString label)) noAnnot (stmtToJS s)
  Try tryStmt errName catchStmt -> 
    JS.JSTry noAnnot (blockFromStmt tryStmt) 
      [JS.JSCatch noAnnot noAnnot (JS.JSIdentifier noAnnot (nameToString errName)) noAnnot (blockFromStmt catchStmt)]
      JS.JSNoFinally
  Throw e -> JS.JSThrow noAnnot (exprToJS e) (JS.JSSemiAuto)
  Return e -> JS.JSReturn noAnnot (Just $ exprToJS e) (JS.JSSemiAuto)
  Var name e -> JS.JSVariable noAnnot (JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier noAnnot (nameToString name)) (JS.JSVarInit noAnnot (exprToJS e)))) (JS.JSSemiAuto)
  Vars pairs -> JS.JSVariable noAnnot (varsToJSCommaList pairs) (JS.JSSemiAuto)
  FunctionStmt name params body ->
    JS.JSFunction noAnnot (JS.JSIdentName noAnnot (nameToString name)) noAnnot (paramsToJSCommaList params) noAnnot (JS.JSBlock noAnnot (map stmtToJS body) noAnnot) (JS.JSSemiAuto)

-- Helper conversion functions
infixOpToJS :: InfixOp -> JS.JSBinOp
infixOpToJS op = case op of
  OpAdd -> JS.JSBinOpPlus noAnnot
  OpSub -> JS.JSBinOpMinus noAnnot
  OpMul -> JS.JSBinOpTimes noAnnot
  OpDiv -> JS.JSBinOpDivide noAnnot
  OpMod -> JS.JSBinOpMod noAnnot
  OpEq -> JS.JSBinOpStrictEq noAnnot  
  OpNe -> JS.JSBinOpStrictNeq noAnnot
  OpLt -> JS.JSBinOpLt noAnnot
  OpLe -> JS.JSBinOpLe noAnnot
  OpGt -> JS.JSBinOpGt noAnnot
  OpGe -> JS.JSBinOpGe noAnnot
  OpAnd -> JS.JSBinOpAnd noAnnot
  OpOr -> JS.JSBinOpOr noAnnot
  OpBitwiseAnd -> JS.JSBinOpBitAnd noAnnot
  OpBitwiseXor -> JS.JSBinOpBitXor noAnnot
  OpBitwiseOr -> JS.JSBinOpBitOr noAnnot
  OpLShift -> JS.JSBinOpLsh noAnnot
  OpSpRShift -> JS.JSBinOpRsh noAnnot
  OpZfRShift -> JS.JSBinOpUrsh noAnnot

lvalueToJS :: LValue -> JSExpression  
lvalueToJS lval = case lval of
  LRef name -> JS.JSIdentifier noAnnot (nameToString name)
  LDot e field -> JS.JSMemberDot (exprToJS e) noAnnot (JS.JSIdentifier noAnnot (nameToString field))
  LBracket e key -> JS.JSMemberSquare (exprToJS e) noAnnot (exprToJS key) noAnnot

caseToJS :: Case -> JS.JSSwitchParts  
caseToJS c = case c of
  Case e stmts -> JS.JSCase noAnnot (exprToJS e) noAnnot (map stmtToJS stmts)
  Default stmts -> JS.JSDefault noAnnot noAnnot (map stmtToJS stmts)

-- varPairToJS not needed - using varsToJSCommaList instead

paramsToJSCommaList :: [Name] -> JS.JSCommaList JSExpression
paramsToJSCommaList [] = JS.JSLNil
paramsToJSCommaList [n] = JS.JSLOne (JS.JSIdentifier noAnnot (nameToString n))  
paramsToJSCommaList (n:ns) = 
  foldr (\name acc -> JS.JSLCons acc noAnnot (JS.JSIdentifier noAnnot (nameToString name))) 
        (JS.JSLOne (JS.JSIdentifier noAnnot (nameToString $ last (n:ns)))) 
        (init (n:ns))

exprToJSArrayElements :: [Expr] -> [JS.JSArrayElement]
exprToJSArrayElements = map (JS.JSArrayElement . exprToJS)

argsToJSCommaList :: [Expr] -> JS.JSCommaList JSExpression
argsToJSCommaList [] = JS.JSLNil  
argsToJSCommaList [e] = JS.JSLOne (exprToJS e)
argsToJSCommaList (e:es) = 
  foldr (\expr acc -> JS.JSLCons acc noAnnot (exprToJS expr)) 
        (JS.JSLOne (exprToJS $ last (e:es))) 
        (init (e:es))

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
    noAnnot
    [exprToJS value]

blockFromStmt :: Stmt -> JS.JSBlock
blockFromStmt (Block stmts) = JS.JSBlock noAnnot (map stmtToJS stmts) noAnnot
blockFromStmt stmt = JS.JSBlock noAnnot [stmtToJS stmt] noAnnot

varsToJSCommaList :: [(Name, Expr)] -> JS.JSCommaList JSExpression
varsToJSCommaList [] = JS.JSLNil
varsToJSCommaList [(name, e)] = JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier noAnnot (nameToString name)) (JS.JSVarInit noAnnot (exprToJS e)))
varsToJSCommaList ((name, e):rest) = 
  foldr (\(n, expr) acc -> JS.JSLCons acc noAnnot (JS.JSVarInitExpression (JS.JSIdentifier noAnnot (nameToString n)) (JS.JSVarInit noAnnot (exprToJS expr)))) 
        (JS.JSLOne (JS.JSVarInitExpression (JS.JSIdentifier noAnnot (nameToString $ fst $ last ((name, e):rest))) (JS.JSVarInit noAnnot (exprToJS $ snd $ last ((name, e):rest))))) 
        (init ((name, e):rest))


-- ENCODE USING LANGUAGE-JAVASCRIPT


stmtToBuilder :: Stmt -> Builder
stmtToBuilder stmt = B.stringUtf8 $ JSP.renderToString $ JSAstStatement (stmtToJS stmt) noAnnot


exprToBuilder :: Expr -> Builder
exprToBuilder expr = B.stringUtf8 $ JSP.renderToString $ JSAstExpression (exprToJS expr) noAnnot



-- Old implementation removed - now using language-javascript 0.8.0.0 for all rendering
