-- | Binary operator constraint generation.
--
-- This module handles type constraint generation for binary operators,
-- dispatching between native arithmetic operators (which receive specialized
-- number-constrained type checking) and user-defined operators (which use
-- general function type constraints).
--
-- Native arithmetic operators constrain both operands and the result to
-- the polymorphic @number@ type (Int or Float). User-defined operators
-- use the operator's annotation for standard function application constraints.
module Type.Constrain.Expression.Operator
  ( constrainBinopOp,
    constrainNativeArith,
    constrainUserDefined,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import Reporting.Annotation (Region)
import Reporting.Error.Type (Category (..), Context (..), Expected (..), MaybeName (..))
import qualified Reporting.Error.Type as TypeError
import Type.Type as Type hiding (Descriptor (..))

-- | Constrain function type, passed in to avoid circular module dependencies.
type Constrain = Can.Expr -> Expected Type -> IO Constraint

-- | Generate type constraints for a binary operator.
--
-- Dispatches constraint generation based on operator classification. Native
-- arithmetic operators receive specialized number-constrained type checking,
-- while user-defined operators use general function type constraints.
constrainBinopOp :: Constrain -> Region -> Can.BinopKind -> Can.Annotation -> Can.Expr -> Can.Expr -> Expected Type -> IO Constraint
constrainBinopOp doConstrain region kind annotation leftExpr rightExpr expected =
  case kind of
    Can.NativeArith op ->
      constrainNativeArith doConstrain region op leftExpr rightExpr expected
    Can.UserDefined op _ _ ->
      constrainUserDefined doConstrain region op annotation leftExpr rightExpr expected

-- | Constrain native arithmetic operator.
--
-- Generates specialized type constraints for native arithmetic operators.
-- Both operands and the result are constrained to the @number@ type,
-- which unifies to either Int or Float during type inference.
--
-- The constraint structure ensures:
--
-- 1. Left operand is @number@ type
-- 2. Right operand is @number@ type
-- 3. Result is @number@ type
-- 4. All three unify to the same concrete number type
constrainNativeArith :: Constrain -> Region -> Can.ArithOp -> Can.Expr -> Can.Expr -> Expected Type -> IO Constraint
constrainNativeArith doConstrain region _op leftExpr rightExpr expected =
  do
    leftVar <- mkFlexNumber
    rightVar <- mkFlexNumber
    let leftType = VarN leftVar
    let rightType = VarN rightVar
    let opName = Name.fromChars "+"

    leftCon <- doConstrain leftExpr (FromContext region (OpLeft opName) leftType)
    rightCon <- doConstrain rightExpr (FromContext region (OpRight opName) rightType)

    let numberCon1 = CEqual region TypeError.Number leftType (NoExpectation leftType)
    let numberCon2 = CEqual region TypeError.Number rightType (NoExpectation rightType)
    let resultCon = CEqual region TypeError.Number leftType expected

    return $
      exists [leftVar, rightVar] $
        CAnd [leftCon, rightCon, numberCon1, numberCon2, resultCon]

-- | Constrain user-defined operator with standard function application constraints.
constrainUserDefined :: Constrain -> Region -> Name.Name -> Can.Annotation -> Can.Expr -> Can.Expr -> Expected Type -> IO Constraint
constrainUserDefined doConstrain region op annotation leftExpr rightExpr expected =
  do
    leftVar <- mkFlexVar
    rightVar <- mkFlexVar
    answerVar <- mkFlexVar
    let leftType = VarN leftVar
    let rightType = VarN rightVar
    let answerType = VarN answerVar
    let binopType = leftType ==> rightType ==> answerType

    let opCon = CForeign region op annotation (NoExpectation binopType)

    leftCon <- doConstrain leftExpr (FromContext region (OpLeft op) leftType)
    rightCon <- doConstrain rightExpr (FromContext region (OpRight op) rightType)

    return $
      exists [leftVar, rightVar, answerVar] $
        CAnd
          [ opCon,
            leftCon,
            rightCon,
            CEqual region (CallResult (OpName op)) answerType expected
          ]
