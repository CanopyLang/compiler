{-# LANGUAGE TemplateHaskell #-}

-- | AST.Source - Source AST representation for parsed Canopy code
--
-- This module defines the Abstract Syntax Tree (AST) for Canopy source code
-- after initial parsing but before canonicalization. The Source AST preserves
-- the original structure from parsing, including source location information,
-- and serves as the input to the canonicalization phase.
--
-- The Source AST represents code exactly as written by the user, with qualified
-- names unresolved and imports not yet processed. This makes it suitable for
-- error reporting with precise source locations and initial syntax validation.
--
-- == Key Features
--
-- * **Complete Source Representation** - All Canopy language constructs
-- * **Location Preservation** - Every node carries source position information
-- * **Import Structure** - Raw import declarations before resolution
-- * **Documentation Support** - Embedded documentation comments
-- * **Pattern Matching** - Full pattern syntax including guards
-- * **Type Annotations** - Optional type signatures as written
--
-- == Architecture
--
-- The AST is structured around core language constructs:
--
-- * 'Expr' - All expression forms (variables, calls, literals, etc.)
-- * 'Pattern' - Pattern matching constructs for function parameters and case expressions
-- * 'Type' - Type annotations and signatures
-- * 'Module' - Top-level module structure with declarations
-- * 'Def' - Function and value definitions
--
-- Each major construct is paired with location information via 'Ann.Located'
-- to enable precise error reporting and source map generation.
--
-- == Usage Examples
--
-- === Basic Expression Parsing
--
-- @
-- -- Simple variable reference
-- let varExpr = Var LowVar (Name.fromChars "userName")
-- 
-- -- Function call with arguments  
-- let callExpr = Call funcExpr [arg1, arg2]
-- 
-- -- Lambda expression
-- let lambdaExpr = Lambda [pattern] bodyExpr
-- @
--
-- === Pattern Construction
--
-- @
-- -- Variable pattern
-- let varPattern = PVar (Name.fromChars "x")
-- 
-- -- Constructor pattern with arguments
-- let ctorPattern = PCtor region ctorName [subPatterns]
-- 
-- -- Record pattern
-- let recordPattern = PRecord [field1, field2]
-- @
--
-- === Module Structure
--
-- @
-- -- Complete module with all components
-- let sourceModule = Module
--   { _name = Just moduleName
--   , _exports = exposingClause  
--   , _docs = documentation
--   , _imports = importList
--   , _values = valueDefs
--   , _unions = typeDefs
--   , _aliases = typeAliases
--   , _binops = infixDefs
--   , _effects = effectsDecl
--   }
-- @
--
-- == Error Handling
--
-- The Source AST preserves enough information for comprehensive error reporting:
--
-- * Source regions for precise error location
-- * Original syntax for helpful error messages
-- * Context information for suggestions
--
-- All parsing errors should reference specific AST nodes to provide users
-- with actionable feedback about syntax issues.
--
-- == Performance Characteristics
--
-- * **Memory Usage**: Linear in source code size with location overhead
-- * **Construction**: O(n) where n is number of AST nodes
-- * **Traversal**: Standard tree traversal patterns apply
-- * **Serialization**: Not typically serialized (canonicalized form is cached)
--
-- == Thread Safety
--
-- All AST types are immutable and thread-safe. Multiple threads can safely
-- traverse and analyze Source AST structures concurrently.
--
-- @since 0.19.1
module AST.Source
  ( Expr,
    Expr_ (..),
    VarType (..),
    Def (..),
    Pattern,
    Pattern_ (..),
    Type,
    Type_ (..),
    Module (..),
    getName,
    getImportName,
    Import (..),
    ForeignImport (..),
    Value (..),
    Union (..),
    Alias (..),
    Infix (..),
    Port (..),
    Effects (..),
    Manager (..),
    Docs (..),
    Comment (..),
    Exposing (..),
    Exposed (..),
    Privacy (..),
  )
where

import qualified AST.Utils.Binop as Binop
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Float as EF
import qualified Canopy.String as ES
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann

-- FFI Support
import qualified Foreign.FFI as FFI

-- EXPRESSIONS

-- | Source expression with location information.
--
-- Represents any expression in Canopy source code, wrapped with precise
-- source location for error reporting. This is the primary expression
-- type used throughout parsing and early compilation phases.
--
-- @since 0.19.1
type Expr = Ann.Located Expr_

-- | Core expression forms in Canopy source code.
--
-- Represents all possible expression constructs that can appear in Canopy
-- source, preserving the original syntax structure. Each constructor
-- corresponds to a specific language feature with its associated data.
--
-- Expression evaluation follows standard functional programming semantics
-- with call-by-value evaluation for most constructs.
--
-- @since 0.19.1
data Expr_
  = -- | Character literal.
    --
    -- Represents single character literals like @'a'@, @'\n'@, @'\u{0041}'@.
    -- Character literals are stored as escaped string representation.
    Chr ES.String
  | -- | String literal.
    --
    -- Represents string literals like @"hello"@, @"multi\nline"@.
    -- Strings are stored with escape sequences preserved from source.
    Str ES.String
  | -- | Integer literal.
    --
    -- Represents integer literals like @42@, @-17@, @0xFF@.
    -- All integer literals are parsed as standard Haskell Int values.
    Int Int
  | -- | Floating point literal.
    --
    -- Represents float literals like @3.14@, @-2.5e10@, @1.0@.
    -- Stored using Canopy's specialized float representation.
    Float EF.Float
  | -- | Variable reference.
    --
    -- Represents unqualified variable names like @userName@, @count@.
    -- VarType distinguishes between lowercase and uppercase variables.
    Var VarType Name
  | -- | Qualified variable reference.
    --
    -- Represents qualified names like @List.map@, @String.length@.
    -- First Name is module, second Name is the variable name.
    VarQual VarType Name Name
  | -- | List literal.
    --
    -- Represents list literals like @[1, 2, 3]@, @[]@, @[x, y]@.
    -- Contains the list of element expressions.
    List [Expr]
  | -- | Operator reference.
    --
    -- Represents operator references like @(+)@, @(::)@, @(|>)@.
    -- Used when operators appear in operator sections.
    Op Name
  | -- | Unary negation.
    --
    -- Represents negation expressions like @-x@, @-(a + b)@.
    -- Applies numeric negation to the sub-expression.
    Negate Expr
  | -- | Binary operator chain.
    --
    -- Represents chains of binary operators like @a + b * c@.
    -- Each tuple contains (left expression, operator). Final expression is the rightmost operand.
    -- Precedence resolution happens in later compilation phases.
    Binops [(Expr, Ann.Located Name)] Expr
  | -- | Lambda expression.
    --
    -- Represents lambda expressions like @\\x -> x + 1@, @\\x y -> x * y@.
    -- Contains parameter patterns and body expression.
    Lambda [Pattern] Expr
  | -- | Function call.
    --
    -- Represents function calls like @func arg1 arg2@, @f()@.
    -- First expression is the function, list contains arguments.
    Call Expr [Expr]
  | -- | Conditional expression.
    --
    -- Represents if-then-else chains like @if cond then a else b@.
    -- Each tuple is (condition, then-branch). Final expression is else-branch.
    -- Supports if-then-elif-else chains with multiple conditions.
    If [(Expr, Expr)] Expr
  | -- | Let expression.
    --
    -- Represents let-in expressions with local definitions.
    -- Contains list of local definitions and body expression.
    Let [Ann.Located Def] Expr
  | -- | Case expression.
    --
    -- Represents pattern matching like @case x of Just y -> y; Nothing -> 0@.
    -- Each tuple contains (pattern, result expression).
    Case Expr [(Pattern, Expr)]
  | -- | Record field accessor.
    --
    -- Represents field access function like @.name@, @.age@.
    -- Creates a function that extracts the named field from records.
    Accessor Name
  | -- | Record field access.
    --
    -- Represents field access like @user.name@, @config.timeout@.
    -- Extracts named field from the record expression.
    Access Expr (Ann.Located Name)
  | -- | Record update.
    --
    -- Represents record updates like @{ user | name = "John" }@.
    -- Updates specified fields while preserving others.
    Update (Ann.Located Name) [(Ann.Located Name, Expr)]
  | -- | Record literal.
    --
    -- Represents record literals like @{ name = "John", age = 25 }@.
    -- Contains field name and value expression pairs.
    Record [(Ann.Located Name, Expr)]
  | -- | Unit literal.
    --
    -- Represents the unit value @()@.
    -- Used for expressions that don't return meaningful values.
    Unit
  | -- | Tuple literal.
    --
    -- Represents tuple literals like @(a, b)@, @(x, y, z)@.
    -- Contains first element, second element, and optional additional elements.
    Tuple Expr Expr [Expr]
  | -- | GLSL shader literal.
    --
    -- Represents embedded GLSL shader code with type information.
    -- Used for WebGL shader integration in Canopy applications.
    Shader Shader.Source Shader.Types
  deriving (Show)

-- | Variable type classification for parsing.
--
-- Distinguishes between lowercase and uppercase variable references
-- during parsing to enable proper syntax validation and error reporting.
--
-- @since 0.19.1
data VarType 
  = -- | Lowercase variable like @userName@, @count@, @processData@.
    --
    -- Represents typical variable and function names that start with
    -- lowercase letters. These refer to values and functions.
    LowVar 
  | -- | Uppercase variable like @Maybe@, @List@, @CustomType@.
    --
    -- Represents type constructors and module names that start with
    -- uppercase letters. These refer to types and constructors.
    CapVar
  deriving (Show)

-- DEFINITIONS

-- | Top-level definition in source code.
--
-- Represents function definitions and destructuring assignments at the
-- top level of modules. Definitions can include optional type annotations
-- and support pattern matching in parameters.
--
-- @since 0.19.1
data Def
  = -- | Function or value definition.
    --
    -- Represents definitions like:
    -- @
    -- square x = x * x
    -- identity : a -> a
    -- identity x = x
    -- @
    --
    -- Contains the definition name, parameter patterns, body expression,
    -- and optional type annotation.
    Define (Ann.Located Name) [Pattern] Expr (Maybe Type)
  | -- | Destructuring definition.
    --
    -- Represents destructuring assignments like:
    -- @
    -- (x, y) = getCoordinates()
    -- {name, age} = user
    -- @
    --
    -- Binds pattern variables to values from the expression.
    Destruct Pattern Expr
  deriving (Show)

-- PATTERN

-- | Pattern with location information.
--
-- Represents patterns used in function parameters, case expressions,
-- and destructuring assignments. Location information enables precise
-- error reporting for pattern matching issues.
--
-- @since 0.19.1
type Pattern = Ann.Located Pattern_

-- | Core pattern matching constructs.
--
-- Represents all pattern forms available in Canopy for destructuring
-- values and binding variables. Patterns are used in function parameters,
-- case expressions, and let destructuring.
--
-- Pattern matching follows standard functional programming semantics
-- with exhaustiveness checking in later compilation phases.
--
-- @since 0.19.1
data Pattern_
  = -- | Wildcard pattern.
    --
    -- Represents the wildcard pattern @_@ that matches anything
    -- without binding a variable. Used when the matched value is ignored.
    PAnything
  | -- | Variable pattern.
    --
    -- Represents variable patterns like @x@, @userName@, @result@.
    -- Binds the matched value to the given variable name.
    PVar Name
  | -- | Record pattern.
    --
    -- Represents record patterns like @{name, age}@, @{x, y}@.
    -- Extracts specified fields from record values.
    PRecord [Ann.Located Name]
  | -- | Pattern alias.
    --
    -- Represents aliased patterns like @x as (Just y)@, @data as {name}@.
    -- Binds the entire matched value to alias while also matching the pattern.
    PAlias Pattern (Ann.Located Name)
  | -- | Unit pattern.
    --
    -- Represents the unit pattern @()@ that matches unit values.
    -- Used in functions that don't take meaningful arguments.
    PUnit
  | -- | Tuple pattern.
    --
    -- Represents tuple patterns like @(x, y)@, @(a, b, c)@.
    -- Matches tuple values and binds components to sub-patterns.
    PTuple Pattern Pattern [Pattern]
  | -- | Constructor pattern.
    --
    -- Represents constructor patterns like @Just x@, @Node left right@.
    -- Matches values constructed with the specified constructor.
    PCtor Ann.Region Name [Pattern]
  | -- | Qualified constructor pattern.
    --
    -- Represents qualified constructor patterns like @Maybe.Just x@.
    -- First Name is module, second Name is constructor.
    PCtorQual Ann.Region Name Name [Pattern]
  | -- | List pattern.
    --
    -- Represents list patterns like @[x, y, z]@, @[]@.
    -- Matches lists with exact length and binds elements to sub-patterns.
    PList [Pattern]
  | -- | Cons pattern.
    --
    -- Represents cons patterns like @x :: xs@, @head :: tail@.
    -- Matches non-empty lists and binds head and tail.
    PCons Pattern Pattern
  | -- | Character pattern.
    --
    -- Represents character patterns like @'a'@, @'\n'@.
    -- Matches specific character values.
    PChr ES.String
  | -- | String pattern.
    --
    -- Represents string patterns like @"hello"@, @""@.
    -- Matches specific string values.
    PStr ES.String
  | -- | Integer pattern.
    --
    -- Represents integer patterns like @42@, @0@, @-17@.
    -- Matches specific integer values.
    PInt Int
  deriving (Show)

-- TYPE

-- | Type annotation with location information.
--
-- Represents type annotations in source code with precise location
-- information for error reporting. Used in function signatures,
-- variable annotations, and type definitions.
--
-- @since 0.19.1
type Type =
  Ann.Located Type_

-- | Core type constructs in Canopy.
--
-- Represents all type forms that can appear in Canopy source code
-- type annotations. These correspond directly to the type syntax
-- as written by the user before type inference and canonicalization.
--
-- @since 0.19.1
data Type_
  = -- | Function type.
    --
    -- Represents function types like @Int -> String@, @a -> b -> c@.
    -- Function types are right-associative: @a -> b -> c@ means @a -> (b -> c)@.
    TLambda Type Type
  | -- | Type variable.
    --
    -- Represents type variables like @a@, @comparable@, @number@.
    -- Used in polymorphic type signatures.
    TVar Name
  | -- | Type constructor application.
    --
    -- Represents type applications like @List Int@, @Maybe String@.
    -- Contains source region, constructor name, and type arguments.
    TType Ann.Region Name [Type]
  | -- | Qualified type constructor.
    --
    -- Represents qualified type applications like @Dict.Dict String Int@.
    -- First Name is module, second Name is type constructor.
    TTypeQual Ann.Region Name Name [Type]
  | -- | Record type.
    --
    -- Represents record types like @{ name : String, age : Int }@.
    -- Optional extension variable enables row polymorphism.
    TRecord [(Ann.Located Name, Type)] (Maybe (Ann.Located Name))
  | -- | Unit type.
    --
    -- Represents the unit type @()@.
    -- Used for functions that don't return meaningful values.
    TUnit
  | -- | Tuple type.
    --
    -- Represents tuple types like @(Int, String)@, @(a, b, c)@.
    -- Contains first type, second type, and optional additional types.
    TTuple Type Type [Type]
  deriving (Show)

-- MODULE

-- | Complete source module representation.
--
-- Represents a complete Canopy source file with all its declarations,
-- imports, exports, and metadata. This is the top-level AST node
-- produced by parsing a single .canopy source file.
--
-- The module structure preserves all information needed for:
-- - Dependency resolution and import processing
-- - Export validation and interface generation  
-- - Documentation extraction and processing
-- - Error reporting with source context
--
-- @since 0.19.1
data Module = Module
  { _name :: Maybe (Ann.Located Name),
    _exports :: Ann.Located Exposing,
    _docs :: Docs,
    _imports :: [Import],
    _foreignImports :: [ForeignImport],
    _values :: [Ann.Located Value],
    _unions :: [Ann.Located Union],
    _aliases :: [Ann.Located Alias],
    _binops :: [Ann.Located Infix],
    _effects :: Effects
  }
  deriving (Show)

-- | Extract the module name from a source module.
--
-- Returns the explicit module name if declared, otherwise defaults to 'Main'.
-- This handles both named modules (@module MyApp exposing (..)@) and
-- anonymous modules (files without module declarations).
--
-- ==== Examples
--
-- >>> getName moduleWithName
-- Name "MyApp"
--
-- >>> getName anonymousModule  
-- Name "Main"
--
-- @since 0.19.1
getName :: Module -> Name
getName (Module maybeName _ _ _ _ _ _ _ _ _) =
  case maybeName of
    Just (Ann.At _ moduleName) ->
      moduleName
    Nothing ->
      Name._Main

-- | Extract the module name from an import declaration.
--
-- Returns the name of the module being imported from an import statement.
-- This is the qualified name used to reference the imported module.
--
-- ==== Examples
--
-- >>> getImportName (Import "List" Nothing Open)
-- Name "List"
--
-- >>> getImportName (Import "Dict" (Just "D") (Explicit [...]))
-- Name "Dict"
--
-- @since 0.19.1
getImportName :: Import -> Name
getImportName (Import (Ann.At _ impName) _ _ _) =
  impName

-- | Import declaration in source code.
--
-- Represents import statements like:
-- @
-- import List
-- import Dict as D
-- import Set exposing (Set, empty, insert)
-- @
--
-- Imports specify module dependencies and control name resolution
-- in the importing module.
--
-- @since 0.19.1
data Import = Import
  { _importName :: Ann.Located Name,
    _importAlias :: Maybe Name,
    _importExposing :: Exposing,
    _importLazy :: !Bool
  }
  deriving (Show)

-- | Foreign import declaration for FFI support.
--
-- Represents foreign import statements that allow Canopy code to interface
-- with external code (currently JavaScript) in a type-safe manner.
--
-- Example:
-- @
-- foreign import javascript "./api.js" as API
-- @
--
-- @since 0.19.1
data ForeignImport = ForeignImport
  { _foreignTarget :: FFI.FFITarget,
    _foreignAlias :: Ann.Located Name,
    _foreignLocation :: Ann.Region
  }
  deriving (Show)

-- | Value definition in source code.
--
-- Represents top-level value and function definitions with optional
-- type annotations. Similar to 'Def' but used specifically in the
-- module's values list.
--
-- @since 0.19.1
data Value = Value (Ann.Located Name) [Pattern] Expr (Maybe Type)
  deriving (Show)

-- | Union type definition in source code.
--
-- Represents custom type definitions like:
-- @
-- type Maybe a = Nothing | Just a
-- type Color = Red | Green | Blue
-- @
--
-- Contains type name, type parameters, and constructor definitions.
--
-- @since 0.19.1
data Union = Union (Ann.Located Name) [Ann.Located Name] [(Ann.Located Name, [Type])]
  deriving (Show)

-- | Type alias definition in source code.
--
-- Represents type alias definitions like:
-- @
-- type alias UserId = Int
-- type alias Point = { x : Float, y : Float }
-- @
--
-- Contains alias name, type parameters, and target type.
--
-- @since 0.19.1
data Alias = Alias (Ann.Located Name) [Ann.Located Name] Type
  deriving (Show)

-- | Infix operator definition in source code.
--
-- Represents infix operator declarations like:
-- @
-- infix right 5 (++)
-- infix left  9 (<<)
-- @
--
-- Defines operator precedence and associativity for custom operators.
--
-- @since 0.19.1
data Infix = Infix Name Binop.Associativity Binop.Precedence Name
  deriving (Show)

-- | Port definition for JavaScript interop.
--
-- Represents port definitions for communicating with JavaScript:
-- @
-- port sendData : String -> Cmd msg
-- port receiveData : (String -> msg) -> Sub msg
-- @
--
-- Ports enable controlled interaction with external JavaScript code.
--
-- @since 0.19.1
data Port = Port (Ann.Located Name) Type
  deriving (Show)

-- | Effect declarations for modules.
--
-- Represents the effects that a module can perform, such as commands,
-- subscriptions, or managed effects. Controls what side effects are
-- available to the module.
--
-- @since 0.19.1
data Effects
  = NoEffects
  | Ports [Port]
  | Manager Ann.Region Manager
  | FFI [ForeignImport]
  deriving (Show)

-- | Effect manager specification.
--
-- Represents effect manager declarations that define how custom effects
-- are implemented and managed by the Canopy runtime.
--
-- @since 0.19.1
data Manager
  = Cmd (Ann.Located Name)
  | Sub (Ann.Located Name)
  | Fx (Ann.Located Name) (Ann.Located Name)
  deriving (Show)

-- | Documentation in source code.
--
-- Represents documentation comments and module documentation.
-- Preserves doc comments for documentation generation and IDE support.
--
-- @since 0.19.1
data Docs
  = NoDocs Ann.Region
  | YesDocs Comment [(Name, Comment)]
  deriving (Show)

-- | Documentation comment.
--
-- Represents individual documentation comments in source code.
-- Comments are preserved as parsed snippets for documentation tools.
--
-- @since 0.19.1
newtype Comment
  = Comment Parse.Snippet
  deriving (Show)

-- EXPOSING

-- | Export specification for modules.
--
-- Represents what a module exposes to other modules:
-- @
-- exposing (..)           -- expose everything
-- exposing (func, Type)   -- expose specific items
-- @
--
-- Controls the public API of modules.
--
-- @since 0.19.1
data Exposing
  = Open
  | Explicit [Exposed]
  deriving (Show)

-- | Individual exported item.
--
-- Represents specific items in an exposing list, such as functions,
-- types, or operators. Each item may have different exposure rules.
--
-- @since 0.19.1
data Exposed
  = Lower (Ann.Located Name)
  | Upper (Ann.Located Name) Privacy
  | Operator Ann.Region Name
  deriving (Show)

-- | Privacy specification for exposed types.
--
-- Represents whether type constructors are publicly exposed or kept private:
-- @
-- Type(..)    -- constructors exposed (Public)
-- Type        -- constructors hidden (Private)
-- @
--
-- @since 0.19.1
data Privacy
  = Public Ann.Region
  | Private
  deriving (Show)

