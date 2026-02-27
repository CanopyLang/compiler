
-- | Compile-time evaluation of arithmetic on constant operands.
--
-- After the existing optimizer produces 'ArithBinop' nodes, this pass
-- folds them when both operands are integer literals. It also applies
-- algebraic identity and absorption rules when one operand is a known
-- constant.
--
-- Float folding is intentionally omitted: 'Canopy.Float' is a UTF-8
-- byte representation, not a Haskell 'Double', so safe round-tripping
-- would require parsing and re-encoding with many edge cases.
--
-- @since 0.19.2
module Optimize.ConstantFold
  ( foldArith,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt

-- | Attempt to fold an arithmetic operation on optimized expressions.
--
-- Returns the folded result when both operands are integer literals,
-- applies algebraic identity\/absorption rules when one operand is a
-- known constant, or falls back to 'Opt.ArithBinop' when no folding
-- is possible.
--
-- Division by zero is never folded so that the runtime semantics
-- (Infinity, -Infinity, NaN) are preserved exactly.
--
-- ==== Examples
--
-- >>> foldArith Can.Add (Opt.Int 1) (Opt.Int 2)
-- Int 3
--
-- >>> foldArith Can.Mul (Opt.VarLocal "x") (Opt.Int 0)
-- Int 0
--
-- >>> foldArith Can.Add (Opt.VarLocal "x") (Opt.Int 0)
-- VarLocal "x"
--
-- @since 0.19.2
foldArith :: Can.ArithOp -> Opt.Expr -> Opt.Expr -> Opt.Expr
foldArith op left right =
  case (op, left, right) of
    -- Integer constant folding (both operands are literals)
    (Can.Add, Opt.Int a, Opt.Int b) -> Opt.Int (a + b)
    (Can.Sub, Opt.Int a, Opt.Int b) -> Opt.Int (a - b)
    (Can.Mul, Opt.Int a, Opt.Int b) -> Opt.Int (a * b)
    (Can.Div, Opt.Int _, Opt.Int 0) -> Opt.ArithBinop op left right
    (Can.Div, Opt.Int a, Opt.Int b) -> Opt.Int (div a b)
    -- Identity and absorption rules
    _ -> foldIdentity op left right

-- | Apply algebraic identity and absorption rules.
--
-- Identity rules collapse operations with identity elements:
--
-- * @x + 0 = 0 + x = x@
-- * @x - 0 = x@
-- * @x * 1 = 1 * x = x@
--
-- Absorption rules collapse operations with absorbing elements:
--
-- * @x * 0 = 0 * x = 0@
--
-- @since 0.19.2
foldIdentity :: Can.ArithOp -> Opt.Expr -> Opt.Expr -> Opt.Expr
foldIdentity op left right =
  case (op, left, right) of
    -- Additive identity: x + 0 = x, 0 + x = x
    (Can.Add, _, Opt.Int 0) -> left
    (Can.Add, Opt.Int 0, _) -> right
    -- Subtractive identity: x - 0 = x
    (Can.Sub, _, Opt.Int 0) -> left
    -- Multiplicative identity: x * 1 = x, 1 * x = x
    (Can.Mul, _, Opt.Int 1) -> left
    (Can.Mul, Opt.Int 1, _) -> right
    -- Multiplicative absorption: x * 0 = 0, 0 * x = 0
    (Can.Mul, _, Opt.Int 0) -> Opt.Int 0
    (Can.Mul, Opt.Int 0, _) -> Opt.Int 0
    -- No rule applies
    _ -> Opt.ArithBinop op left right
