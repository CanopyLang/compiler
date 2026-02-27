-- | AST.Canonical.Expr - Expression types for the Canonical AST
--
-- This module provides focused access to expression-related types from the
-- Canonical AST. It re-exports the expression types defined in
-- "AST.Canonical.Types" for modules that only need expression constructs.
--
-- For the complete Canonical AST with all types and serialization instances,
-- import "AST.Canonical" instead.
--
-- == Exported Types
--
-- * 'Expr' - Located expression (type alias for 'Ann.Located' 'Expr_')
-- * 'Expr_' - Expression constructors including variables, literals, and operations
-- * 'CaseBranch' - Pattern match branch in case expressions
-- * 'FieldUpdate' - Record field update with region tracking
-- * 'CtorOpts' - Constructor optimization hints for code generation
-- * 'ArithOp' - Native arithmetic operator classification
-- * 'BinopKind' - Binary operator kind (native vs user-defined)
--
-- @since 0.19.1
module AST.Canonical.Expr
  ( Expr,
    Expr_ (..),
    CaseBranch (..),
    FieldUpdate (..),
    CtorOpts (..),
    ArithOp (..),
    BinopKind (..),
  )
where

import AST.Canonical.Types
  ( ArithOp (..),
    BinopKind (..),
    CaseBranch (..),
    CtorOpts (..),
    Expr,
    Expr_ (..),
    FieldUpdate (..),
  )
