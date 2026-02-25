{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unused-top-binds -Wno-unused-matches #-}

module Generate.JavaScript.Expression
  ( generate,
    generateCtor,
    generateField,
    generateTailDefExpr,
    generateFunction,
    generateMain,
    Code(..),
    codeToExpr,
    codeToStmtList,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Data.Index as Index
import qualified Data.IntMap as IntMap
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Optimize.DecisionTree as DT
import qualified Reporting.Annotation as A
import qualified Reporting.InternalError as InternalError

-- EXPRESSIONS

generateJsExpr :: Mode.Mode -> Opt.Expr -> JS.Expr
generateJsExpr mode expression =
  codeToExpr (generate mode expression)

generate :: Mode.Mode -> Opt.Expr -> Code
generate mode expression =
  case expression of
    Opt.Bool bool ->
      JsExpr $ JS.Bool bool
    Opt.Chr char ->
      JsExpr $
        case mode of
          Mode.Dev _ _ _ _ ->
            JS.Call toChar [JS.String (Utf8.toBuilder char)]
          Mode.Prod {} ->
            JS.String (Utf8.toBuilder char)
    Opt.Str string ->
      case StringPool.lookupString (Mode.stringPool mode) string of
        Just poolName -> JsExpr (JS.Ref poolName)
        Nothing -> JsExpr (JS.String (Utf8.toBuilder string))
    Opt.Int int ->
      JsExpr $ JS.Int int
    Opt.Float float ->
      JsExpr $ JS.Float (Utf8.toBuilder float)
    Opt.VarLocal name ->
      JsExpr $ JS.Ref (JsName.fromLocal name)
    Opt.VarGlobal (Opt.Global home name) ->
      -- Check if this is an FFI module by checking if the module name is an FFI alias
      let moduleName = ModuleName._module home
      in if Mode.isFFIAlias mode moduleName
         then -- This is an FFI function - generate direct JavaScript access
              -- Create JavaScript: Math.add, AudioFFI.createContext, etc.
              let moduleStr = Name.toChars moduleName
                  nameStr = Name.toChars name
                  jsName = Name.fromChars (moduleStr ++ "." ++ nameStr)
              in JsExpr $ JS.Ref (JsName.fromLocal jsName)
         else -- Regular global function
              JsExpr $ JS.Ref (JsName.fromGlobal home name)
    Opt.VarEnum (Opt.Global home name) index ->
      case mode of
        Mode.Dev _ _ _ _ ->
          JsExpr $ JS.Ref (JsName.fromGlobal home name)
        Mode.Prod {} ->
          JsExpr $ JS.Int (Index.toMachine index)
    Opt.VarBox (Opt.Global home name) ->
      JsExpr . JS.Ref $
        ( case mode of
            Mode.Dev _ _ _ _ -> JsName.fromGlobal home name
            Mode.Prod {} -> JsName.fromGlobal ModuleName.basics Name.identity
        )
    Opt.VarCycle home name ->
      JsExpr $ JS.Call (JS.Ref (JsName.fromCycle home name)) []
    Opt.VarDebug name home region unhandledValueName ->
      JsExpr $ generateDebug mode name home region unhandledValueName
    Opt.VarKernel home name ->
      JsExpr $ JS.Ref (JsName.fromKernel home name)
    Opt.List entries ->
      case entries of
        [] ->
          JsExpr $ JS.Ref (JsName.fromKernel Name.list "Nil")
        _ ->
          JsExpr $
            JS.Call
              (JS.Ref (JsName.fromKernel Name.list "fromArray"))
              [ JS.Array $ fmap (generateJsExpr mode) entries
              ]
    Opt.Function args body ->
      -- For functions with >100 args that just return a record, cap at F9 + currying
      -- to avoid stack overflow but keep correct semantics
      if length args > 100
        then generateLargeFunction mode (fmap JsName.fromLocal args) (generate mode body)
        else generateFunction (fmap JsName.fromLocal args) (generate mode body)
    Opt.Call func args ->
      JsExpr $ generateCall mode func args
    Opt.ArithBinop op left right ->
      generateArithBinop mode op left right
    Opt.TailCall name args ->
      generateTailCall mode name args
    Opt.If branches final ->
      generateIf mode branches final
    Opt.Let def body ->
      -- Special case: if this is just a tail-recursive function definition
      -- followed by a reference to that function, don't wrap in IIFE
      case (def, body) of
        (Opt.TailDef name _ _, Opt.VarLocal bodyName) | name == bodyName ->
          JsExpr $ generateTailDefExpr mode name (getTailDefArgs def) (getTailDefBody def)
        (Opt.TailDef name _ _, Opt.VarLocal bodyName) | name /= bodyName ->
          -- TailDef with different variable reference - treat as separate statements
          let defStmt = generateDef mode def
              bodyStmts = codeToStmtList (generate mode body)
              allStmts = flattenStatements [defStmt] ++ bodyStmts
              -- Don't filter return statements for TailDef followed by different variable
              nonEmptyStmts = filter (\stmt -> case stmt of
                                        JS.EmptyStmt -> False
                                        _ -> True) allStmts
          in case nonEmptyStmts of
               [singleStmt] -> JsStmt singleStmt
               [] -> JsStmt JS.EmptyStmt
               stmts -> JsBlock stmts
        _ ->
          let defStmt = generateDef mode def
              bodyStmts = codeToStmtList (generate mode body)
              allStmts = flattenStatements [defStmt] ++ bodyStmts
              -- Filter out only empty statements, preserve return statements for let expressions
              nonEmptyStmts = filter (\stmt -> case stmt of
                                        JS.EmptyStmt -> False
                                        _ -> True) allStmts
          in case nonEmptyStmts of
               [singleStmt] -> JsStmt singleStmt  -- Single statement doesn't need block
               [] -> JsStmt JS.EmptyStmt  -- Empty should be empty statement
               stmts -> JsBlock stmts  -- Multiple statements need block
    Opt.Destruct (Opt.Destructor name path) body ->
      let pathDef = JS.Var (JsName.fromLocal name) (generatePath mode path)
       in JsBlock $ flattenStatements [pathDef] ++ codeToStmtList (generate mode body)
    Opt.Case label root decider jumps ->
      JsBlock $ generateCase mode label root decider jumps
    Opt.Accessor field ->
      JsExpr $
        JS.Function
          Nothing
          [JsName.dollar]
          [ JS.Return $
              JS.Access (JS.Ref JsName.dollar) (generateField mode field)
          ]
    Opt.Access record field ->
      JsExpr $ JS.Access (generateJsExpr mode record) (generateField mode field)
    Opt.Update record fields ->
      JsExpr $
        JS.Call
          (JS.Ref (JsName.fromKernel Name.utils "update"))
          [ generateJsExpr mode record,
            generateRecord mode fields
          ]
    Opt.Record fields ->
      JsExpr $ generateRecord mode fields
    Opt.Unit ->
      case mode of
        Mode.Dev _ _ _ _ ->
          JsExpr $ JS.Ref (JsName.fromKernel Name.utils "Tuple0")
        Mode.Prod {} ->
          JsExpr $ JS.Int 0
    Opt.Tuple a b maybeC ->
      JsExpr $
        case maybeC of
          Nothing ->
            JS.Call
              (JS.Ref (JsName.fromKernel Name.utils "Tuple2"))
              [ generateJsExpr mode a,
                generateJsExpr mode b
              ]
          Just c ->
            JS.Call
              (JS.Ref (JsName.fromKernel Name.utils "Tuple3"))
              [ generateJsExpr mode a,
                generateJsExpr mode b,
                generateJsExpr mode c
              ]
    Opt.Shader src attributes uniforms ->
      let toTranlation field =
            ( JsName.fromLocal field,
              JS.String (JsName.toBuilder (generateField mode field))
            )

          toTranslationObject fields =
            JS.Object (fmap toTranlation (Set.toList fields))
       in ( JsExpr . JS.Object $
              [ (JsName.fromLocal "src", JS.String (Shader.toJsStringBuilder src)),
                (JsName.fromLocal "attributes", toTranslationObject attributes),
                (JsName.fromLocal "uniforms", toTranslationObject uniforms)
              ]
          )

-- CODE CHUNKS

data Code
  = JsExpr JS.Expr
  | JsStmt JS.Stmt
  | JsBlock [JS.Stmt]

codeToExpr :: Code -> JS.Expr
codeToExpr code =
  case code of
    JsExpr expr ->
      expr
    JsStmt (JS.Return expr) ->
      expr
    JsStmt stmt ->
      JS.Call (JS.Function Nothing [] [stmt]) []
    JsBlock [JS.Return expr] ->
      expr
    JsBlock stmts ->
      JS.Call (JS.Function Nothing [] stmts) []

codeToStmtList :: Code -> [JS.Stmt]
codeToStmtList code =
  case code of
    JsExpr (JS.Call (JS.Function Nothing [] stmts) []) ->
      flattenStatements stmts
    JsExpr expr ->
      [JS.Return expr]
    JsStmt stmt ->
      [stmt]
    JsBlock stmts ->
      flattenStatements stmts

flattenStatements :: [JS.Stmt] -> [JS.Stmt]
flattenStatements = concatMap flattenStatement
  where
    flattenStatement :: JS.Stmt -> [JS.Stmt]
    flattenStatement stmt =
      case stmt of
        JS.Block [] -> []  -- Remove empty blocks
        JS.Block stmts -> flattenStatements stmts  -- Flatten nested blocks
        JS.ExprStmt (JS.Call (JS.Function Nothing [] innerStmts) []) ->
          -- Handle IIFE expressions that should be flattened
          flattenStatements innerStmts
        JS.EmptyStmt -> []  -- Remove empty statements
        _ -> [stmt]  -- Keep other statements as-is

codeToStmt :: Code -> JS.Stmt
codeToStmt code =
  case code of
    JsExpr (JS.Call (JS.Function Nothing [] stmts) []) ->
      JS.Block stmts
    JsExpr expr ->
      JS.Return expr
    JsStmt stmt ->
      stmt
    JsBlock [stmt] ->
      stmt
    JsBlock stmts ->
      JS.Block stmts

-- CHARS

{-# NOINLINE toChar #-}
toChar :: JS.Expr
toChar =
  JS.Ref (JsName.fromKernel Name.utils "chr")

-- CTOR

generateCtor :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> Int -> Code
generateCtor mode (Opt.Global home name) index arity =
  let argNames =
        Index.indexedMap (\i _ -> JsName.fromIndex i) [1 .. arity]

      ctorTag =
        case mode of
          Mode.Dev _ _ _ _ -> JS.String (Name.toBuilder name)
          Mode.Prod {} -> JS.Int (ctorToInt home name index)
   in ((generateFunction argNames . JsExpr) . JS.Object $ ((JsName.dollar, ctorTag) : fmap (\n -> (n, JS.Ref n)) argNames))

ctorToInt :: ModuleName.Canonical -> Name.Name -> Index.ZeroBased -> Int
ctorToInt home name index =
  if home == ModuleName.dict && name == "RBNode_elm_builtin" || name == "RBEmpty_elm_builtin"
    then negate (Index.toHuman index)
    else Index.toMachine index

-- RECORDS

generateRecord :: Mode.Mode -> Map Name.Name Opt.Expr -> JS.Expr
generateRecord mode fields =
  let toPair (field, value) =
        (generateField mode field, generateJsExpr mode value)
   in JS.Object (fmap toPair (Map.toList fields))

generateField :: Mode.Mode -> Name.Name -> JsName.Name
generateField mode name =
  case mode of
    Mode.Dev _ _ _ _ ->
      JsName.fromLocal name
    Mode.Prod fields _ _ _ _ ->
      maybe
        (InternalError.report "Generate.JavaScript.Expression.generateField" "Unknown field name in production mode" "The field shortener map is missing an expected field.")
        id
        (Map.lookup name fields)

-- | Generate large functions (>100 parameters) with chunking to avoid stack overflow
generateLargeFunction :: Mode.Mode -> [JsName.Name] -> Code -> Code
generateLargeFunction mode args body =
  -- Use F9 for first 9 args, then curry the rest in chunks of 9
  let chunks = chunkList 9 args
  in case chunks of
    [] -> body
    [single] -> generateFunction single body
    (first : rest) ->
      let innerFn = foldr (\chunk acc -> generateFunction chunk acc) body rest
      in generateFunction first innerFn

chunkList :: Int -> [a] -> [[a]]
chunkList _ [] = []
chunkList n xs =
  let (chunk, rest) = splitAt n xs
  in chunk : chunkList n rest

-- DEBUG

generateDebug :: Mode.Mode -> Name.Name -> ModuleName.Canonical -> A.Region -> Maybe Name.Name -> JS.Expr
generateDebug mode name (ModuleName.Canonical _ home) region unhandledValueName =
  if name /= "todo"
    then JS.Ref (JsName.fromGlobal ModuleName.debug name)
    else case unhandledValueName of
      Nothing ->
        JS.Call
          (JS.Ref (JsName.fromKernel Name.debug "todo"))
          [ JS.String (Name.toBuilder home),
            regionToJsExpr mode region
          ]
      Just valueName ->
        JS.Call
          (JS.Ref (JsName.fromKernel Name.debug "todoCase"))
          [ JS.String (Name.toBuilder home),
            regionToJsExpr mode region,
            JS.Ref (JsName.fromLocal valueName)
          ]

regionToJsExpr :: Mode.Mode -> A.Region -> JS.Expr
regionToJsExpr mode (A.Region start end) =
  if Mode.isElmCompatible mode
    then  -- Elm-compatible mode
      JS.Object
        [ (JsName.fromLocal "I", positionToJsExpr mode start),
          (JsName.fromLocal "N", positionToJsExpr mode end)
        ]
    else  -- Canopy native mode
      JS.Object
        [ (JsName.fromLocal "start", positionToJsExpr mode start),
          (JsName.fromLocal "end", positionToJsExpr mode end)
        ]

positionToJsExpr :: Mode.Mode -> A.Position -> JS.Expr
positionToJsExpr mode (A.Position line column) =
  if Mode.isElmCompatible mode
    then  -- Elm-compatible mode
      JS.Object
        [ (JsName.fromLocal "z", JS.Int (fromIntegral line)),
          (JsName.fromLocal "A", JS.Int (fromIntegral column))
        ]
    else  -- Canopy native mode
      JS.Object
        [ (JsName.fromLocal "line", JS.Int (fromIntegral line)),
          (JsName.fromLocal "column", JS.Int (fromIntegral column))
        ]

-- FUNCTION

generateFunction :: [JsName.Name] -> Code -> Code
generateFunction args body =
  case IntMap.lookup (length args) funcHelpers of
    Just helper ->
      JsExpr $
        JS.Call
          helper
          [ JS.Function Nothing args $
              codeToStmtList body
          ]
    Nothing ->
      let addArg arg code =
            (JsExpr . JS.Function Nothing [arg] $ codeToStmtList code)
       in foldr addArg body args

-- Generate tail-call optimized function with while(true) loop like Elm
generateTailFunction :: Name.Name -> [JsName.Name] -> Code -> Code
generateTailFunction functionName args body =
  let labelName = JsName.fromLocal functionName
      -- Force a multi-statement block to avoid the single-statement optimization
      bodyStmts = codeToStmtList body
      whileBody = case bodyStmts of
        [stmt] -> JS.Block [stmt, JS.EmptyStmt]  -- Add empty statement to force braces
        stmts -> JS.Block stmts
  in case IntMap.lookup (length args) funcHelpers of
    Just helper ->
      JsExpr $
        JS.Call
          helper
          [ JS.Function Nothing args $
              [ JS.Labelled labelName $
                  JS.While (JS.Bool True) whileBody
              ]
          ]
    Nothing ->
      let addArg arg code =
            let codeStmts = codeToStmtList code
                argWhileBody = case codeStmts of
                  [stmt] -> JS.Block [stmt, JS.EmptyStmt]
                  stmts -> JS.Block stmts
            in (JsExpr . JS.Function Nothing [arg] $
              [ JS.Labelled labelName $
                  JS.While (JS.Bool True) argWhileBody
              ])
       in foldr addArg body args

{-# NOINLINE funcHelpers #-}
funcHelpers :: IntMap.IntMap JS.Expr
funcHelpers =
  IntMap.fromList $
    fmap (\n -> (n, JS.Ref (JsName.makeF n))) [2 .. 9]

-- ARITHMETIC BINOPS

-- | Generate JavaScript for native arithmetic operator.
--
-- Compiles optimized arithmetic operations directly to JavaScript infix
-- operators for maximum performance. Recursively generates code for both
-- operands and constructs an infix expression.
--
-- This is the final code generation step that produces native JavaScript
-- arithmetic operations without function call overhead.
--
-- ==== Generated Code
--
-- Arithmetic operators compile to their JavaScript equivalents:
--
-- * Add → @a + b@
-- * Sub → @a - b@
-- * Mul → @a * b@
-- * Div → @a / b@
--
-- ==== Compilation Process
--
-- 1. **Generate left operand** - Recursively generate JavaScript for left expression
-- 2. **Generate right operand** - Recursively generate JavaScript for right expression
-- 3. **Map operator** - Convert 'Can.ArithOp' to 'JS.InfixOp'
-- 4. **Construct infix** - Build JavaScript infix expression
--
-- ==== Examples
--
-- @
-- -- Simple integer addition
-- generateArithBinop mode Add (Int 1) (Int 2)
-- -- JavaScript: 1 + 2
--
-- -- Variable multiplication
-- generateArithBinop mode Mul (VarLocal "x") (Int 2)
-- -- JavaScript: x * 2
--
-- -- Nested arithmetic
-- generateArithBinop mode Add (ArithBinop Mul (VarLocal "x") (Int 2)) (Int 3)
-- -- JavaScript: (x * 2) + 3
-- @
--
-- ==== Optimization Integration
--
-- The generated code benefits from earlier optimization passes:
--
-- * **Constant folding** - Constants already evaluated at compile time
-- * **Identity elimination** - Unnecessary operations already removed
-- * **Dead code elimination** - Unused expressions already eliminated
--
-- ==== Performance
--
-- * **Time Complexity**: O(depth) for recursive generation
-- * **Space Complexity**: O(depth) for expression tree
-- * **Runtime**: Native JavaScript operators (fastest possible execution)
--
-- @since 0.19.2
generateArithBinop :: Mode.Mode -> Can.ArithOp -> Opt.Expr -> Opt.Expr -> Code
generateArithBinop mode op left right =
  let leftExpr = codeToExpr (generate mode left)
      rightExpr = codeToExpr (generate mode right)
      jsOp = arithOpToJs op
  in JsExpr (JS.Infix jsOp leftExpr rightExpr)

-- | Map arithmetic operator to JavaScript infix operator.
--
-- Converts Canopy arithmetic operator types to their JavaScript equivalents.
-- This is a simple mapping function that ensures correct operator precedence
-- and associativity in generated code.
--
-- ==== Operator Mapping
--
-- * 'Can.Add' → 'JS.OpAdd' (+)
-- * 'Can.Sub' → 'JS.OpSub' (-)
-- * 'Can.Mul' → 'JS.OpMul' (*)
-- * 'Can.Div' → 'JS.OpDiv' (/)
--
-- JavaScript handles operator precedence and associativity according to
-- standard rules:
--
-- * Multiplication and division have higher precedence than addition/subtraction
-- * All arithmetic operators are left-associative
-- * Parentheses are inserted automatically by the JavaScript AST printer
--
-- ==== Examples
--
-- >>> arithOpToJs Can.Add
-- JS.OpAdd
--
-- >>> arithOpToJs Can.Mul
-- JS.OpMul
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) constant-time pattern match
-- * **Space Complexity**: O(1) no allocation
--
-- @since 0.19.2
arithOpToJs :: Can.ArithOp -> JS.InfixOp
arithOpToJs Can.Add = JS.OpAdd
arithOpToJs Can.Sub = JS.OpSub
arithOpToJs Can.Mul = JS.OpMul
arithOpToJs Can.Div = JS.OpDiv

-- CALLS

generateCall :: Mode.Mode -> Opt.Expr -> [Opt.Expr] -> JS.Expr
generateCall mode func args =
  case func of
    Opt.VarGlobal global@(Opt.Global (ModuleName.Canonical pkg _) _)
      | Pkg.isCore pkg ->
        generateCoreCall mode global args
    Opt.VarBox _ ->
      case mode of
        Mode.Dev _ _ _ _ ->
          generateCallHelp mode func args
        Mode.Prod {} ->
          case args of
            [arg] ->
              generateJsExpr mode arg
            _ ->
              generateCallHelp mode func args
    _ ->
      generateCallHelp mode func args

generateCallHelp :: Mode.Mode -> Opt.Expr -> [Opt.Expr] -> JS.Expr
generateCallHelp mode func args =
  generateNormalCall
    (generateJsExpr mode func)
    (fmap (generateJsExpr mode) args)

generateGlobalCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateGlobalCall home name = generateNormalCall (JS.Ref (JsName.fromGlobal home name))

generateNormalCall :: JS.Expr -> [JS.Expr] -> JS.Expr
generateNormalCall func args =
  case IntMap.lookup (length args) callHelpers of
    Just helper ->
      JS.Call helper (func : args)
    Nothing ->
      List.foldl' (\f a -> JS.Call f [a]) func args

{-# NOINLINE callHelpers #-}
callHelpers :: IntMap.IntMap JS.Expr
callHelpers =
  IntMap.fromList $
    fmap (\n -> (n, JS.Ref (JsName.makeA n))) [2 .. 9]

-- CORE CALLS

generateCoreCall :: Mode.Mode -> Opt.Global -> [Opt.Expr] -> JS.Expr
generateCoreCall mode (Opt.Global home@(ModuleName.Canonical _ moduleName) name) args
  | moduleName == Name.basics = generateBasicsCall mode home name args
  | moduleName == Name.bitwise = generateBitwiseCall home name (fmap (generateJsExpr mode) args)
  | moduleName == Name.tuple = generateTupleCall home name (fmap (generateJsExpr mode) args)
  | moduleName == Name.jsArray = generateJsArrayCall home name (fmap (generateJsExpr mode) args)
  | otherwise = generateGlobalCall home name (fmap (generateJsExpr mode) args)

generateTupleCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateTupleCall home name args =
  case args of
    [value] ->
      case name of
        "first" -> JS.Access value (JsName.fromLocal "a")
        "second" -> JS.Access value (JsName.fromLocal "b")
        _ -> generateGlobalCall home name args
    _ ->
      generateGlobalCall home name args

generateJsArrayCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateJsArrayCall home name args =
  case args of
    [entry] | name == "singleton" -> JS.Array [entry]
    [index, array] | name == "unsafeGet" -> JS.Index array index
    _ -> generateGlobalCall home name args

generateBitwiseCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateBitwiseCall home name args =
  case args of
    [arg] ->
      case name of
        "complement" -> JS.Prefix JS.PrefixComplement arg
        _ -> generateGlobalCall home name args
    [left, right] ->
      case name of
        "and" -> JS.Infix JS.OpBitwiseAnd left right
        "or" -> JS.Infix JS.OpBitwiseOr left right
        "xor" -> JS.Infix JS.OpBitwiseXor left right
        "shiftLeftBy" -> JS.Infix JS.OpLShift right left
        "shiftRightBy" -> JS.Infix JS.OpSpRShift right left
        "shiftRightZfBy" -> JS.Infix JS.OpZfRShift right left
        _ -> generateGlobalCall home name args
    _ ->
      generateGlobalCall home name args

generateBasicsCall :: Mode.Mode -> ModuleName.Canonical -> Name.Name -> [Opt.Expr] -> JS.Expr
generateBasicsCall mode home name args =
  case args of
    [canopyArg] ->
      let arg = generateJsExpr mode canopyArg
       in case name of
            "not" -> JS.Prefix JS.PrefixNot arg
            "negate" -> JS.Prefix JS.PrefixNegate arg
            "toFloat" -> arg
            "truncate" -> JS.Infix JS.OpBitwiseOr arg (JS.Int 0)
            _ -> generateGlobalCall home name [arg]
    [canopyLeft, canopyRight] ->
      case name of
        -- NOTE: removed "composeL" and "composeR" because of this issue:
        -- https://github.com/canopy/compiler/issues/1722
        "append" -> append mode canopyLeft canopyRight
        "apL" -> generateJsExpr mode $ apply canopyLeft canopyRight
        "apR" -> generateJsExpr mode $ apply canopyRight canopyLeft
        _ ->
          let left = generateJsExpr mode canopyLeft
              right = generateJsExpr mode canopyRight
           in case name of
                "add" -> JS.Infix JS.OpAdd left right
                "sub" -> JS.Infix JS.OpSub left right
                "mul" -> JS.Infix JS.OpMul left right
                "fdiv" -> JS.Infix JS.OpDiv left right
                "idiv" -> JS.Infix JS.OpBitwiseOr (JS.Infix JS.OpDiv left right) (JS.Int 0)
                "eq" -> equal left right
                "neq" -> notEqual left right
                "lt" -> cmp JS.OpLt JS.OpLt 0 left right
                "gt" -> cmp JS.OpGt JS.OpGt 0 left right
                "le" -> cmp JS.OpLe JS.OpLt 1 left right
                "ge" -> cmp JS.OpGe JS.OpGt (-1) left right
                "or" -> JS.Infix JS.OpOr left right
                "and" -> JS.Infix JS.OpAnd left right
                "xor" -> JS.Infix JS.OpNe left right
                "remainderBy" -> JS.Infix JS.OpMod right left
                _ -> generateGlobalCall home name [left, right]
    _ ->
      generateGlobalCall home name (fmap (generateJsExpr mode) args)

equal :: JS.Expr -> JS.Expr -> JS.Expr
equal left right =
  if isLiteral left || isLiteral right
    then strictEq left right
    else JS.Call (JS.Ref (JsName.fromKernel Name.utils "eq")) [left, right]

notEqual :: JS.Expr -> JS.Expr -> JS.Expr
notEqual left right =
  if isLiteral left || isLiteral right
    then strictNEq left right
    else
      JS.Prefix JS.PrefixNot $
        JS.Call (JS.Ref (JsName.fromKernel Name.utils "eq")) [left, right]

cmp :: JS.InfixOp -> JS.InfixOp -> Int -> JS.Expr -> JS.Expr -> JS.Expr
cmp idealOp backupOp backupInt left right =
  if isLiteral left || isLiteral right
    then JS.Infix idealOp left right
    else
      JS.Infix
        backupOp
        (JS.Call (JS.Ref (JsName.fromKernel Name.utils "cmp")) [left, right])
        (JS.Int backupInt)

isLiteral :: JS.Expr -> Bool
isLiteral expr =
  case expr of
    JS.String _ ->
      True
    JS.Float _ ->
      True
    JS.Int _ ->
      True
    JS.Bool _ ->
      True
    _ ->
      False

apply :: Opt.Expr -> Opt.Expr -> Opt.Expr
apply func value =
  case func of
    Opt.Accessor field ->
      Opt.Access value field
    Opt.Call f args ->
      Opt.Call f (args <> [value])
    _ ->
      Opt.Call func [value]

append :: Mode.Mode -> Opt.Expr -> Opt.Expr -> JS.Expr
append mode left right =
  let seqs = generateJsExpr mode left : toSeqs mode right
   in if any isStringLiteral seqs
        then foldr1 (JS.Infix JS.OpAdd) seqs
        else foldr1 jsAppend seqs

jsAppend :: JS.Expr -> JS.Expr -> JS.Expr
jsAppend a b =
  JS.Call (JS.Ref (JsName.fromKernel Name.utils "ap")) [a, b]

toSeqs :: Mode.Mode -> Opt.Expr -> [JS.Expr]
toSeqs mode expr =
  case expr of
    Opt.Call (Opt.VarGlobal (Opt.Global home "append")) [left, right]
      | home == ModuleName.basics ->
        generateJsExpr mode left : toSeqs mode right
    _ ->
      [generateJsExpr mode expr]

isStringLiteral :: JS.Expr -> Bool
isStringLiteral expr =
  case expr of
    JS.String _ ->
      True
    _ ->
      False

-- SIMPLIFY INFIX OPERATORS

strictEq :: JS.Expr -> JS.Expr -> JS.Expr
strictEq left right =
  case left of
    JS.Int 0 ->
      JS.Prefix JS.PrefixNot right
    JS.Bool bool ->
      if bool then right else JS.Prefix JS.PrefixNot right
    _ ->
      case right of
        JS.Int 0 ->
          JS.Prefix JS.PrefixNot left
        JS.Bool bool ->
          if bool then left else JS.Prefix JS.PrefixNot left
        _ ->
          JS.Infix JS.OpEq left right

strictNEq :: JS.Expr -> JS.Expr -> JS.Expr
strictNEq left right =
  case left of
    JS.Int 0 ->
      JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot right)
    JS.Bool bool ->
      if bool then JS.Prefix JS.PrefixNot right else right
    _ ->
      case right of
        JS.Int 0 ->
          JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot left)
        JS.Bool bool ->
          if bool then JS.Prefix JS.PrefixNot left else left
        _ ->
          JS.Infix JS.OpNe left right


-- DEFINITIONS

generateDef :: Mode.Mode -> Opt.Def -> JS.Stmt
generateDef mode def =
  case def of
    Opt.Def name body ->
      JS.Var (JsName.fromLocal name) (generateJsExpr mode body)
    Opt.TailDef name argNames body ->
      JS.Var (JsName.fromLocal name) (generateTailDefExpr mode name argNames body)


-- Helper functions for extracting TailDef components
getTailDefArgs :: Opt.Def -> [Name.Name]
getTailDefArgs def = case def of
  Opt.TailDef _ args _ -> args
  _ -> []

getTailDefBody :: Opt.Def -> Opt.Expr
getTailDefBody def = case def of
  Opt.TailDef _ _ body -> body
  _ -> InternalError.report
    "Generate.JavaScript.Expression.getTailDefBody"
    "Called on non-TailDef"
    "getTailDefBody must only be called on Opt.TailDef values. The caller must verify the definition is a TailDef before invoking this function."


generateTailDefExpr :: Mode.Mode -> Name.Name -> [Name.Name] -> Opt.Expr -> JS.Expr
generateTailDefExpr mode name argNames body =
  codeToExpr (generateTailFunction name (fmap JsName.fromLocal argNames) (generate mode body))

-- Generate tail-call assignment like Elm: var $temp$func=func,$temp$acc=...; func=$temp$func; continue label;
generateTailCall :: Mode.Mode -> Name.Name -> [(Name.Name, Opt.Expr)] -> Code
generateTailCall mode name args =
  JsBlock allStmts
  where
    tempVarNames = fmap (\(argName, argExpr) ->
        (JsName.makeTemp argName, generateJsExpr mode argExpr)) args
    realAssignments = fmap (\(argName, _) ->
        JS.ExprStmtWithSemi (JS.Assign
          (JS.LRef (JsName.fromLocal argName))
          (JS.Ref (JsName.makeTemp argName)))) args
    continueStmt = JS.Continue (Just (JsName.fromLocal name))
    tempVarStmt = case tempVarNames of
      [] -> []
      _ -> [JS.Vars tempVarNames]
    allStmts = tempVarStmt ++ realAssignments ++ [continueStmt]

-- PATHS

generatePath :: Mode.Mode -> Opt.Path -> JS.Expr
generatePath mode path =
  case path of
    Opt.Index index subPath ->
      JS.Access (generatePath mode subPath) (JsName.fromIndex index)
    Opt.Root name ->
      JS.Ref (JsName.fromLocal name)
    Opt.Field field subPath ->
      JS.Access (generatePath mode subPath) (generateField mode field)
    Opt.Unbox subPath ->
      case mode of
        Mode.Dev _ _ _ _ ->
          JS.Access (generatePath mode subPath) (JsName.fromIndex Index.first)
        Mode.Prod {} ->
          generatePath mode subPath

-- GENERATE IFS

generateIf :: Mode.Mode -> [(Opt.Expr, Opt.Expr)] -> Opt.Expr -> Code
generateIf mode givenBranches givenFinal =
  let (branches, final) =
        crushIfs givenBranches givenFinal

      convertBranch (condition, expr) =
        ( generateJsExpr mode condition,
          generate mode expr
        )

      branchExprs = fmap convertBranch branches
      finalCode = generate mode final
   in if isBlock finalCode || any (isBlock . snd) branchExprs
        then JsBlock [foldr addStmtIf (codeToStmt finalCode) branchExprs]
        else JsExpr $ foldr addExprIf (codeToExpr finalCode) branchExprs

addExprIf :: (JS.Expr, Code) -> JS.Expr -> JS.Expr
addExprIf (condition, branch) = JS.If condition (codeToExpr branch)

addStmtIf :: (JS.Expr, Code) -> JS.Stmt -> JS.Stmt
addStmtIf (condition, branch) = JS.IfStmt condition (codeToStmt branch)

isBlock :: Code -> Bool
isBlock code =
  case code of
    JsBlock _ -> True
    JsStmt _ -> False  -- Single statements are not blocks
    JsExpr _ -> False

crushIfs :: [(Opt.Expr, Opt.Expr)] -> Opt.Expr -> ([(Opt.Expr, Opt.Expr)], Opt.Expr)
crushIfs = crushIfsHelp []

crushIfsHelp ::
  [(Opt.Expr, Opt.Expr)] ->
  [(Opt.Expr, Opt.Expr)] ->
  Opt.Expr ->
  ([(Opt.Expr, Opt.Expr)], Opt.Expr)
crushIfsHelp visitedBranches unvisitedBranches final =
  case unvisitedBranches of
    [] ->
      case final of
        Opt.If subBranches subFinal ->
          crushIfsHelp visitedBranches subBranches subFinal
        _ ->
          (reverse visitedBranches, final)
    visiting : unvisited ->
      crushIfsHelp (visiting : visitedBranches) unvisited final

-- CASE EXPRESSIONS

generateCase :: Mode.Mode -> Name.Name -> Name.Name -> Opt.Decider Opt.Choice -> [(Int, Opt.Expr)] -> [JS.Stmt]
generateCase mode label root decider = foldr (goto mode label) (generateDecider mode label root decider)

goto :: Mode.Mode -> Name.Name -> (Int, Opt.Expr) -> [JS.Stmt] -> [JS.Stmt]
goto mode label (index, branch) stmts =
  let labeledDeciderStmt =
        JS.Labelled
          (JsName.makeLabel label index)
          (JS.While (JS.Bool True) (JS.Block stmts))
   in labeledDeciderStmt : codeToStmtList (generate mode branch)

generateDecider :: Mode.Mode -> Name.Name -> Name.Name -> Opt.Decider Opt.Choice -> [JS.Stmt]
generateDecider mode label root decisionTree =
  case decisionTree of
    Opt.Leaf (Opt.Inline branch) ->
      codeToStmtList (generate mode branch)
    Opt.Leaf (Opt.Jump index) ->
      [JS.Break (Just (JsName.makeLabel label index))]
    Opt.Chain testChain success failure ->
      [ JS.IfStmt
          (List.foldl1' (JS.Infix JS.OpAnd) (fmap (generateIfTest mode root) testChain))
          (JS.Block $ generateDecider mode label root success)
          (JS.Block $ generateDecider mode label root failure)
      ]
    Opt.FanOut path edges fallback ->
      [ JS.Switch
          ( case edges of
              firstEdge : _ -> generateCaseTest mode root path (fst firstEdge)
              [] -> InternalError.report
                "Generate.JavaScript.Expression.generateDecider"
                "Empty edges list in FanOut"
                "A FanOut decision node must have at least one edge. The decision tree builder should never create a FanOut with zero edges."
          )
          ( foldr
              (\edge cases -> generateCaseBranch mode label root edge : cases)
              [JS.Default (generateDecider mode label root fallback)]
              edges
          )
      ]

generateIfTest :: Mode.Mode -> Name.Name -> (DT.Path, DT.Test) -> JS.Expr
generateIfTest mode root (path, test) =
  let value = pathToJsExpr mode root path
   in case test of
        DT.IsCtor home name index _ opts ->
          let tag =
                case mode of
                  Mode.Dev _ _ _ _ -> JS.Access value JsName.dollar
                  Mode.Prod {} ->
                    case opts of
                      Can.Normal -> JS.Access value JsName.dollar
                      Can.Enum -> value
                      Can.Unbox -> value
           in strictEq tag $
                case mode of
                  Mode.Dev _ _ _ _ -> JS.String (Name.toBuilder name)
                  Mode.Prod {} -> JS.Int (ctorToInt home name index)
        DT.IsBool True ->
          value
        DT.IsBool False ->
          JS.Prefix JS.PrefixNot value
        DT.IsInt int ->
          strictEq value (JS.Int int)
        DT.IsChr char ->
          strictEq (JS.String (Utf8.toBuilder char)) $
            case mode of
              Mode.Dev _ _ _ _ -> JS.Call (JS.Access value (JsName.fromLocal "valueOf")) []
              Mode.Prod {} -> value
        DT.IsStr string ->
          strictEq value (JS.String (Utf8.toBuilder string))
        DT.IsCons ->
          JS.Access value (JsName.fromLocal "b")
        DT.IsNil ->
          JS.Prefix JS.PrefixNot $
            JS.Access value (JsName.fromLocal "b")
        DT.IsTuple ->
          InternalError.report
            "Generate.JavaScript.Expression.generateBoolTest"
            "COMPILER BUG - there should never be tests on a tuple"
            "Tuples are structurally matched and should never appear as a test in the decision tree. This indicates a bug in the pattern match compiler."

generateCaseBranch :: Mode.Mode -> Name.Name -> Name.Name -> (DT.Test, Opt.Decider Opt.Choice) -> JS.Case
generateCaseBranch mode label root (test, subTree) =
  JS.Case
    (generateCaseValue mode test)
    (generateDecider mode label root subTree)

generateCaseValue :: Mode.Mode -> DT.Test -> JS.Expr
generateCaseValue mode test =
  case test of
    DT.IsCtor home name index _ _ ->
      case mode of
        Mode.Dev _ _ _ _ -> JS.String (Name.toBuilder name)
        Mode.Prod {} -> JS.Int (ctorToInt home name index)
    DT.IsInt int ->
      JS.Int int
    DT.IsChr char ->
      JS.String (Utf8.toBuilder char)
    DT.IsStr string ->
      JS.String (Utf8.toBuilder string)
    DT.IsBool _ ->
      InternalError.report
        "Generate.JavaScript.Expression.generateCaseValue"
        "COMPILER BUG - there should never be three tests on a boolean"
        "Booleans only have two constructors (True/False) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
    DT.IsCons ->
      InternalError.report
        "Generate.JavaScript.Expression.generateCaseValue"
        "COMPILER BUG - there should never be three tests on a list"
        "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
    DT.IsNil ->
      InternalError.report
        "Generate.JavaScript.Expression.generateCaseValue"
        "COMPILER BUG - there should never be three tests on a list"
        "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
    DT.IsTuple ->
      InternalError.report
        "Generate.JavaScript.Expression.generateCaseValue"
        "COMPILER BUG - there should never be three tests on a tuple"
        "Tuples are structurally matched and should never appear as a case value in the decision tree. This indicates a bug in the pattern match compiler."

generateCaseTest :: Mode.Mode -> Name.Name -> DT.Path -> DT.Test -> JS.Expr
generateCaseTest mode root path exampleTest =
  let value = pathToJsExpr mode root path
   in case exampleTest of
        DT.IsCtor home name _ _ opts ->
          if name == Name.bool && home == ModuleName.basics
            then value
            else case mode of
              Mode.Dev _ _ _ _ ->
                JS.Access value JsName.dollar
              Mode.Prod {} ->
                case opts of
                  Can.Normal ->
                    JS.Access value JsName.dollar
                  Can.Enum ->
                    value
                  Can.Unbox ->
                    value
        DT.IsInt _ ->
          value
        DT.IsStr _ ->
          value
        DT.IsChr _ ->
          case mode of
            Mode.Dev _ _ _ _ ->
              JS.Call (JS.Access value (JsName.fromLocal "valueOf")) []
            Mode.Prod {} ->
              value
        DT.IsBool _ ->
          InternalError.report
            "Generate.JavaScript.Expression.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a boolean"
            "Booleans only have two constructors (True/False) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsCons ->
          InternalError.report
            "Generate.JavaScript.Expression.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a list"
            "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsNil ->
          InternalError.report
            "Generate.JavaScript.Expression.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a list"
            "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsTuple ->
          InternalError.report
            "Generate.JavaScript.Expression.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a tuple"
            "Tuples are structurally matched and should never appear as a case test. This indicates a bug in the pattern match compiler."

-- PATTERN PATHS

pathToJsExpr :: Mode.Mode -> Name.Name -> DT.Path -> JS.Expr
pathToJsExpr mode root path =
  case path of
    DT.Index index subPath ->
      JS.Access (pathToJsExpr mode root subPath) (JsName.fromIndex index)
    DT.Unbox subPath ->
      case mode of
        Mode.Dev _ _ _ _ ->
          JS.Access (pathToJsExpr mode root subPath) (JsName.fromIndex Index.first)
        Mode.Prod {} ->
          pathToJsExpr mode root subPath
    DT.Empty ->
      JS.Ref (JsName.fromLocal root)

-- GENERATE MAIN

generateMain :: Mode.Mode -> ModuleName.Canonical -> Opt.Main -> JS.Expr
generateMain mode home main =
  case main of
    Opt.Static ->
      JS.Ref (JsName.fromKernel Name.virtualDom "init")
        # JS.Ref (JsName.fromGlobal home "main")
        # JS.Int 0
        # JS.Int 0
    Opt.Dynamic msgType decoder ->
      JS.Ref (JsName.fromGlobal home "main")
        # generateJsExpr mode decoder
        # toDebugMetadata mode msgType

(#) :: JS.Expr -> JS.Expr -> JS.Expr
(#) func arg =
  JS.Call func [arg]

toDebugMetadata :: Mode.Mode -> Can.Type -> JS.Expr
toDebugMetadata mode msgType =
  case mode of
    Mode.Prod {} ->
      -- Production mode: use simple 0 like Elm for compatibility
      JS.Int 0
    Mode.Dev Nothing _ _ _ ->
      -- Dev mode without interfaces: use simple 0 like Elm
      JS.Int 0
    Mode.Dev (Just interfaces) _ _ _ ->
      -- Dev mode with interfaces: full type metadata
      JS.Json . Encode.object $
        [ "versions" ==> Encode.object ["canopy" ==> V.encode V.compiler],
          "types" ==> Type.encodeMetadata (Extract.fromMsg interfaces msgType)
        ]
