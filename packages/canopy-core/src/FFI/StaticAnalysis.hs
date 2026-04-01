{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Static analysis of FFI JavaScript files.
--
-- Detects type inconsistencies between @canopy-type annotations and actual
-- JavaScript code at compile time, similar to Facebook's Flow type checker.
-- This provides compile-time safety for the FFI boundary, catching issues
-- that would otherwise only manifest as runtime errors.
--
-- == Analysis Capabilities
--
-- * Mixed-type operation detection (@number + string@)
-- * Nullable return detection for non-Maybe declared types
-- * Missing return path detection (if without else)
-- * Loose equality detection (@==@ instead of @===@)
-- * Async function / Task type mismatch detection
-- * Result tag construction validation
-- * Return type consistency checking
--
-- == Architecture
--
-- The analyzer operates on the @language-javascript@ AST (already parsed
-- during JSDoc extraction) and the declared @canopy-type annotations.
-- It performs lightweight type inference on JavaScript expressions, then
-- compares inferred types against declared types to find inconsistencies.
--
-- @since 0.20.0
module FFI.StaticAnalysis
  ( -- * Analysis Entry Point
    analyzeFFIFile,

    -- * Result Types
    AnalysisResult (..),
    FFIWarning (..),

    -- * Severity Classification
    FFISeverity (..),
    warningSeverity,

    -- * Inferred Types
    InferredType (..),

    -- * Expression Inference (exported for testing)
    inferExprType,

    -- * Statement Analysis (exported for testing)
    analyzeReturnPaths,
    ReturnInfo (..),

    -- * Helpers (exported for testing)
    commaListToList,
    trailingListToList,
    extractAnnotLine,
  )
where

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text.Encoding as TextEnc
import FFI.Types (FFIType (..))
import qualified FFI.TypeParser as TypeParser
import Language.JavaScript.Parser.AST
  ( JSAnnot (..),
    JSArrayElement (..),
    JSBinOp (..),
    JSBlock (..),
    JSCommaList (..),
    JSCommaTrailingList (..),
    JSExpression (..),
    JSIdent (..),
    JSObjectProperty (..),
    JSPropertyName (..),
    JSStatement (..),
    JSUnaryOp (..),
  )
import qualified Language.JavaScript.Parser.AST as JSAST
import Language.JavaScript.Parser.SrcLocation (TokenPosn (..))

-- INFERRED TYPES

-- | Inferred type from JavaScript expression analysis.
--
-- Represents the type that a JavaScript expression is determined to produce
-- based on static analysis of the AST. This is a lightweight inference --
-- not a full type system, but sufficient to catch common FFI boundary errors.
--
-- @since 0.20.0
data InferredType
  = -- | JavaScript number (typeof === "number")
    InfNumber
  | -- | JavaScript string (typeof === "string")
    InfString
  | -- | JavaScript boolean (typeof === "boolean")
    InfBoolean
  | -- | JavaScript null or undefined
    InfNull
  | -- | Array with inferred element type
    InfArray !InferredType
  | -- | Object with inferred field types
    InfObject ![(Text, InferredType)]
  | -- | Promise / async result
    InfPromise !InferredType
  | -- | Union of possible types (e.g., from ternary or if/else)
    InfUnion ![InferredType]
  | -- | Type cannot be determined statically
    InfUnknown
  deriving (Eq, Show)

-- WARNING TYPES

-- | Warning produced by FFI static analysis.
--
-- Each warning identifies a specific issue in the JavaScript FFI code
-- along with its location (line number) and a human-readable description.
--
-- @since 0.20.0
data FFIWarning
  = -- | Mixed-type operation (e.g., @number + string@)
    MixedTypeOperation !Int !Text !Text
  | -- | Function can return null/undefined but declared as non-Maybe
    NullableReturn !Int !Text
  | -- | Not all code paths return a value
    MissingReturnPath !Int !Text
  | -- | Inferred return type does not match declared @canopy-type
    ReturnTypeMismatch !Int !Text !InferredType !FFIType
  | -- | Loose equality (@==@ instead of @===@)
    LooseEquality !Int !Text
  | -- | Async function but @canopy-type does not use Task
    AsyncWithoutTask !Int !Text
  | -- | Returns value without @{ $: "Ok"/"Err" }@ wrapper for Result type
    MissingResultTag !Int !Text
  | -- | Array contains mixed element types
    MixedArrayElements !Int !Text
  | -- | JS function parameter count does not match @canopy-type arity
    ArityMismatch !Int !Text !Int !Int
  deriving (Eq, Show)

-- SEVERITY CLASSIFICATION

-- | Severity level for FFI static analysis warnings.
--
-- Severe issues block compilation; advisory issues are emitted as warnings.
--
-- @since 0.20.1
data FFISeverity
  = -- | Blocks compilation — type safety is compromised
    FFIError
  | -- | Allows compilation — potential issue that may not cause runtime failure
    FFIWarningLevel
  deriving (Eq, Show)

-- | Classify an 'FFIWarning' by severity.
--
-- Errors (block compilation):
--
-- * 'ReturnTypeMismatch' — declared type contradicts inferred return
-- * 'NullableReturn' — function can return null but type is non-Maybe
-- * 'AsyncWithoutTask' — async function without Task return type
-- * 'MissingResultTag' — Result type without @$@ tag construction
--
-- Warnings (allow compilation):
--
-- * 'LooseEquality' — @==@ instead of @===@
-- * 'MixedArrayElements' — heterogeneous array elements
-- * 'MissingReturnPath' — some code paths lack explicit return
-- * 'MixedTypeOperation' — operands of different types
--
-- @since 0.20.1
warningSeverity :: FFIWarning -> FFISeverity
warningSeverity (ReturnTypeMismatch {}) = FFIError
warningSeverity (NullableReturn {}) = FFIError
warningSeverity (AsyncWithoutTask {}) = FFIError
warningSeverity (MissingResultTag {}) = FFIError
warningSeverity (LooseEquality {}) = FFIWarningLevel
warningSeverity (MixedArrayElements {}) = FFIWarningLevel
warningSeverity (MissingReturnPath {}) = FFIWarningLevel
warningSeverity (ArityMismatch {}) = FFIError
warningSeverity (MixedTypeOperation {}) = FFIWarningLevel

-- ANALYSIS RESULT

-- | Result of analyzing an FFI JavaScript file.
--
-- Contains all warnings discovered during static analysis, plus any
-- inferred type information that was gathered.
--
-- @since 0.20.0
data AnalysisResult = AnalysisResult
  { _analysisWarnings :: ![FFIWarning],
    _analysisInferred :: !(Map.Map Text InferredType)
  }
  deriving (Eq, Show)

-- RETURN PATH INFO

-- | Information about a single return path in a function body.
--
-- @since 0.20.0
data ReturnInfo
  = -- | Explicit return with an expression
    ExplicitReturn !Int !InferredType
  | -- | Implicit undefined return (falling off end of function or bare return)
    ImplicitUndefined !Int
  deriving (Eq, Show)

-- ENTRY POINT

-- | Analyze an FFI JavaScript file for type safety issues.
--
-- Examines each function in the parsed JavaScript AST, comparing its
-- behavior against the declared @canopy-type annotations. Detects mixed-type
-- operations, nullable returns, missing return paths, loose equality, and
-- async/Task mismatches.
--
-- @since 0.20.0
analyzeFFIFile ::
  -- | Parsed JavaScript statements
  [JSStatement] ->
  -- | Declared @canopy-type annotations (function name -> type)
  Map.Map Text FFIType ->
  AnalysisResult
analyzeFFIFile statements declaredTypes =
  AnalysisResult
    { _analysisWarnings = functionWarnings ++ globalWarnings,
      _analysisInferred = inferredMap
    }
  where
    functions = extractFunctions statements
    functionWarnings = concatMap (analyzeFunction declaredTypes) functions
    globalWarnings = concatMap analyzeStatementWarnings statements
    inferredMap = Map.fromList (concatMap inferFunctionEntry functions)

-- FUNCTION EXTRACTION

-- | A JavaScript function extracted from the AST for analysis.
data JSFunc = JSFunc
  { _jsFuncName :: !Text,
    _jsFuncLine :: !Int,
    _jsFuncIsAsync :: !Bool,
    _jsFuncParams :: !Int,
    _jsFuncBody :: !JSBlock
  }

-- | Extract all named functions from a list of statements.
extractFunctions :: [JSStatement] -> [JSFunc]
extractFunctions = concatMap extractFromStatement

-- | Extract function declarations from a single statement.
extractFromStatement :: JSStatement -> [JSFunc]
extractFromStatement = \case
  JSFunction annot ident _ params _ body _ ->
    identToFunc annot ident False (countCommaList params) body
  JSAsyncFunction _ annot ident _ params _ body _ ->
    identToFunc annot ident True (countCommaList params) body
  JSAST.JSGenerator _ annot ident _ params _ body _ ->
    identToFunc annot ident False (countCommaList params) body
  JSStatementBlock _ stmts _ _ ->
    concatMap extractFromStatement stmts
  _ -> []

-- | Build a JSFunc from an identifier and body, if the identifier is named.
identToFunc :: JSAnnot -> JSIdent -> Bool -> Int -> JSBlock -> [JSFunc]
identToFunc annot ident isAsync paramCount body =
  case ident of
    JSIdentName _ nameBS ->
      [ JSFunc
          { _jsFuncName = TextEnc.decodeUtf8Lenient nameBS,
            _jsFuncLine = extractAnnotLine annot,
            _jsFuncIsAsync = isAsync,
            _jsFuncParams = paramCount,
            _jsFuncBody = body
          }
      ]
    JSIdentNone -> []

-- | Count items in a comma-separated parameter list.
countCommaList :: JSCommaList a -> Int
countCommaList JSLNil = 0
countCommaList (JSLOne _) = 1
countCommaList cl = length (commaListToList cl)

-- FUNCTION ANALYSIS

-- | Analyze a single function against declared types.
analyzeFunction :: Map.Map Text FFIType -> JSFunc -> [FFIWarning]
analyzeFunction declaredTypes func =
  arityWarnings ++ asyncWarnings ++ returnWarnings ++ bodyWarnings
  where
    name = _jsFuncName func
    line = _jsFuncLine func
    declared = Map.lookup name declaredTypes
    arityWarnings = checkArityMismatch line name (_jsFuncParams func) declared
    asyncWarnings = checkAsyncMismatch line name (_jsFuncIsAsync func) declared
    returnWarnings = analyzeReturns line name (_jsFuncBody func) declared
    bodyWarnings = analyzeBodyExpressions name (_jsFuncBody func)

-- | Check if JS parameter count matches declared @canopy-type arity.
--
-- Only checks when the declared type is a function type (arity > 0).
-- Non-function types (arity 0) are skipped since the JS function may
-- be a thunk or wrapper.
checkArityMismatch :: Int -> Text -> Int -> Maybe FFIType -> [FFIWarning]
checkArityMismatch line name jsParams (Just declaredType)
  | declaredArity > 0 && jsParams /= declaredArity =
      [ArityMismatch line name jsParams declaredArity]
  | otherwise = []
  where
    declaredArity = TypeParser.countArity declaredType
checkArityMismatch _ _ _ Nothing = []

-- | Build the inferred type entry for a function (for the result map).
inferFunctionEntry :: JSFunc -> [(Text, InferredType)]
inferFunctionEntry func =
  [(name, inferReturnType (_jsFuncBody func))]
  where
    name = _jsFuncName func

-- ASYNC MISMATCH DETECTION

-- | Check if an async function is declared without Task type.
checkAsyncMismatch :: Int -> Text -> Bool -> Maybe FFIType -> [FFIWarning]
checkAsyncMismatch line name True (Just declaredType)
  | not (isTaskType declaredType) = [AsyncWithoutTask line name]
checkAsyncMismatch _ _ _ _ = []

-- | Check whether an FFIType is a Task type.
isTaskType :: FFIType -> Bool
isTaskType (FFITask _ _) = True
isTaskType (FFIFunctionType _ ret) = isTaskType ret
isTaskType _ = False

-- RETURN PATH ANALYSIS

-- | Analyze all return paths of a function and check for issues.
analyzeReturns :: Int -> Text -> JSBlock -> Maybe FFIType -> [FFIWarning]
analyzeReturns line name body declared =
  nullableWarnings ++ missingReturnWarnings ++ typeMismatchWarnings ++ resultTagWarnings
  where
    paths = analyzeReturnPaths body
    hasImplicitUndefined = any isImplicitUndefined paths
    nullableWarnings = checkNullableReturn line name hasImplicitUndefined declared
    missingReturnWarnings = checkMissingReturn line name paths
    typeMismatchWarnings = maybe [] (checkReturnTypes name paths) declared
    resultTagWarnings = maybe [] (checkResultTags name paths) declared

-- | Collect all return paths from a function body.
analyzeReturnPaths :: JSBlock -> [ReturnInfo]
analyzeReturnPaths (JSBlock _ stmts _) =
  collectReturns stmts

-- | Collect return information from a list of statements.
collectReturns :: [JSStatement] -> [ReturnInfo]
collectReturns [] = [ImplicitUndefined 0]
collectReturns stmts =
  maybe [ImplicitUndefined (lastStmtLine stmts)] id (collectReturnsExplicit stmts)

-- | Try to collect explicit returns; returns Nothing if no explicit return found.
collectReturnsExplicit :: [JSStatement] -> Maybe [ReturnInfo]
collectReturnsExplicit [] = Nothing
collectReturnsExplicit (stmt : rest) =
  case stmt of
    JSReturn annot mexpr _ ->
      Just [returnInfoFromExpr (extractAnnotLine annot) mexpr]
    JSIfElse _ _ _ _ thenStmt _ elseStmt ->
      combineIfElseReturns thenStmt elseStmt rest
    JSIf _ _ _ _ thenStmt ->
      addImplicitPath thenStmt rest
    JSTry _ (JSBlock _ tryStmts _) catches _ ->
      combineTryCatchReturns tryStmts catches rest
    JSStatementBlock _ innerStmts _ _ ->
      collectReturnsExplicit (innerStmts ++ rest)
    _ -> collectReturnsExplicit rest

-- | Combine return paths from if/else branches.
combineIfElseReturns :: JSStatement -> JSStatement -> [JSStatement] -> Maybe [ReturnInfo]
combineIfElseReturns thenStmt elseStmt rest =
  case (stmtReturns thenStmt, stmtReturns elseStmt) of
    (Just thenRets, Just elseRets) -> Just (thenRets ++ elseRets)
    (Just thenRets, Nothing) ->
      fmap (thenRets ++) (collectReturnsExplicit rest)
    (Nothing, Just elseRets) ->
      fmap (elseRets ++) (collectReturnsExplicit rest)
    (Nothing, Nothing) -> collectReturnsExplicit rest

-- | Add implicit undefined path for an if-without-else.
addImplicitPath :: JSStatement -> [JSStatement] -> Maybe [ReturnInfo]
addImplicitPath thenStmt rest =
  case stmtReturns thenStmt of
    Just thenRets ->
      Just (thenRets ++ maybe [ImplicitUndefined 0] id (collectReturnsExplicit rest))
    Nothing -> collectReturnsExplicit rest

-- | Combine returns from try/catch blocks.
combineTryCatchReturns :: [JSStatement] -> [JSAST.JSTryCatch] -> [JSStatement] -> Maybe [ReturnInfo]
combineTryCatchReturns tryStmts catches rest =
  case (collectReturnsExplicit tryStmts, catchReturns) of
    (Just tryRets, Just catchRets) -> Just (tryRets ++ catchRets)
    (Just tryRets, Nothing) ->
      fmap (tryRets ++) (collectReturnsExplicit rest)
    (Nothing, Just catchRets) ->
      fmap (catchRets ++) (collectReturnsExplicit rest)
    (Nothing, Nothing) -> collectReturnsExplicit rest
  where
    catchReturns = collectCatchReturns catches

-- | Collect returns from catch clauses.
collectCatchReturns :: [JSAST.JSTryCatch] -> Maybe [ReturnInfo]
collectCatchReturns [] = Nothing
collectCatchReturns (JSAST.JSCatch _ _ _ _ (JSBlock _ stmts _) : _) =
  collectReturnsExplicit stmts
collectCatchReturns (_ : rest) = collectCatchReturns rest

-- | Get return info from a single statement (for branch analysis).
stmtReturns :: JSStatement -> Maybe [ReturnInfo]
stmtReturns (JSReturn annot mexpr _) =
  Just [returnInfoFromExpr (extractAnnotLine annot) mexpr]
stmtReturns (JSStatementBlock _ stmts _ _) =
  collectReturnsExplicit stmts
stmtReturns (JSIfElse _ _ _ _ thenStmt _ elseStmt) =
  combineIfElseReturns thenStmt elseStmt []
stmtReturns _ = Nothing

-- | Build a ReturnInfo from an optional return expression.
returnInfoFromExpr :: Int -> Maybe JSExpression -> ReturnInfo
returnInfoFromExpr line Nothing = ImplicitUndefined line
returnInfoFromExpr line (Just expr) = ExplicitReturn line (inferExprType expr)

-- | Check whether a return path is an implicit undefined.
isImplicitUndefined :: ReturnInfo -> Bool
isImplicitUndefined (ImplicitUndefined _) = True
isImplicitUndefined _ = False

-- | Get the line number of the last statement in a list.
lastStmtLine :: [JSStatement] -> Int
lastStmtLine [] = 0
lastStmtLine stmts = extractStmtLine (last stmts)

-- RETURN CHECKERS

-- | Warn if function can return null/undefined but is declared as non-Maybe.
checkNullableReturn :: Int -> Text -> Bool -> Maybe FFIType -> [FFIWarning]
checkNullableReturn line name True (Just declared)
  | not (isMaybeType declared) && not (isUnitType declared) =
      [NullableReturn line name]
checkNullableReturn _ _ _ _ = []

-- | Warn if there are both explicit and implicit returns (missing return path).
checkMissingReturn :: Int -> Text -> [ReturnInfo] -> [FFIWarning]
checkMissingReturn line name paths
  | hasExplicit && hasImplicit = [MissingReturnPath line name]
  | otherwise = []
  where
    hasExplicit = any isExplicitReturn paths
    hasImplicit = any isImplicitUndefined paths
    isExplicitReturn (ExplicitReturn _ _) = True
    isExplicitReturn _ = False

-- | Check return types against declared type.
checkReturnTypes :: Text -> [ReturnInfo] -> FFIType -> [FFIWarning]
checkReturnTypes name paths declared =
  concatMap (checkOneReturn name declared) paths

-- | Check a single return path against the declared type.
checkOneReturn :: Text -> FFIType -> ReturnInfo -> [FFIWarning]
checkOneReturn _ _ (ImplicitUndefined _) = []
checkOneReturn name declared (ExplicitReturn line inferred)
  | typesCompatible inferred declared = []
  | otherwise = [ReturnTypeMismatch line name inferred declared]

-- | Check Result tag construction.
checkResultTags :: Text -> [ReturnInfo] -> FFIType -> [FFIWarning]
checkResultTags name paths (FFIResult _ _) =
  concatMap (checkOneResultTag name) paths
checkResultTags name paths (FFIFunctionType _ ret) =
  checkResultTags name paths ret
checkResultTags _ _ _ = []

-- | Check a single return for Result tag presence.
checkOneResultTag :: Text -> ReturnInfo -> [FFIWarning]
checkOneResultTag _ (ImplicitUndefined _) = []
checkOneResultTag name (ExplicitReturn line inferred) =
  case inferred of
    InfObject fields ->
      [MissingResultTag line name | not (hasResultTag fields)]
    InfUnknown -> []
    _ -> [MissingResultTag line name]

-- | Check if object fields contain a "$" tag (Canopy Result convention).
hasResultTag :: [(Text, InferredType)] -> Bool
hasResultTag = any (\(k, _) -> k == "$")

-- BODY EXPRESSION ANALYSIS

-- | Walk the function body and detect warnings in expressions.
analyzeBodyExpressions :: Text -> JSBlock -> [FFIWarning]
analyzeBodyExpressions name (JSBlock _ stmts _) =
  concatMap (analyzeStmtExpressions name) stmts

-- | Analyze expressions within a statement for warnings.
analyzeStmtExpressions :: Text -> JSStatement -> [FFIWarning]
analyzeStmtExpressions name = \case
  JSReturn _ (Just expr) _ -> analyzeExprWarnings name expr
  JSExpressionStatement expr _ -> analyzeExprWarnings name expr
  JSIfElse _ _ cond _ thenStmt _ elseStmt ->
    analyzeExprWarnings name cond
      ++ analyzeStmtExpressions name thenStmt
      ++ analyzeStmtExpressions name elseStmt
  JSIf _ _ cond _ thenStmt ->
    analyzeExprWarnings name cond
      ++ analyzeStmtExpressions name thenStmt
  JSStatementBlock _ stmts _ _ ->
    concatMap (analyzeStmtExpressions name) stmts
  JSVariable _ exprs _ -> analyzeCommaListWarnings name exprs
  JSLet _ exprs _ -> analyzeCommaListWarnings name exprs
  JSConstant _ exprs _ -> analyzeCommaListWarnings name exprs
  JSWhile _ _ cond _ body ->
    analyzeExprWarnings name cond ++ analyzeStmtExpressions name body
  JSDoWhile _ body _ _ cond _ _ ->
    analyzeStmtExpressions name body ++ analyzeExprWarnings name cond
  JSTry _ (JSBlock _ tryStmts _) catches _ ->
    concatMap (analyzeStmtExpressions name) tryStmts
      ++ concatMap (analyzeCatchExpressions name) catches
  _ -> []

-- | Analyze warnings in catch clause bodies.
analyzeCatchExpressions :: Text -> JSAST.JSTryCatch -> [FFIWarning]
analyzeCatchExpressions name (JSAST.JSCatch _ _ _ _ (JSBlock _ stmts _)) =
  concatMap (analyzeStmtExpressions name) stmts
analyzeCatchExpressions _ _ = []

-- | Analyze warnings in a comma-separated expression list.
analyzeCommaListWarnings :: Text -> JSCommaList JSExpression -> [FFIWarning]
analyzeCommaListWarnings name exprs =
  concatMap (analyzeExprWarnings name) (commaListToList exprs)

-- | Analyze a single expression for warnings.
analyzeExprWarnings :: Text -> JSExpression -> [FFIWarning]
analyzeExprWarnings name = \case
  JSExpressionBinary left op right ->
    detectMixedOp name left op right
      ++ detectLooseEquality name op
      ++ analyzeExprWarnings name left
      ++ analyzeExprWarnings name right
  JSExpressionTernary cond _ thenExpr _ elseExpr ->
    analyzeExprWarnings name cond
      ++ analyzeExprWarnings name thenExpr
      ++ analyzeExprWarnings name elseExpr
  JSExpressionParen _ expr _ -> analyzeExprWarnings name expr
  JSCallExpression callee _ args _ ->
    analyzeExprWarnings name callee
      ++ concatMap (analyzeExprWarnings name) (commaListToList args)
  JSCallExpressionDot callee _ _ -> analyzeExprWarnings name callee
  JSCallExpressionSquare callee _ _ _ -> analyzeExprWarnings name callee
  JSArrayLiteral _ elements _ ->
    checkArrayElements name elements
  JSAssignExpression _ _ rhs -> analyzeExprWarnings name rhs
  JSVarInitExpression _ initializer ->
    analyzeInitializerWarnings name initializer
  _ -> []

-- | Analyze initializer expressions for warnings.
analyzeInitializerWarnings :: Text -> JSAST.JSVarInitializer -> [FFIWarning]
analyzeInitializerWarnings name (JSAST.JSVarInit _ expr) = analyzeExprWarnings name expr
analyzeInitializerWarnings _ _ = []

-- MIXED-TYPE OPERATION DETECTION

-- | Detect mixed-type binary operations.
detectMixedOp :: Text -> JSExpression -> JSBinOp -> JSExpression -> [FFIWarning]
detectMixedOp name left op right =
  case op of
    JSBinOpPlus annot -> checkMixedAdd (extractAnnotLine annot) name leftType rightType
    JSBinOpMinus annot -> checkNumericOp (extractAnnotLine annot) name "subtraction" leftType rightType
    JSBinOpTimes annot -> checkNumericOp (extractAnnotLine annot) name "multiplication" leftType rightType
    JSBinOpDivide annot -> checkNumericOp (extractAnnotLine annot) name "division" leftType rightType
    _ -> []
  where
    leftType = inferExprType left
    rightType = inferExprType right

-- | Check for mixed-type addition (the most common JS coercion issue).
checkMixedAdd :: Int -> Text -> InferredType -> InferredType -> [FFIWarning]
checkMixedAdd line name InfNumber InfString = [MixedTypeOperation line name "number + string"]
checkMixedAdd line name InfString InfNumber = [MixedTypeOperation line name "string + number"]
checkMixedAdd line name InfNull InfNumber = [MixedTypeOperation line name "null + number"]
checkMixedAdd line name InfNull InfString = [MixedTypeOperation line name "null + string"]
checkMixedAdd line name InfNumber InfNull = [MixedTypeOperation line name "number + null"]
checkMixedAdd line name InfString InfNull = [MixedTypeOperation line name "string + null"]
checkMixedAdd _ _ _ _ = []

-- | Check for non-numeric operands in numeric operations.
checkNumericOp :: Int -> Text -> Text -> InferredType -> InferredType -> [FFIWarning]
checkNumericOp line name opName InfString _ = [MixedTypeOperation line name (opName <> " with string")]
checkNumericOp line name opName _ InfString = [MixedTypeOperation line name (opName <> " with string")]
checkNumericOp line name opName InfNull _ = [MixedTypeOperation line name (opName <> " with null")]
checkNumericOp line name opName _ InfNull = [MixedTypeOperation line name (opName <> " with null")]
checkNumericOp _ _ _ _ _ = []

-- LOOSE EQUALITY DETECTION

-- | Detect loose equality operators.
detectLooseEquality :: Text -> JSBinOp -> [FFIWarning]
detectLooseEquality name (JSBinOpEq annot) =
  [LooseEquality (extractAnnotLine annot) name]
detectLooseEquality name (JSBinOpNeq annot) =
  [LooseEquality (extractAnnotLine annot) name]
detectLooseEquality _ _ = []

-- ARRAY ELEMENT ANALYSIS

-- | Check array literal for mixed element types.
checkArrayElements :: Text -> [JSArrayElement] -> [FFIWarning]
checkArrayElements name elements =
  case inferredTypes of
    [] -> []
    (first : rest)
      | all (== first) rest -> []
      | otherwise -> [MixedArrayElements (firstElementLine elements) name]
  where
    exprs = [e | JSArrayElement e <- elements]
    inferredTypes = filter (/= InfUnknown) (map inferExprType exprs)

-- | Get line of first array element.
firstElementLine :: [JSArrayElement] -> Int
firstElementLine (JSArrayElement expr : _) = extractExprLine expr
firstElementLine _ = 0

-- GLOBAL STATEMENT ANALYSIS

-- | Analyze a top-level statement for warnings (loose equality in conditions, etc.).
analyzeStatementWarnings :: JSStatement -> [FFIWarning]
analyzeStatementWarnings = \case
  _ -> []

-- TYPE INFERENCE

-- | Infer the type of a JavaScript expression.
--
-- Performs lightweight static type inference on JavaScript AST nodes.
-- Returns 'InfUnknown' for expressions that cannot be typed statically.
--
-- @since 0.20.0
inferExprType :: JSExpression -> InferredType
inferExprType = \case
  JSDecimal _ _ -> InfNumber
  JSHexInteger _ _ -> InfNumber
  JSAST.JSOctal _ _ -> InfNumber
  JSAST.JSBinaryInteger _ _ -> InfNumber
  JSAST.JSBigIntLiteral _ _ -> InfNumber
  JSStringLiteral _ _ -> InfString
  JSAST.JSRegEx _ _ -> InfUnknown
  JSLiteral _ bs -> inferLiteralType bs
  JSArrayLiteral _ elements _ -> inferArrayType elements
  JSObjectLiteral _ props _ -> inferObjectType props
  JSExpressionBinary left op right ->
    inferBinaryOp (inferExprType left) op (inferExprType right)
  JSExpressionTernary _ _ thenExpr _ elseExpr ->
    simplifyUnion (InfUnion [inferExprType thenExpr, inferExprType elseExpr])
  JSExpressionParen _ expr _ -> inferExprType expr
  JSUnaryExpression op _ -> inferUnaryType op
  JSAST.JSExpressionPostfix _ _ -> InfNumber
  JSAwaitExpression _ expr -> unwrapPromise (inferExprType expr)
  JSCallExpression callee _ _ _ -> inferCallType callee
  JSCallExpressionDot _ _ member -> inferMemberType member
  JSAST.JSMemberDot _ _ member -> inferMemberType member
  JSAST.JSNewExpression _ _ -> InfUnknown
  JSVarInitExpression _ initializer -> inferInitializerType initializer
  _ -> InfUnknown

-- | Infer type from a JavaScript literal bytestring.
inferLiteralType :: BS.ByteString -> InferredType
inferLiteralType bs
  | bs == "true" = InfBoolean
  | bs == "false" = InfBoolean
  | bs == "null" = InfNull
  | bs == "undefined" = InfNull
  | otherwise = InfUnknown

-- | Infer the type of an array literal from its elements.
inferArrayType :: [JSArrayElement] -> InferredType
inferArrayType elements =
  case elementTypes of
    [] -> InfArray InfUnknown
    (t : rest)
      | all (== t) rest -> InfArray t
      | otherwise -> InfArray (simplifyUnion (InfUnion elementTypes))
  where
    exprs = [e | JSArrayElement e <- elements]
    elementTypes = filter (/= InfUnknown) (map inferExprType exprs)

-- | Infer the type of an object literal from its properties.
inferObjectType :: JSCommaTrailingList JSObjectProperty -> InferredType
inferObjectType propList =
  InfObject (concatMap inferPropertyType (trailingListToList propList))

-- | Infer the name and type of an object property.
inferPropertyType :: JSObjectProperty -> [(Text, InferredType)]
inferPropertyType = \case
  JSPropertyNameandValue pname _ exprs ->
    [(propertyNameToText pname, inferPropertyValue exprs)]
  JSPropertyIdentRef _ nameBS ->
    [(TextEnc.decodeUtf8Lenient nameBS, InfUnknown)]
  _ -> []

-- | Infer type from property value expressions.
inferPropertyValue :: [JSExpression] -> InferredType
inferPropertyValue [] = InfUnknown
inferPropertyValue (expr : _) = inferExprType expr

-- | Convert a JSPropertyName to Text.
propertyNameToText :: JSPropertyName -> Text
propertyNameToText = \case
  JSPropertyIdent _ bs -> TextEnc.decodeUtf8Lenient bs
  JSPropertyString _ bs -> TextEnc.decodeUtf8Lenient (stripQuotes bs)
  JSPropertyNumber _ bs -> TextEnc.decodeUtf8Lenient bs
  JSPropertyComputed {} -> "<computed>"

-- | Strip surrounding quotes from a ByteString.
stripQuotes :: BS.ByteString -> BS.ByteString
stripQuotes bs
  | BS.length bs >= 2 = BS.drop 1 (BS.take (BS.length bs - 1) bs)
  | otherwise = bs

-- | Infer the result type of a binary operation.
inferBinaryOp :: InferredType -> JSBinOp -> InferredType -> InferredType
inferBinaryOp left op right =
  case op of
    JSBinOpPlus _ -> inferPlusType left right
    JSBinOpMinus _ -> InfNumber
    JSBinOpTimes _ -> InfNumber
    JSBinOpDivide _ -> InfNumber
    JSBinOpMod _ -> InfNumber
    JSBinOpExponentiation _ -> InfNumber
    JSBinOpLsh _ -> InfNumber
    JSBinOpRsh _ -> InfNumber
    JSBinOpUrsh _ -> InfNumber
    JSBinOpBitAnd _ -> InfNumber
    JSBinOpBitOr _ -> InfNumber
    JSBinOpBitXor _ -> InfNumber
    JSBinOpEq _ -> InfBoolean
    JSBinOpNeq _ -> InfBoolean
    JSBinOpStrictEq _ -> InfBoolean
    JSBinOpStrictNeq _ -> InfBoolean
    JSBinOpLt _ -> InfBoolean
    JSBinOpGt _ -> InfBoolean
    JSBinOpLe _ -> InfBoolean
    JSBinOpGe _ -> InfBoolean
    JSBinOpInstanceOf _ -> InfBoolean
    JSBinOpIn _ -> InfBoolean
    JSBinOpAnd _ -> simplifyUnion (InfUnion [left, right])
    JSBinOpOr _ -> simplifyUnion (InfUnion [left, right])
    JSBinOpNullishCoalescing _ -> simplifyUnion (InfUnion [left, right])
    _ -> InfUnknown

-- | Infer the result of the @+@ operator.
inferPlusType :: InferredType -> InferredType -> InferredType
inferPlusType InfNumber InfNumber = InfNumber
inferPlusType InfString InfString = InfString
inferPlusType InfString _ = InfString
inferPlusType _ InfString = InfString
inferPlusType InfNumber _ = InfNumber
inferPlusType _ InfNumber = InfNumber
inferPlusType _ _ = InfUnknown

-- | Infer type from a unary operator.
inferUnaryType :: JSUnaryOp -> InferredType
inferUnaryType = \case
  JSUnaryOpNot _ -> InfBoolean
  JSUnaryOpTypeof _ -> InfString
  JSUnaryOpVoid _ -> InfNull
  JSUnaryOpMinus _ -> InfNumber
  JSUnaryOpPlus _ -> InfNumber
  JSUnaryOpTilde _ -> InfNumber
  _ -> InfUnknown

-- | Infer type from a function call expression.
inferCallType :: JSExpression -> InferredType
inferCallType = \case
  JSMemberDot _ _ (JSIdentifier _ member) ->
    inferKnownMethodReturn member
  JSIdentifier _ name ->
    inferKnownFunctionReturn name
  _ -> InfUnknown

-- | Infer return type from known method names.
inferKnownMethodReturn :: BS.ByteString -> InferredType
inferKnownMethodReturn method
  | method == "toString" = InfString
  | method == "toFixed" = InfString
  | method == "toUpperCase" = InfString
  | method == "toLowerCase" = InfString
  | method == "trim" = InfString
  | method == "slice" = InfString
  | method == "substring" = InfString
  | method == "indexOf" = InfNumber
  | method == "lastIndexOf" = InfNumber
  | method == "length" = InfNumber
  | method == "charCodeAt" = InfNumber
  | method == "push" = InfNumber
  | method == "pop" = InfUnknown
  | method == "map" = InfArray InfUnknown
  | method == "filter" = InfArray InfUnknown
  | method == "concat" = InfArray InfUnknown
  | method == "includes" = InfBoolean
  | method == "startsWith" = InfBoolean
  | method == "endsWith" = InfBoolean
  | method == "hasOwnProperty" = InfBoolean
  | method == "isArray" = InfBoolean
  | method == "keys" = InfArray InfString
  | method == "values" = InfArray InfUnknown
  | method == "entries" = InfArray InfUnknown
  | method == "parse" = InfUnknown
  | method == "stringify" = InfString
  | otherwise = InfUnknown

-- | Infer return type from known global function names.
inferKnownFunctionReturn :: BS.ByteString -> InferredType
inferKnownFunctionReturn name
  | name == "parseInt" = InfNumber
  | name == "parseFloat" = InfNumber
  | name == "isNaN" = InfBoolean
  | name == "isFinite" = InfBoolean
  | name == "String" = InfString
  | name == "Number" = InfNumber
  | name == "Boolean" = InfBoolean
  | name == "Array" = InfArray InfUnknown
  | otherwise = InfUnknown

-- | Infer type from a member access (property name).
inferMemberType :: JSExpression -> InferredType
inferMemberType = \case
  JSIdentifier _ member
    | member == "length" -> InfNumber
    | member == "prototype" -> InfUnknown
    | otherwise -> InfUnknown
  _ -> InfUnknown

-- | Infer type from a variable initializer.
inferInitializerType :: JSAST.JSVarInitializer -> InferredType
inferInitializerType (JSAST.JSVarInit _ expr) = inferExprType expr
inferInitializerType _ = InfUnknown

-- | Unwrap a Promise type (from await expression).
unwrapPromise :: InferredType -> InferredType
unwrapPromise (InfPromise inner) = inner
unwrapPromise other = other

-- | Infer the overall return type of a function body.
inferReturnType :: JSBlock -> InferredType
inferReturnType body =
  case paths of
    [] -> InfNull
    [ExplicitReturn _ t] -> t
    [ImplicitUndefined _] -> InfNull
    _ -> simplifyUnion (InfUnion (map returnInfoType paths))
  where
    paths = analyzeReturnPaths body
    returnInfoType (ExplicitReturn _ t) = t
    returnInfoType (ImplicitUndefined _) = InfNull

-- TYPE COMPATIBILITY

-- | Check whether an inferred type is compatible with a declared FFI type.
typesCompatible :: InferredType -> FFIType -> Bool
typesCompatible InfUnknown _ = True
typesCompatible InfNull (FFIOpaque _ _) = False
typesCompatible (InfObject _) (FFIOpaque _ _) = True
typesCompatible (InfUnion types) (FFIOpaque name args) =
  any (\t -> typesCompatible t (FFIOpaque name args)) types
typesCompatible _ (FFIOpaque _ _) = True
typesCompatible InfNumber FFIInt = True
typesCompatible InfNumber FFIFloat = True
typesCompatible InfString FFIString = True
typesCompatible InfBoolean FFIBool = True
typesCompatible InfNull FFIUnit = True
typesCompatible InfNull (FFIMaybe _) = True
typesCompatible (InfArray _) (FFIList _) = True
typesCompatible (InfObject _) (FFIRecord _) = True
typesCompatible (InfObject _) (FFIResult _ _) = True
typesCompatible (InfPromise _) (FFITask _ _) = True
typesCompatible (InfUnion types) declared = any (`typesCompatible` declared) types
typesCompatible inferred (FFIMaybe inner) = typesCompatible inferred inner
typesCompatible inferred (FFIFunctionType _ ret) = typesCompatible inferred ret
typesCompatible _ (FFITypeVar _) = True
typesCompatible _ _ = False

-- | Check whether an FFIType has a Maybe return type (unwrapping function types).
isMaybeType :: FFIType -> Bool
isMaybeType (FFIMaybe _) = True
isMaybeType (FFIFunctionType _ ret) = isMaybeType ret
isMaybeType _ = False

-- | Check whether an FFIType has a Unit return type (unwrapping function types).
isUnitType :: FFIType -> Bool
isUnitType FFIUnit = True
isUnitType (FFIFunctionType _ ret) = isUnitType ret
isUnitType _ = False

-- SIMPLIFICATION

-- | Simplify a union type by removing duplicates and collapsing singletons.
simplifyUnion :: InferredType -> InferredType
simplifyUnion (InfUnion types) =
  case dedupTypes types of
    [] -> InfUnknown
    [single] -> single
    deduped -> InfUnion deduped
simplifyUnion other = other

-- | Remove duplicate types from a list.
dedupTypes :: [InferredType] -> [InferredType]
dedupTypes = foldr addIfNew []
  where
    addIfNew t acc
      | t `elem` acc = acc
      | otherwise = t : acc

-- ANNOTATION HELPERS

-- | Extract the line number from a JSAnnot.
extractAnnotLine :: JSAnnot -> Int
extractAnnotLine (JSAnnot (TokenPn _ line _) _) = line
extractAnnotLine _ = 0

-- | Extract the line number from an expression (best effort).
extractExprLine :: JSExpression -> Int
extractExprLine = \case
  JSIdentifier annot _ -> extractAnnotLine annot
  JSDecimal annot _ -> extractAnnotLine annot
  JSStringLiteral annot _ -> extractAnnotLine annot
  JSLiteral annot _ -> extractAnnotLine annot
  JSHexInteger annot _ -> extractAnnotLine annot
  JSExpressionBinary left _ _ -> extractExprLine left
  JSExpressionParen annot _ _ -> extractAnnotLine annot
  JSArrayLiteral annot _ _ -> extractAnnotLine annot
  JSObjectLiteral annot _ _ -> extractAnnotLine annot
  _ -> 0

-- | Extract the line number from a statement (best effort).
extractStmtLine :: JSStatement -> Int
extractStmtLine = \case
  JSReturn annot _ _ -> extractAnnotLine annot
  JSIf annot _ _ _ _ -> extractAnnotLine annot
  JSIfElse annot _ _ _ _ _ _ -> extractAnnotLine annot
  JSFunction annot _ _ _ _ _ _ -> extractAnnotLine annot
  JSVariable annot _ _ -> extractAnnotLine annot
  JSLet annot _ _ -> extractAnnotLine annot
  JSConstant annot _ _ -> extractAnnotLine annot
  JSWhile annot _ _ _ _ -> extractAnnotLine annot
  JSThrow annot _ _ -> extractAnnotLine annot
  _ -> 0

-- COMMA LIST HELPERS

-- | Convert a JSCommaList to a regular list.
commaListToList :: JSCommaList a -> [a]
commaListToList JSLNil = []
commaListToList (JSLOne x) = [x]
commaListToList (JSLCons rest _ x) = commaListToList rest ++ [x]

-- | Convert a JSCommaTrailingList to a regular list.
trailingListToList :: JSCommaTrailingList a -> [a]
trailingListToList (JSCTLComma cl _) = commaListToList cl
trailingListToList (JSCTLNone cl) = commaListToList cl
