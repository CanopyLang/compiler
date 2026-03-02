{-# LANGUAGE OverloadedStrings #-}

module Canonicalize.Expression
  ( canonicalize,
    FreeLocals,
    Uses (..),
    verifyBindings,
    gatherTypedArgs,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified AST.Utils.Type as Type
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Environment.Dups as Dups
import qualified Canonicalize.Pattern as Pattern
import qualified Canonicalize.Type as Type
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Monad (foldM)
import qualified Data.Graph as Graph
import qualified Canopy.Data.Index as Index
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- RESULTS

type Result i w a =
  Result.Result i w Error.Error a

type FreeLocals =
  Map.Map Name.Name Uses

data Uses = Uses
  { _direct :: {-# UNPACK #-} !Int,
    _delayed :: {-# UNPACK #-} !Int
  }

-- CANONICALIZE

canonicalize :: Env.Env -> Src.Expr -> Result FreeLocals [Warning.Warning] Can.Expr
canonicalize env (Ann.At region expression) =
  Ann.At region
    <$> case expression of
      Src.Str string ->
        Result.ok (Can.Str string)
      Src.Chr char ->
        Result.ok (Can.Chr char)
      Src.Int int ->
        Result.ok (Can.Int int)
      Src.Float float ->
        Result.ok (Can.Float float)
      Src.Var varType name ->
        canonicalizeVar region env varType name
      Src.VarQual varType prefix name ->
        canonicalizeVarQual region env varType prefix name
      Src.List exprs ->
        Can.List <$> traverse (canonicalize env) exprs
      Src.Op op ->
        do
          (Env.Binop _ home name annotation _ _) <- Env.findBinop region env op
          return (Can.VarOperator op home name annotation)
      Src.Negate expr ->
        Can.Negate <$> canonicalize env expr
      Src.Binops ops final ->
        Ann.toValue <$> canonicalizeBinops region env ops final
      Src.Lambda srcArgs body ->
        canonicalizeLambda env srcArgs body
      Src.Call func args ->
        Can.Call
          <$> canonicalize env func
          <*> traverse (canonicalize env) args
      Src.If branches finally ->
        Can.If
          <$> traverse (canonicalizeIfBranch env) branches
          <*> canonicalize env finally
      Src.Let defs expr ->
        Ann.toValue <$> canonicalizeLet region env defs expr
      Src.Case expr branches ->
        Can.Case
          <$> canonicalize env expr
          <*> traverse (canonicalizeCaseBranch env) branches
      Src.Accessor field ->
        Result.ok $ Can.Accessor field
      Src.Access record field ->
        Can.Access
          <$> canonicalize env record
          <*> Result.ok field
      Src.Update (Ann.At reg name) fields ->
        let makeCanFields =
              Dups.checkFields' (\r t -> Can.FieldUpdate r <$> canonicalize env t) fields
         in Can.Update name
              <$> (Ann.At reg <$> findVar reg env name)
              <*> (sequenceA =<< makeCanFields)
      Src.Record fields ->
        do
          fieldDict <- Dups.checkFields fields
          Can.Record <$> traverse (canonicalize env) fieldDict
      Src.Unit ->
        Result.ok Can.Unit
      Src.Tuple a b cs ->
        Can.Tuple
          <$> canonicalize env a
          <*> canonicalize env b
          <*> canonicalizeTupleExtras region env cs
      Src.Shader src tipe ->
        Result.ok (Can.Shader src tipe)
      Src.Interpolation segments ->
        canonicalizeInterpolation env region segments

-- CANONICALIZE VARIABLES

-- | Resolve an unqualified variable reference.
--
-- Lowercase variables are resolved through the environment's local
-- and top-level scope. Uppercase variables are resolved as constructors.
canonicalizeVar :: Ann.Region -> Env.Env -> Src.VarType -> Name.Name -> Result FreeLocals [Warning.Warning] Can.Expr_
canonicalizeVar region env Src.LowVar name = findVar region env name
canonicalizeVar region env Src.CapVar name = toVarCtor name <$> Env.findCtor region env name

-- | Resolve a qualified variable reference (e.g. @Module.function@).
--
-- Follows the same lowercase/uppercase dispatch as 'canonicalizeVar'
-- but uses the qualified lookup path through the environment.
canonicalizeVarQual :: Ann.Region -> Env.Env -> Src.VarType -> Name.Name -> Name.Name -> Result FreeLocals [Warning.Warning] Can.Expr_
canonicalizeVarQual region env Src.LowVar prefix name = findVarQual region env prefix name
canonicalizeVarQual region env Src.CapVar prefix name = toVarCtor name <$> Env.findCtorQual region env prefix name

-- CANONICALIZE LAMBDA

-- | Canonicalize a lambda expression.
--
-- Verifies that pattern arguments are non-overlapping, extends the
-- local environment with the bindings introduced by the patterns,
-- and canonicalizes the body in the extended scope.
canonicalizeLambda :: Env.Env -> [Src.Pattern] -> Src.Expr -> Result FreeLocals [Warning.Warning] Can.Expr_
canonicalizeLambda env srcArgs body =
  delayedUsage $ do
    (args, bindings) <-
      Pattern.verify Error.DPLambdaArgs $
        traverse (Pattern.canonicalize env) srcArgs
    newEnv <- Env.addLocals bindings env
    (cbody, freeLocals) <-
      verifyBindings Warning.Pattern bindings (canonicalize newEnv body)
    return (Can.Lambda args cbody, freeLocals)

-- CANONICALIZE TUPLE EXTRAS

canonicalizeTupleExtras :: Ann.Region -> Env.Env -> [Src.Expr] -> Result FreeLocals [Warning.Warning] (Maybe Can.Expr)
canonicalizeTupleExtras region env extras =
  case extras of
    [] ->
      Result.ok Nothing
    [three] ->
      Just <$> canonicalize env three
    _ ->
      Result.throw (Error.TupleLargerThanThree region)

-- CANONICALIZE INTERPOLATION

canonicalizeInterpolation ::
  Env.Env ->
  Ann.Region ->
  [Src.InterpolationSegment] ->
  Result FreeLocals [Warning.Warning] Can.Expr_
canonicalizeInterpolation env region segments =
  case segmentsToExprs region segments of
    [] ->
      Result.ok (Can.Str Utf8.empty)
    [single] ->
      Ann.toValue <$> canonicalize env single
    exprs ->
      Can.StringConcat <$> traverse (canonicalize env) exprs

segmentsToExprs :: Ann.Region -> [Src.InterpolationSegment] -> [Src.Expr]
segmentsToExprs region = concatMap (segmentToExpr region)

segmentToExpr :: Ann.Region -> Src.InterpolationSegment -> [Src.Expr]
segmentToExpr region segment =
  case segment of
    Src.IStr str
      | Utf8.isEmpty str -> []
      | otherwise -> [Ann.At region (Src.Str str)]
    Src.IExpr expr -> [expr]

-- CANONICALIZE IF BRANCH

canonicalizeIfBranch :: Env.Env -> (Src.Expr, Src.Expr) -> Result FreeLocals [Warning.Warning] (Can.Expr, Can.Expr)
canonicalizeIfBranch env (condition, branch) =
  (,)
    <$> canonicalize env condition
    <*> canonicalize env branch

-- CANONICALIZE CASE BRANCH

canonicalizeCaseBranch :: Env.Env -> (Src.Pattern, Src.Expr) -> Result FreeLocals [Warning.Warning] Can.CaseBranch
canonicalizeCaseBranch env (pattern, expr) =
  directUsage $
    do
      (cpattern, bindings) <-
        Pattern.verify Error.DPCaseBranch $
          Pattern.canonicalize env pattern
      newEnv <- Env.addLocals bindings env

      (cexpr, freeLocals) <-
        verifyBindings Warning.Pattern bindings (canonicalize newEnv expr)

      return (Can.CaseBranch cpattern cexpr, freeLocals)

-- CANONICALIZE BINOPS

canonicalizeBinops :: Ann.Region -> Env.Env -> [(Src.Expr, Ann.Located Name.Name)] -> Src.Expr -> Result FreeLocals [Warning.Warning] Can.Expr
canonicalizeBinops overallRegion env ops final =
  let canonicalizeHelp (expr, Ann.At region op) =
        (,)
          <$> canonicalize env expr
          <*> Env.findBinop region env op
   in runBinopStepper overallRegion
        =<< ( More
                <$> traverse canonicalizeHelp ops
                <*> canonicalize env final
            )

data Step
  = Done Can.Expr
  | More [(Can.Expr, Env.Binop)] Can.Expr
  | Error Env.Binop Env.Binop

runBinopStepper :: Ann.Region -> Step -> Result FreeLocals w Can.Expr
runBinopStepper overallRegion step =
  case step of
    Done expr ->
      Result.ok expr
    More [] expr ->
      Result.ok expr
    More ((expr, op) : rest) final ->
      runBinopStepper overallRegion $
        toBinopStep (toBinop op expr) op rest final
    Error (Env.Binop op1 _ _ _ _ _) (Env.Binop op2 _ _ _ _ _) ->
      Result.throw (Error.Binop overallRegion op1 op2)

toBinopStep :: (Can.Expr -> Can.Expr) -> Env.Binop -> [(Can.Expr, Env.Binop)] -> Can.Expr -> Step
toBinopStep makeBinop rootOp@(Env.Binop _ _ _ _ rootAssociativity rootPrecedence) middle final =
  case middle of
    [] ->
      Done (makeBinop final)
    (expr, op@(Env.Binop _ _ _ _ associativity precedence)) : rest
      | precedence < rootPrecedence ->
          More ((makeBinop expr, op) : rest) final
      | precedence > rootPrecedence ->
          applyHigherPrecedence makeBinop rootOp (toBinopStep (toBinop op expr) op rest final)
      | otherwise ->
          applyEqualPrecedence makeBinop rootOp op expr rest final rootAssociativity associativity

applyHigherPrecedence :: (Can.Expr -> Can.Expr) -> Env.Binop -> Step -> Step
applyHigherPrecedence makeBinop _ (Done newLast) = Done (makeBinop newLast)
applyHigherPrecedence makeBinop rootOp (More newMiddle newLast) = toBinopStep makeBinop rootOp newMiddle newLast
applyHigherPrecedence _ _ (Error a b) = Error a b

applyEqualPrecedence :: (Can.Expr -> Can.Expr) -> Env.Binop -> Env.Binop -> Can.Expr -> [(Can.Expr, Env.Binop)] -> Can.Expr -> Binop.Associativity -> Binop.Associativity -> Step
applyEqualPrecedence makeBinop _ op expr rest final Binop.Left Binop.Left =
  toBinopStep (\right -> toBinop op (makeBinop expr) right) op rest final
applyEqualPrecedence makeBinop _ op expr rest final Binop.Right Binop.Right =
  toBinopStep (\right -> makeBinop (toBinop op expr right)) op rest final
applyEqualPrecedence _ rootOp op _ _ _ _ _ =
  Error rootOp op

-- | Convert binary operator to canonical expression.
--
-- Constructs a canonical binary operator expression by classifying the
-- operator and merging source regions. The classification determines whether
-- the operator will be compiled as a native JavaScript operator or remain
-- as a function call.
--
-- The process:
--
-- 1. **Classify** - Determine if operator is native arithmetic or user-defined
-- 2. **Merge Regions** - Combine source regions from left and right operands
-- 3. **Construct** - Create 'Can.BinopOp' node with classification and annotation
--
-- ==== Examples
--
-- >>> toBinop (Env.Binop "+" ModuleName.basics "add" ann L N) leftExpr rightExpr
-- Can.BinopOp (Can.NativeArith Can.Add) ann leftExpr rightExpr
--
-- >>> toBinop (Env.Binop "==" ModuleName.basics "eq" ann L N) leftExpr rightExpr
-- Can.BinopOp (Can.UserDefined "eq" ModuleName.basics "eq") ann leftExpr rightExpr
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) operator classification
-- * **Space Complexity**: O(1) node allocation
--
-- @since 0.19.2
toBinop :: Env.Binop -> Can.Expr -> Can.Expr -> Can.Expr
toBinop (Env.Binop op home name annotation _ _) left right =
  let kind = classifyBinop home op name
  in Ann.merge left right (Can.BinopOp kind annotation left right)

-- | Classify a binary operator as native or custom.
--
-- Determines whether a binary operator from the Canonical AST should be
-- compiled as a native JavaScript operator or remain as a function call.
-- This classification drives the optimization and code generation strategy.
--
-- Native operators are identified by their home module (Basics) and their
-- canonical names. All other operators are classified as custom, including
-- user-defined operators and comparison operators.
--
-- **Native arithmetic operators:**
--
-- * @Basics.add@ → OpAdd (+)
-- * @Basics.sub@ → OpSub (-)
-- * @Basics.mul@ → OpMul (*)
-- * @Basics.fdiv@ → OpDiv (/)
--
-- **Custom operators (examples):**
--
-- * @Basics.eq@ (==) - Comparison, not arithmetic
-- * @Basics.append@ (++) - String/list operation
-- * @List.cons@ (::) - List construction
-- * User-defined operators from any module
--
-- ==== Examples
--
-- >>> classifyBinop ModuleName.basics (Name.fromChars "+")
-- NativeArith Add
--
-- >>> classifyBinop ModuleName.basics (Name.fromChars "==")
-- UserDefined "==" ModuleName.basics "=="
--
-- >>> classifyBinop userModule (Name.fromChars "<>")
-- UserDefined "<>" userModule "<>"
--
-- ==== Algorithm
--
-- 1. **Module Check** - Verify operator home is Basics module
-- 2. **Name Lookup** - Match operator canonical name against known arithmetic ops
-- 3. **Classification** - Return Native with ArithOp or Custom
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) map lookup
-- * **Space Complexity**: O(1) no allocation
-- * **Optimization Impact**: Determines entire optimization strategy
--
-- @since 0.19.2
classifyBinop :: ModuleName.Canonical -> Name.Name -> Name.Name -> Can.BinopKind
classifyBinop home op name
  | ModuleName.isBasics home = classifyBasicsOp op name
  | otherwise = Can.UserDefined op home name

-- | Classify Basics module operator.
--
-- Maps specific arithmetic operator names from the Basics module to their
-- corresponding native arithmetic operation types. Operators not matching
-- the native arithmetic set are classified as user-defined, allowing them
-- to remain as function calls.
--
-- This function is called only after verifying the operator's home module
-- is Basics, ensuring we only check operators from the standard library.
--
-- ==== Arithmetic Operator Mapping
--
-- * @"+"@ → 'Can.NativeArith' 'Can.Add'
-- * @"-"@ → 'Can.NativeArith' 'Can.Sub'
-- * @"*"@ → 'Can.NativeArith' 'Can.Mul'
-- * @"/"@ → 'Can.NativeArith' 'Can.Div'
--
-- All other Basics operators (==, ++, <|, etc.) remain user-defined.
--
-- ==== Examples
--
-- >>> classifyBasicsOp (Name.fromChars "+")
-- NativeArith Add
--
-- >>> classifyBasicsOp (Name.fromChars "==")
-- UserDefined "==" ModuleName.basics "=="
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - constant-time name comparison
-- * **Space Complexity**: O(1) - no allocation
--
-- @since 0.19.2
classifyBasicsOp :: Name.Name -> Name.Name -> Can.BinopKind
classifyBasicsOp op name
  | op == Name.fromChars "+" = Can.NativeArith Can.Add
  | op == Name.fromChars "-" = Can.NativeArith Can.Sub
  | op == Name.fromChars "*" = Can.NativeArith Can.Mul
  | op == Name.fromChars "/" = Can.NativeArith Can.Div
  | otherwise = Can.UserDefined op ModuleName.basics name

-- CANONICALIZE LET

canonicalizeLet :: Ann.Region -> Env.Env -> [Ann.Located Src.Def] -> Src.Expr -> Result FreeLocals [Warning.Warning] Can.Expr
canonicalizeLet letRegion env defs body =
  directUsage $
    do
      bindings <-
        Dups.detect (Error.DuplicatePattern Error.DPLetBinding) $
          List.foldl' addBindings Dups.none defs

      newEnv <- Env.addLocals bindings env

      verifyBindings Warning.Def bindings $
        do
          nodes <- foldM (addDefNodes newEnv) [] defs
          cbody <- canonicalize newEnv body
          detectCycles letRegion (Graph.stronglyConnComp nodes) cbody

-- ADD BINDINGS

addBindings :: Dups.Dict Ann.Region -> Ann.Located Src.Def -> Dups.Dict Ann.Region
addBindings bindings (Ann.At _ def) =
  case def of
    Src.Define (Ann.At region name) _ _ _ ->
      Dups.insert name region region bindings
    Src.Destruct pattern _ ->
      addBindingsHelp bindings pattern

addBindingsHelp :: Dups.Dict Ann.Region -> Src.Pattern -> Dups.Dict Ann.Region
addBindingsHelp bindings (Ann.At region pattern) =
  case pattern of
    Src.PAnything ->
      bindings
    Src.PVar name ->
      Dups.insert name region region bindings
    Src.PRecord fields ->
      let addField dict (Ann.At fieldRegion name) =
            Dups.insert name fieldRegion fieldRegion dict
       in List.foldl' addField bindings fields
    Src.PUnit ->
      bindings
    Src.PTuple a b cs ->
      List.foldl' addBindingsHelp bindings (a : b : cs)
    Src.PCtor _ _ patterns ->
      List.foldl' addBindingsHelp bindings patterns
    Src.PCtorQual _ _ _ patterns ->
      List.foldl' addBindingsHelp bindings patterns
    Src.PList patterns ->
      List.foldl' addBindingsHelp bindings patterns
    Src.PCons hd tl ->
      addBindingsHelp (addBindingsHelp bindings hd) tl
    Src.PAlias aliasPattern (Ann.At nameRegion name) ->
      Dups.insert name nameRegion nameRegion $
        addBindingsHelp bindings aliasPattern
    Src.PChr _ ->
      bindings
    Src.PStr _ ->
      bindings
    Src.PInt _ ->
      bindings

-- BUILD BINDINGS GRAPH

type Node =
  (Binding, Name.Name, [Name.Name])

data Binding
  = Define Can.Def
  | Edge (Ann.Located Name.Name)
  | Destruct Can.Pattern Can.Expr

addDefNodes :: Env.Env -> [Node] -> Ann.Located Src.Def -> Result FreeLocals [Warning.Warning] [Node]
addDefNodes env nodes (Ann.At _ (Src.Define aname@(Ann.At _ name) srcArgs body maybeType)) =
  addDefineNode env nodes aname name srcArgs body maybeType
addDefNodes env nodes (Ann.At _ (Src.Destruct pattern body)) =
  addDestructNode env nodes pattern body

addDefineNode :: Env.Env -> [Node] -> Ann.Located Name.Name -> Name.Name -> [Src.Pattern] -> Src.Expr -> Maybe Src.Type -> Result FreeLocals [Warning.Warning] [Node]
addDefineNode env nodes aname name srcArgs body Nothing =
  do
    (args, argBindings) <-
      Pattern.verify (Error.DPFuncArgs name) $
        traverse (Pattern.canonicalize env) srcArgs
    newEnv <- Env.addLocals argBindings env
    (cbody, freeLocals) <-
      verifyBindings Warning.Pattern argBindings (canonicalize newEnv body)
    let cdef = Can.Def aname args cbody
    let node = (Define cdef, name, Map.keys freeLocals)
    logLetLocals args freeLocals (node : nodes)
addDefineNode env nodes aname name srcArgs body (Just tipe) =
  do
    (Can.Forall freeVars ctipe) <- Type.toAnnotation env tipe
    ((args, resultType), argBindings) <-
      Pattern.verify (Error.DPFuncArgs name) $
        gatherTypedArgs env name srcArgs ctipe Index.first []
    newEnv <- Env.addLocals argBindings env
    (cbody, freeLocals) <-
      verifyBindings Warning.Pattern argBindings (canonicalize newEnv body)
    let cdef = Can.TypedDef aname freeVars args cbody resultType
    let node = (Define cdef, name, Map.keys freeLocals)
    logLetLocals args freeLocals (node : nodes)

addDestructNode :: Env.Env -> [Node] -> Src.Pattern -> Src.Expr -> Result FreeLocals [Warning.Warning] [Node]
addDestructNode env nodes pattern body =
  do
    (cpattern, _bindings) <-
      Pattern.verify Error.DPDestruct $
        Pattern.canonicalize env pattern
    Result.Result $ \fs ws bad good ->
      let (Result.Result k) = canonicalize env body
       in k
            Map.empty
            ws
            ( \freeLocals warnings errors ->
                bad (Map.unionWith combineUses freeLocals fs) warnings errors
            )
            ( \freeLocals warnings cbody ->
                let names = getPatternNames [] pattern
                    name = Name.fromManyNames (map Ann.toValue names)
                    node = (Destruct cpattern cbody, name, Map.keys freeLocals)
                 in good
                      (Map.unionWith combineUses fs freeLocals)
                      warnings
                      (List.foldl' (addEdge [name]) (node : nodes) names)
            )

logLetLocals :: [arg] -> FreeLocals -> value -> Result FreeLocals w value
logLetLocals args letLocals value =
  Result.Result $ \freeLocals warnings _ good ->
    good
      ( Map.unionWith combineUses freeLocals $
          case args of
            [] -> letLocals
            _ -> Map.map delayUse letLocals
      )
      warnings
      value

addEdge :: [Name.Name] -> [Node] -> Ann.Located Name.Name -> [Node]
addEdge edges nodes aname@(Ann.At _ name) =
  (Edge aname, name, edges) : nodes

getPatternNames :: [Ann.Located Name.Name] -> Src.Pattern -> [Ann.Located Name.Name]
getPatternNames names (Ann.At region pattern) =
  case pattern of
    Src.PAnything -> names
    Src.PVar name -> Ann.At region name : names
    Src.PRecord fields -> fields ++ names
    Src.PAlias ptrn name -> getPatternNames (name : names) ptrn
    Src.PUnit -> names
    Src.PTuple a b cs -> List.foldl' getPatternNames (getPatternNames (getPatternNames names a) b) cs
    Src.PCtor _ _ args -> List.foldl' getPatternNames names args
    Src.PCtorQual _ _ _ args -> List.foldl' getPatternNames names args
    Src.PList patterns -> List.foldl' getPatternNames names patterns
    Src.PCons hd tl -> getPatternNames (getPatternNames names hd) tl
    Src.PChr _ -> names
    Src.PStr _ -> names
    Src.PInt _ -> names

-- GATHER TYPED ARGS

gatherTypedArgs ::
  Env.Env ->
  Name.Name ->
  [Src.Pattern] ->
  Can.Type ->
  Index.ZeroBased ->
  [(Can.Pattern, Can.Type)] ->
  Result Pattern.DupsDict w ([(Can.Pattern, Can.Type)], Can.Type)
gatherTypedArgs env name srcArgs tipe index revTypedArgs =
  case srcArgs of
    [] ->
      return (reverse revTypedArgs, tipe)
    srcArg : otherSrcArgs ->
      case Type.iteratedDealias tipe of
        Can.TLambda argType resultType ->
          do
            arg <- Pattern.canonicalize env srcArg
            gatherTypedArgs env name otherSrcArgs resultType (Index.next index) $
              (arg, argType) : revTypedArgs
        _ ->
          let (Ann.At start _, Ann.At end _) = case (srcArgs, reverse srcArgs) of
                (firstArg : _, lastArg : _) -> (firstArg, lastArg)
                _ -> InternalError.report
                  "Canonicalize.Expression.gatherTypedArgs"
                  "Expected non-empty srcArgs"
                  "gatherTypedArgs was called with a non-empty srcArgs list, but the (srcArgs, reverse srcArgs) pattern match failed to extract first and last elements. This should be impossible for a non-empty list."
           in Result.throw $
                Error.AnnotationTooShort (Ann.mergeRegions start end) name index (length srcArgs)

-- DETECT CYCLES

detectCycles :: Ann.Region -> [Graph.SCC Binding] -> Can.Expr -> Result i w Can.Expr
detectCycles _ [] body = Result.ok body
detectCycles letRegion (scc : subSccs) body =
  detectSCC letRegion scc subSccs body

detectSCC :: Ann.Region -> Graph.SCC Binding -> [Graph.SCC Binding] -> Can.Expr -> Result i w Can.Expr
detectSCC letRegion (Graph.AcyclicSCC binding) subSccs body =
  detectAcyclicBinding letRegion binding subSccs body
detectSCC letRegion (Graph.CyclicSCC bindings) subSccs body =
  Ann.At letRegion
    <$> ( Can.LetRec
            <$> checkCycle bindings []
            <*> detectCycles letRegion subSccs body
        )

detectAcyclicBinding :: Ann.Region -> Binding -> [Graph.SCC Binding] -> Can.Expr -> Result i w Can.Expr
detectAcyclicBinding letRegion (Define def) subSccs body =
  Ann.At letRegion . Can.Let def <$> detectCycles letRegion subSccs body
detectAcyclicBinding letRegion (Edge _) subSccs body =
  detectCycles letRegion subSccs body
detectAcyclicBinding letRegion (Destruct pattern expr) subSccs body =
  Ann.At letRegion . Can.LetDestruct pattern expr <$> detectCycles letRegion subSccs body

checkCycle :: [Binding] -> [Can.Def] -> Result i w [Can.Def]
checkCycle [] defs = Result.ok defs
checkCycle (binding : otherBindings) defs =
  checkCycleBinding binding otherBindings defs

checkCycleBinding :: Binding -> [Binding] -> [Can.Def] -> Result i w [Can.Def]
checkCycleBinding (Define def@(Can.Def name args _)) otherBindings defs
  | null args = Result.throw (Error.RecursiveLet name (toNames otherBindings defs))
  | otherwise = checkCycle otherBindings (def : defs)
checkCycleBinding (Define def@(Can.TypedDef name _ args _ _)) otherBindings defs
  | null args = Result.throw (Error.RecursiveLet name (toNames otherBindings defs))
  | otherwise = checkCycle otherBindings (def : defs)
checkCycleBinding (Edge name) otherBindings defs =
  Result.throw (Error.RecursiveLet name (toNames otherBindings defs))
checkCycleBinding (Destruct _ _) otherBindings defs =
  -- a Destruct cannot appear in a cycle without any Edge values
  -- so we just keep going until we get to the edges
  checkCycle otherBindings defs

toNames :: [Binding] -> [Can.Def] -> [Name.Name]
toNames [] revDefs = reverse (map getDefName revDefs)
toNames (binding : otherBindings) revDefs =
  bindingName binding otherBindings revDefs

bindingName :: Binding -> [Binding] -> [Can.Def] -> [Name.Name]
bindingName (Define def) otherBindings revDefs = getDefName def : toNames otherBindings revDefs
bindingName (Edge (Ann.At _ name)) otherBindings revDefs = name : toNames otherBindings revDefs
bindingName (Destruct _ _) otherBindings revDefs = toNames otherBindings revDefs

getDefName :: Can.Def -> Name.Name
getDefName def =
  case def of
    Can.Def (Ann.At _ name) _ _ ->
      name
    Can.TypedDef (Ann.At _ name) _ _ _ _ ->
      name

-- LOG VARIABLE USES

logVar :: Name.Name -> a -> Result FreeLocals w a
logVar name value =
  Result.Result $ \freeLocals warnings _ good ->
    good (Map.insertWith combineUses name oneDirectUse freeLocals) warnings value

{-# NOINLINE oneDirectUse #-}
oneDirectUse :: Uses
oneDirectUse =
  Uses 1 0

combineUses :: Uses -> Uses -> Uses
combineUses (Uses a b) (Uses x y) =
  Uses (a + x) (b + y)

delayUse :: Uses -> Uses
delayUse (Uses direct delayed) =
  Uses 0 (direct + delayed)

-- MANAGING BINDINGS

verifyBindings ::
  Warning.Context ->
  Pattern.Bindings ->
  Result FreeLocals [Warning.Warning] value ->
  Result info [Warning.Warning] (value, FreeLocals)
verifyBindings context bindings (Result.Result k) =
  Result.Result $ \info warnings bad good ->
    k
      Map.empty
      warnings
      ( \_ warnings1 err ->
          bad info warnings1 err
      )
      ( \freeLocals warnings1 value ->
          let outerFreeLocals =
                Map.difference freeLocals bindings

              warnings2 =
                -- NOTE: Uses Map.size for O(1) lookup. This means there is
                -- no dictionary allocation unless a problem is detected.
                if Map.size bindings + Map.size outerFreeLocals == Map.size freeLocals
                  then warnings1
                  else
                    Map.foldlWithKey (addUnusedWarning context) warnings1 $
                      Map.difference bindings freeLocals
           in good info warnings2 (value, outerFreeLocals)
      )

addUnusedWarning :: Warning.Context -> [Warning.Warning] -> Name.Name -> Ann.Region -> [Warning.Warning]
addUnusedWarning context warnings name region =
  Warning.UnusedVariable region context name : warnings

directUsage :: Result () w (expr, FreeLocals) -> Result FreeLocals w expr
directUsage (Result.Result k) =
  Result.Result $ \freeLocals warnings bad good ->
    k
      ()
      warnings
      (\() ws es -> bad freeLocals ws es)
      ( \() ws (value, newFreeLocals) ->
          good (Map.unionWith combineUses freeLocals newFreeLocals) ws value
      )

delayedUsage :: Result () w (expr, FreeLocals) -> Result FreeLocals w expr
delayedUsage (Result.Result k) =
  Result.Result $ \freeLocals warnings bad good ->
    k
      ()
      warnings
      (\() ws es -> bad freeLocals ws es)
      ( \() ws (value, newFreeLocals) ->
          let delayedLocals = Map.map delayUse newFreeLocals
           in good (Map.unionWith combineUses freeLocals delayedLocals) ws value
      )

-- FIND VARIABLE

findVar :: Ann.Region -> Env.Env -> Name.Name -> Result FreeLocals w Can.Expr_
findVar region (Env.Env localHome vs _ _ _ qvs _ _) name =
  maybe
    (Result.throw (Error.NotFoundVar region Nothing name (toPossibleNames vs qvs)))
    (resolveVar region localHome name)
    (Map.lookup name vs)

resolveVar :: Ann.Region -> ModuleName.Canonical -> Name.Name -> Env.Var -> Result FreeLocals w Can.Expr_
resolveVar _ _ name (Env.Local _) = logVar name (Can.VarLocal name)
resolveVar _ localHome name (Env.TopLevel _) = logVar name (Can.VarTopLevel localHome name)
resolveVar _ localHome name (Env.Foreign home annotation)
  | home == ModuleName.debug = Result.ok (Can.VarDebug localHome name annotation)
  | otherwise = Result.ok (Can.VarForeign home name annotation)
resolveVar region _ name (Env.Foreigns h hs) =
  Result.throw (Error.AmbiguousVar region Nothing name h hs)

findVarQual :: Ann.Region -> Env.Env -> Name.Name -> Name.Name -> Result FreeLocals w Can.Expr_
findVarQual region (Env.Env localHome vs _ _ _ qvs _ _) prefix name =
  maybe
    (findKernelOrFail region localHome vs qvs prefix name)
    (resolveQualified region localHome vs qvs prefix name)
    (Map.lookup prefix qvs)

resolveQualified :: Ann.Region -> ModuleName.Canonical -> Map.Map Name.Name Env.Var -> Env.Qualified Can.Annotation -> Name.Name -> Name.Name -> Map.Map Name.Name (Env.Info Can.Annotation) -> Result FreeLocals w Can.Expr_
resolveQualified region localHome vs qvs prefix name qualified =
  maybe
    (Result.throw (Error.NotFoundVar region (Just prefix) name (toPossibleNames vs qvs)))
    (resolveQualifiedInfo region localHome prefix name)
    (Map.lookup name qualified)

resolveQualifiedInfo :: Ann.Region -> ModuleName.Canonical -> Name.Name -> Name.Name -> Env.Info Can.Annotation -> Result FreeLocals w Can.Expr_
resolveQualifiedInfo _ localHome _ name (Env.Specific home annotation)
  | home == ModuleName.debug = Result.ok (Can.VarDebug localHome name annotation)
  | otherwise = Result.ok (Can.VarForeign home name annotation)
resolveQualifiedInfo region _ prefix name (Env.Ambiguous h hs) =
  Result.throw (Error.AmbiguousVar region (Just prefix) name h hs)

findKernelOrFail :: Ann.Region -> ModuleName.Canonical -> Map.Map Name.Name Env.Var -> Env.Qualified Can.Annotation -> Name.Name -> Name.Name -> Result FreeLocals w Can.Expr_
findKernelOrFail region localHome vs qvs prefix name
  | Name.isKernel prefix && Pkg.isKernel (ModuleName._package localHome) =
      Result.ok (Can.VarKernel (Name.getKernel prefix) name)
  | otherwise =
      Result.throw (Error.NotFoundVar region (Just prefix) name (toPossibleNames vs qvs))

toPossibleNames :: Map.Map Name.Name Env.Var -> Env.Qualified Can.Annotation -> Error.PossibleNames
toPossibleNames exposed qualified =
  Error.PossibleNames (Map.keysSet exposed) (Map.map Map.keysSet qualified)

-- FIND CTOR

toVarCtor :: Name.Name -> Env.Ctor -> Can.Expr_
toVarCtor name ctor =
  case ctor of
    Env.Ctor home typeName (Can.Union vars _ _ _ opts) index args ->
      let freeVars = Map.fromList (map (\v -> (v, ())) vars)
          result = Can.TType home typeName (map Can.TVar vars)
          tipe = foldr Can.TLambda result args
       in Can.VarCtor opts home name index (Can.Forall freeVars tipe)
    Env.RecordCtor home vars tipe ->
      let freeVars = Map.fromList (map (\v -> (v, ())) vars)
       in Can.VarCtor Can.Normal home name Index.first (Can.Forall freeVars tipe)
