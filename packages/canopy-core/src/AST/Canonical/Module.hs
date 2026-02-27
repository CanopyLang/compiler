-- | AST.Canonical.Module - Module structure types for the Canonical AST
--
-- This module provides focused access to module-related types from the
-- Canonical AST. It re-exports the module structure types defined in
-- "AST.Canonical.Types" for modules that only need module-level constructs.
--
-- For the complete Canonical AST with all types and serialization instances,
-- import "AST.Canonical" instead.
--
-- == Exported Types
--
-- * 'Module' - Complete canonical module with exports, declarations, and effects
-- * 'Alias' - Type alias definition with type variables and body
-- * 'Binop' - Binary operator definition with associativity and precedence
-- * 'Union' - Union type with constructors, cached metadata, and optimization hints
-- * 'Ctor' - Individual constructor with name, index, arity, and argument types
-- * 'Exports' - Module export specification (everything or selective)
-- * 'Export' - Individual export item classification
-- * 'Effects' - Module effect declarations (ports, managers, FFI)
-- * 'Port' - Port definition for JavaScript interop
-- * 'Manager' - Effect manager classification (Cmd, Sub, Fx)
--
-- @since 0.19.1
module AST.Canonical.Module
  ( Module (..),
    Alias (..),
    Binop (..),
    Union (..),
    Ctor (..),
    Exports (..),
    Export (..),
    Effects (..),
    Port (..),
    Manager (Cmd, SubManager, Fx),
  )
where

import AST.Canonical.Types
  ( Alias (..),
    Binop (..),
    Ctor (..),
    Effects (..),
    Export (..),
    Exports (..),
    Manager (Cmd, Fx, SubManager),
    Module (..),
    Port (..),
    Union (..),
  )
