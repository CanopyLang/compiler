{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | JavaScript expression code generation for the Canopy compiler.
--
-- This module provides the main expression generator that translates
-- optimized AST expressions to JavaScript code. It uses continuation-passing
-- style code representations for efficient code generation.
--
-- Sub-modules handle specialized concerns:
--
-- * "Generate.JavaScript.Expression.Call" - Function call generation and optimization
-- * "Generate.JavaScript.Expression.Case" - Case/pattern match code generation
--
-- @since 0.19.1
module Generate.JavaScript.Expression
  ( generate,
    generateCtor,
    generateField,
    generateTailDefExpr,
    generateFunction,
    generateMain,
    Code (..),
    codeToExpr,
    codeToStmtList,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Version as Version
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression.Call as Call
import qualified Generate.JavaScript.Expression.Case as ExprCase
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError

-- EXPRESSIONS

generateJsExpr :: Mode.Mode -> Opt.Expr -> JS.Expr
generateJsExpr mode expression =
  codeToExpr (generate mode expression)

generateStmts :: Mode.Mode -> Opt.Expr -> [JS.Stmt]
generateStmts mode expression =
  codeToStmtList (generate mode expression)

-- | Generate JavaScript code from an optimized expression.
--
-- This is the main dispatch function that translates each 'Opt.Expr' variant
-- to the appropriate JavaScript code representation.
--
-- @since 0.19.1
generate :: Mode.Mode -> Opt.Expr -> Code
generate mode expression =
  case expression of
    Opt.Bool bool ->
      JsExpr $ JS.Bool bool
    Opt.Chr char ->
      JsExpr $
        case mode of
          Mode.Dev _ _ _ _ _ ->
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
      let moduleName = ModuleName._module home
       in if Mode.isFFIAlias mode moduleName
            then
              let moduleStr = Name.toChars moduleName
                  nameStr = Name.toChars name
                  jsName = Name.fromChars (moduleStr ++ "." ++ nameStr)
               in JsExpr $ JS.Ref (JsName.fromLocal jsName)
            else JsExpr $ JS.Ref (JsName.fromGlobal home name)
    Opt.VarEnum (Opt.Global home name) index ->
      case mode of
        Mode.Dev _ _ _ _ _ ->
          JsExpr $ JS.Ref (JsName.fromGlobal home name)
        Mode.Prod {} ->
          JsExpr $ JS.Int (Index.toMachine index)
    Opt.VarBox (Opt.Global home name) ->
      JsExpr . JS.Ref $
        ( case mode of
            Mode.Dev _ _ _ _ _ -> JsName.fromGlobal home name
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
      if length args > 100
        then generateLargeFunction mode (fmap JsName.fromLocal args) (generate mode body)
        else generateFunction (fmap JsName.fromLocal args) (generate mode body)
    Opt.Call func args ->
      JsExpr $ Call.generateCall generateJsExpr mode func args
    Opt.ArithBinop op left right ->
      generateArithBinop mode op left right
    Opt.TailCall name args ->
      generateTailCall mode name args
    Opt.If branches final ->
      generateIf mode branches final
    Opt.Let def body ->
      case (def, body) of
        (Opt.TailDef name _ _, Opt.VarLocal bodyName) | name == bodyName ->
          JsExpr $ generateTailDefExpr mode name (getTailDefArgs def) (getTailDefBody def)
        (Opt.TailDef name _ _, Opt.VarLocal bodyName) | name /= bodyName ->
          let defStmt = generateDef mode def
              bodyStmts = codeToStmtList (generate mode body)
              allStmts = flattenStatements [defStmt] ++ bodyStmts
              nonEmptyStmts = filter notEmpty allStmts
           in toCodeBlock nonEmptyStmts
        _ ->
          let defStmt = generateDef mode def
              bodyStmts = codeToStmtList (generate mode body)
              allStmts = flattenStatements [defStmt] ++ bodyStmts
              nonEmptyStmts = filter notEmpty allStmts
           in toCodeBlock nonEmptyStmts
    Opt.Destruct (Opt.Destructor name path) body ->
      let pathDef = JS.Var (JsName.fromLocal name) (generatePath mode path)
       in JsBlock $ flattenStatements [pathDef] ++ codeToStmtList (generate mode body)
    Opt.Case label root decider jumps ->
      JsBlock $ ExprCase.generateCase generateJsExpr generateStmts mode label root decider jumps
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
        Mode.Dev _ _ _ _ _ ->
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
      let toTranslation field =
            ( JsName.fromLocal field,
              JS.String (JsName.toBuilder (generateField mode field))
            )

          toTranslationObject fields =
            JS.Object (fmap toTranslation (Set.toList fields))
       in ( JsExpr . JS.Object $
              [ (JsName.fromLocal "src", JS.String (Shader.toJsStringBuilder src)),
                (JsName.fromLocal "attributes", toTranslationObject attributes),
                (JsName.fromLocal "uniforms", toTranslationObject uniforms)
              ]
          )

-- | Filter predicate for non-empty statements.
--
-- @since 0.19.1
notEmpty :: JS.Stmt -> Bool
notEmpty stmt =
  case stmt of
    JS.EmptyStmt -> False
    _ -> True

-- | Convert a list of statements to a Code block.
--
-- @since 0.19.1
toCodeBlock :: [JS.Stmt] -> Code
toCodeBlock stmts =
  case stmts of
    [singleStmt] -> JsStmt singleStmt
    [] -> JsStmt JS.EmptyStmt
    _ -> JsBlock stmts

-- CODE CHUNKS

-- | Intermediate code representation for JavaScript generation.
--
-- Distinguishes between pure expressions, single statements, and
-- multi-statement blocks to enable correct code generation context.
--
-- @since 0.19.1
data Code
  = JsExpr JS.Expr
  | JsStmt JS.Stmt
  | JsBlock [JS.Stmt]

-- | Convert a code chunk to a JavaScript expression.
--
-- Wraps statement blocks in IIFEs when necessary.
--
-- @since 0.19.1
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

-- | Convert a code chunk to a list of JavaScript statements.
--
-- Unwraps IIFEs and normalizes representations.
--
-- @since 0.19.1
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

-- | Flatten nested blocks and remove empty statements.
--
-- @since 0.19.1
flattenStatements :: [JS.Stmt] -> [JS.Stmt]
flattenStatements = concatMap flattenStatement
  where
    flattenStatement :: JS.Stmt -> [JS.Stmt]
    flattenStatement stmt =
      case stmt of
        JS.Block [] -> []
        JS.Block stmts -> flattenStatements stmts
        JS.ExprStmt (JS.Call (JS.Function Nothing [] innerStmts) []) ->
          flattenStatements innerStmts
        JS.EmptyStmt -> []
        _ -> [stmt]

-- | Convert a code chunk to a single JavaScript statement.
--
-- @since 0.19.1
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

-- | Generate JavaScript for a constructor function.
--
-- Creates an Fn helper call that takes the constructor fields as arguments
-- and returns an object with the tag and field values.
--
-- @since 0.19.1
generateCtor :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> Int -> Code
generateCtor mode (Opt.Global home name) index arity =
  let argNames =
        Index.indexedMap (\i _ -> JsName.fromIndex i) [1 .. arity]

      ctorTag =
        case mode of
          Mode.Dev _ _ _ _ _ -> JS.String (Name.toBuilder name)
          Mode.Prod {} -> JS.Int (ctorToInt home name index)
   in ((generateFunction argNames . JsExpr) . JS.Object $ ((JsName.dollar, ctorTag) : fmap (\n -> (n, JS.Ref n)) argNames))

-- | Convert constructor to integer tag for production mode.
--
-- @since 0.19.1
ctorToInt :: ModuleName.Canonical -> Name.Name -> Index.ZeroBased -> Int
ctorToInt home name index =
  if home == ModuleName.dict && name == "RBNode_elm_builtin" || name == "RBEmpty_elm_builtin"
    then negate (Index.toHuman index)
    else Index.toMachine index

-- RECORDS

-- | Generate a JavaScript object literal for a record.
--
-- @since 0.19.1
generateRecord :: Mode.Mode -> Map.Map Name.Name Opt.Expr -> JS.Expr
generateRecord mode fields =
  let toPair (field, value) =
        (generateField mode field, generateJsExpr mode value)
   in JS.Object (fmap toPair (Map.toList fields))

-- | Generate a JavaScript property name for a record field.
--
-- In production mode, uses the minified field name from the shortener map.
-- In dev mode, uses the original field name.
--
-- @since 0.19.1
generateField :: Mode.Mode -> Name.Name -> JsName.Name
generateField mode name =
  case mode of
    Mode.Dev _ _ _ _ _ ->
      JsName.fromLocal name
    Mode.Prod fields _ _ _ _ _ ->
      maybe
        (InternalError.report "Generate.JavaScript.Expression.generateField" "Unknown field name in production mode" "The field shortener map is missing an expected field.")
        id
        (Map.lookup name fields)

-- | Generate large functions (>100 parameters) with chunking.
--
-- Splits into 9-argument chunks and nests them to avoid stack overflow.
--
-- @since 0.19.1
generateLargeFunction :: Mode.Mode -> [JsName.Name] -> Code -> Code
generateLargeFunction _mode args body =
  let chunks = chunkList 9 args
   in case chunks of
        [] -> body
        [single] -> generateFunction single body
        (first : rest) ->
          let innerFn = foldr (\chunk acc -> generateFunction chunk acc) body rest
           in generateFunction first innerFn

-- | Split a list into chunks of the given size.
--
-- @since 0.19.1
chunkList :: Int -> [a] -> [[a]]
chunkList _ [] = []
chunkList n xs =
  let (chunk, rest) = splitAt n xs
   in chunk : chunkList n rest

-- DEBUG

-- | Generate JavaScript for debug operations.
--
-- @since 0.19.1
generateDebug :: Mode.Mode -> Name.Name -> ModuleName.Canonical -> Ann.Region -> Maybe Name.Name -> JS.Expr
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

-- | Generate JavaScript object for a source region.
--
-- @since 0.19.1
regionToJsExpr :: Mode.Mode -> Ann.Region -> JS.Expr
regionToJsExpr mode (Ann.Region start end) =
  if Mode.isElmCompatible mode
    then
      JS.Object
        [ (JsName.fromLocal "I", positionToJsExpr mode start),
          (JsName.fromLocal "N", positionToJsExpr mode end)
        ]
    else
      JS.Object
        [ (JsName.fromLocal "start", positionToJsExpr mode start),
          (JsName.fromLocal "end", positionToJsExpr mode end)
        ]

-- | Generate JavaScript object for a source position.
--
-- @since 0.19.1
positionToJsExpr :: Mode.Mode -> Ann.Position -> JS.Expr
positionToJsExpr mode (Ann.Position line column) =
  if Mode.isElmCompatible mode
    then
      JS.Object
        [ (JsName.fromLocal "z", JS.Int (fromIntegral line)),
          (JsName.fromLocal "A", JS.Int (fromIntegral column))
        ]
    else
      JS.Object
        [ (JsName.fromLocal "line", JS.Int (fromIntegral line)),
          (JsName.fromLocal "column", JS.Int (fromIntegral column))
        ]

-- FUNCTION

-- | Generate JavaScript for a function expression using Fn helpers.
--
-- Uses F2..F9 helpers for multi-argument functions, and nested single-arg
-- functions for higher arities.
--
-- @since 0.19.1
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

-- | Generate a tail-call optimized function using a labeled while loop.
--
-- @since 0.19.1
generateTailFunction :: Name.Name -> [JsName.Name] -> Code -> Code
generateTailFunction functionName args body =
  let labelName = JsName.fromLocal functionName
      bodyStmts = codeToStmtList body
      whileBody = case bodyStmts of
        [stmt] -> JS.Block [stmt, JS.EmptyStmt]
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

-- | Generate JavaScript for a native arithmetic binary operation.
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
-- @since 0.19.2
arithOpToJs :: Can.ArithOp -> JS.InfixOp
arithOpToJs Can.Add = JS.OpAdd
arithOpToJs Can.Sub = JS.OpSub
arithOpToJs Can.Mul = JS.OpMul
arithOpToJs Can.Div = JS.OpDiv

-- DEFINITIONS

-- | Generate a JavaScript variable declaration for a definition.
--
-- @since 0.19.1
generateDef :: Mode.Mode -> Opt.Def -> JS.Stmt
generateDef mode def =
  case def of
    Opt.Def name body ->
      JS.Var (JsName.fromLocal name) (generateJsExpr mode body)
    Opt.TailDef name argNames body ->
      JS.Var (JsName.fromLocal name) (generateTailDefExpr mode name argNames body)

-- | Extract argument names from a TailDef.
--
-- @since 0.19.1
getTailDefArgs :: Opt.Def -> [Name.Name]
getTailDefArgs def =
  case def of
    Opt.TailDef _ args _ -> args
    Opt.Def _ _ -> []

-- | Extract body from a TailDef.
--
-- @since 0.19.1
getTailDefBody :: Opt.Def -> Opt.Expr
getTailDefBody def =
  case def of
    Opt.TailDef _ _ body -> body
    _ ->
      InternalError.report
        "Generate.JavaScript.Expression.getTailDefBody"
        "Called on non-TailDef"
        "getTailDefBody must only be called on Opt.TailDef values. The caller must verify the definition is a TailDef before invoking this function."

-- | Generate the JavaScript expression for a tail-recursive function definition.
--
-- @since 0.19.1
generateTailDefExpr :: Mode.Mode -> Name.Name -> [Name.Name] -> Opt.Expr -> JS.Expr
generateTailDefExpr mode name argNames body =
  codeToExpr (generateTailFunction name (fmap JsName.fromLocal argNames) (generate mode body))

-- | Generate tail-call assignment with temporary variables.
--
-- @since 0.19.1
generateTailCall :: Mode.Mode -> Name.Name -> [(Name.Name, Opt.Expr)] -> Code
generateTailCall mode name args =
  JsBlock allStmts
  where
    tempVarNames =
      fmap (\(argName, argExpr) ->
        (JsName.makeTemp argName, generateJsExpr mode argExpr)) args
    realAssignments =
      fmap (\(argName, _) ->
        JS.ExprStmtWithSemi (JS.Assign
          (JS.LRef (JsName.fromLocal argName))
          (JS.Ref (JsName.makeTemp argName)))) args
    continueStmt = JS.Continue (Just (JsName.fromLocal name))
    tempVarStmt =
      case tempVarNames of
        [] -> []
        _ -> [JS.Vars tempVarNames]
    allStmts = tempVarStmt ++ realAssignments ++ [continueStmt]

-- PATHS

-- | Generate JavaScript for a destructuring path expression.
--
-- @since 0.19.1
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
        Mode.Dev _ _ _ _ _ ->
          JS.Access (generatePath mode subPath) (JsName.fromIndex Index.first)
        Mode.Prod {} ->
          generatePath mode subPath

-- GENERATE IFS

-- | Generate JavaScript for an if expression.
--
-- @since 0.19.1
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

-- | Generate ternary if expression.
--
-- @since 0.19.1
addExprIf :: (JS.Expr, Code) -> JS.Expr -> JS.Expr
addExprIf (condition, branch) = JS.If condition (codeToExpr branch)

-- | Generate if statement.
--
-- @since 0.19.1
addStmtIf :: (JS.Expr, Code) -> JS.Stmt -> JS.Stmt
addStmtIf (condition, branch) = JS.IfStmt condition (codeToStmt branch)

-- | Check if a code chunk requires a statement block.
--
-- @since 0.19.1
isBlock :: Code -> Bool
isBlock code =
  case code of
    JsBlock _ -> True
    JsStmt _ -> False
    JsExpr _ -> False

-- | Flatten chained if expressions for cleaner output.
--
-- @since 0.19.1
crushIfs :: [(Opt.Expr, Opt.Expr)] -> Opt.Expr -> ([(Opt.Expr, Opt.Expr)], Opt.Expr)
crushIfs = crushIfsHelp []

-- | Accumulator helper for crushing if chains.
--
-- @since 0.19.1
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
        -- WILDCARD AUDIT: All non-If expressions terminate the chain.
        -- Enumerating every Opt.Expr variant is impractical; new variants
        -- are terminal by default, which is the correct behaviour.
        _ ->
          (reverse visitedBranches, final)
    visiting : unvisited ->
      crushIfsHelp (visiting : visitedBranches) unvisited final

-- GENERATE MAIN

-- | Generate JavaScript for the main entry point.
--
-- Handles Static (VirtualDom), Dynamic (Platform.Program), TestMain,
-- and BrowserTestMain variants.
--
-- @since 0.19.1
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
    Opt.TestMain ->
      JS.Function Nothing []
        [ JS.Return
            ( JS.Object
                [ (JsName.fromLocal "_testMain", JS.Ref (JsName.fromGlobal home "main"))
                ]
            )
        ]
    Opt.BrowserTestMain ->
      JS.Function Nothing []
        [ JS.Return
            ( JS.Object
                [ (JsName.fromLocal "_browserTestMain", JS.Ref (JsName.fromGlobal home "main"))
                ]
            )
        ]

-- | Left-to-right function application operator.
--
-- @since 0.19.1
(#) :: JS.Expr -> JS.Expr -> JS.Expr
(#) func arg =
  JS.Call func [arg]

-- | Generate debug type metadata for dynamic main.
--
-- @since 0.19.1
toDebugMetadata :: Mode.Mode -> Can.Type -> JS.Expr
toDebugMetadata mode msgType =
  case mode of
    Mode.Prod {} ->
      JS.Int 0
    Mode.Dev Nothing _ _ _ _ ->
      JS.Int 0
    Mode.Dev (Just interfaces) _ _ _ _ ->
      JS.Json . Encode.object $
        [ "versions" ==> Encode.object ["canopy" ==> Version.encode Version.compiler],
          "types" ==> Type.encodeMetadata (Extract.fromMsg interfaces msgType)
        ]

