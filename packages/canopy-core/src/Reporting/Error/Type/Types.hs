{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

-- | Reporting.Error.Type.Types - Core type definitions for type errors
--
-- This internal module holds the type definitions that are shared across all
-- type-error sub-modules: 'Error', 'Expected', 'Context', 'SubContext',
-- 'PExpected', and 'PContext'.  By placing these in a leaf module we avoid
-- circular imports between the rendering sub-modules (Pattern, Expression,
-- Record, Render) and the parent 'Reporting.Error.Type' module.
--
-- End users should import from 'Reporting.Error.Type' which re-exports
-- everything defined here.
module Reporting.Error.Type.Types
  ( -- * Top-level error
    Error (..),

    -- * Expression expectations
    Expected (..),
    Context (..),
    SubContext (..),

    -- * Pattern expectations
    PExpected (..),
    PContext (..),

    -- * Replacement helpers
    typeReplace,
    ptypeReplace,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Data.Map as Map
import qualified Reporting.Annotation as Ann
import Reporting.Error.Type.Operators
  ( Category,
    MaybeName,
    PCategory,
  )
import qualified Type.Error as TypeErr

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | The top-level type error produced by the type solver.
data Error
  = BadExpr Ann.Region Category TypeErr.Type (Expected TypeErr.Type)
  | BadPattern Ann.Region PCategory TypeErr.Type (PExpected TypeErr.Type)
  | InfiniteType Ann.Region Name.Name TypeErr.Type
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Expression expectations
-- ---------------------------------------------------------------------------

-- | How the solver arrived at the expected type for an expression.
data Expected tipe
  = NoExpectation tipe
  | FromContext Ann.Region Context tipe
  | FromAnnotation Name.Name Int SubContext tipe

deriving instance Show a => Show (Expected a)

-- | The syntactic context that constrains an expression's type.
data Context
  = ListEntry Index.ZeroBased
  | Negate
  | OpLeft Name.Name
  | OpRight Name.Name
  | IfCondition
  | IfBranch Index.ZeroBased
  | CaseBranch Index.ZeroBased
  | CallArity MaybeName Int
  | CallArg MaybeName Index.ZeroBased
  | RecordAccess Ann.Region (Maybe Name.Name) Ann.Region Name.Name
  | RecordUpdateKeys Name.Name (Map.Map Name.Name Can.FieldUpdate)
  | RecordUpdateValue Name.Name
  | Destructure
  | Interpolation Index.ZeroBased
  deriving (Show)

-- | The sub-context within a type-annotated definition.
data SubContext
  = TypedIfBranch Index.ZeroBased
  | TypedCaseBranch Index.ZeroBased
  | TypedBody
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Pattern expectations
-- ---------------------------------------------------------------------------

-- | How the solver arrived at the expected type for a pattern.
data PExpected tipe
  = PNoExpectation tipe
  | PFromContext Ann.Region PContext tipe
  deriving (Show)

-- | The syntactic context that constrains a pattern's type.
data PContext
  = PTypedArg Name.Name Index.ZeroBased
  | PCaseMatch Index.ZeroBased
  | PCtorArg Name.Name Index.ZeroBased
  | PListEntry Index.ZeroBased
  | PTail
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Replace the type inside an 'Expected' wrapper.
typeReplace :: Expected a -> b -> Expected b
typeReplace expectation tipe =
  case expectation of
    NoExpectation _ ->
      NoExpectation tipe
    FromContext region context _ ->
      FromContext region context tipe
    FromAnnotation name arity context _ ->
      FromAnnotation name arity context tipe

-- | Replace the type inside a 'PExpected' wrapper.
ptypeReplace :: PExpected a -> b -> PExpected b
ptypeReplace expectation tipe =
  case expectation of
    PNoExpectation _ ->
      PNoExpectation tipe
    PFromContext region context _ ->
      PFromContext region context tipe
