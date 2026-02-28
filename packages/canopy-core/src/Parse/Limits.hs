-- | Parser recursion depth and repetition limits.
--
-- Defines hard limits for recursive parser constructs to prevent stack
-- overflow on malicious or accidentally-generated input files. Each
-- limit is chosen to accommodate all reasonable real-world programs
-- while providing a safety net against adversarial input.
--
-- @since 0.19.2
module Parse.Limits
  ( -- * Depth Limits
    maxFieldAccessDepth,
    maxCaseBranches,
    maxExpressionDepth,
    maxLetBindings,
    maxFunctionArgs,
  )
where

-- | Maximum depth of field access chains (a.b.c.d...).
--
-- Limits like @record.x.y.z...@ to 100 levels of chained access.
-- Real-world programs rarely exceed 10 levels.
--
-- @since 0.19.2
maxFieldAccessDepth :: Int
maxFieldAccessDepth = 100

-- | Maximum number of case branches in a single case expression.
--
-- Limits the number of pattern match branches. Real-world programs
-- rarely exceed 50 branches; 500 allows for generated code.
--
-- @since 0.19.2
maxCaseBranches :: Int
maxCaseBranches = 500

-- | Maximum nesting depth for expressions.
--
-- Limits deeply nested constructs like @if (if (if ...))@.
-- Real-world programs rarely exceed 30 levels of nesting.
--
-- @since 0.19.2
maxExpressionDepth :: Int
maxExpressionDepth = 200

-- | Maximum number of let bindings in a single let-in block.
--
-- @since 0.19.2
maxLetBindings :: Int
maxLetBindings = 200

-- | Maximum number of function arguments.
--
-- @since 0.19.2
maxFunctionArgs :: Int
maxFunctionArgs = 50
