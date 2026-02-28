{-# LANGUAGE OverloadedStrings #-}

-- | Type query support for the REPL.
--
-- Provides functionality for the @:type@ and @:browse@ commands,
-- extracting type information from compiled artifacts and dependency
-- interfaces.
--
-- == :type
--
-- The @:type@ command compiles an expression in the current REPL context
-- and extracts its type from the resulting interface, without executing
-- the generated JavaScript.
--
-- == :browse
--
-- The @:browse@ command lists exported values and their types from
-- a dependency module's interface.
--
-- @since 0.19.2
module Repl.TypeQuery
  ( -- * Type Display
    formatTypeOf,

    -- * Module Browsing
    formatBrowseModule,
    formatBrowseState,
  )
where

import qualified AST.Canonical as Can
import qualified Build
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer

-- TYPE DISPLAY

-- | Format the type of a specific name from a module's interface.
--
-- Looks up the name in the interface's values map and renders
-- its type annotation as a human-readable string.
--
-- @since 0.19.2
formatTypeOf :: Name.Name -> Interface.Interface -> Maybe String
formatTypeOf name iface =
  fmap formatAnnotation (Map.lookup name (Interface._values iface))

-- | Format a canonical annotation as a type string.
--
-- @since 0.19.2
formatAnnotation :: Can.Annotation -> String
formatAnnotation annotation =
  Doc.toLine (Type.toDoc Localizer.empty RT.None (Extract.fromAnnotation annotation))

-- MODULE BROWSING

-- | Format the exports of a dependency module for the @:browse@ command.
--
-- Produces a list of lines showing each exported value, type alias,
-- custom type, and binary operator with its type signature.
--
-- @since 0.19.2
formatBrowseModule :: ModuleName.Raw -> Interface.Interface -> String
formatBrowseModule modName iface =
  unlines (header : "" : valueLines ++ aliasLines ++ unionLines ++ binopLines)
  where
    header = "-- " ++ Name.toChars modName

    valueLines = map formatValueExport (Map.toAscList (Interface._values iface))
    aliasLines = concatMap formatAliasExport (Map.toAscList (Interface._aliases iface))
    unionLines = concatMap formatUnionExport (Map.toAscList (Interface._unions iface))
    binopLines = map formatBinopExport (Map.toAscList (Interface._binops iface))

-- | Format a value export as @name : Type@.
formatValueExport :: (Name.Name, Can.Annotation) -> String
formatValueExport (name, annotation) =
  Name.toChars name ++ " : " ++ formatAnnotation annotation

-- | Format a type alias export.
formatAliasExport :: (Name.Name, Interface.Alias) -> [String]
formatAliasExport (name, iAlias) =
  maybe [] (formatPublicAlias name) (Interface.toPublicAlias iAlias)

-- | Format a public alias as @type alias Name vars = Type@.
formatPublicAlias :: Name.Name -> Can.Alias -> [String]
formatPublicAlias name (Can.Alias tvars tipe) =
  [aliasDecl]
  where
    tvarsStr = concatMap (\v -> " " ++ Name.toChars v) tvars
    typeStr = Doc.toLine (Type.toDoc Localizer.empty RT.None (Extract.fromType tipe))
    aliasDecl = "type alias " ++ Name.toChars name ++ tvarsStr ++ " = " ++ typeStr

-- | Format a union type export.
formatUnionExport :: (Name.Name, Interface.Union) -> [String]
formatUnionExport (name, iUnion) =
  maybe [] (formatPublicUnion name) (toPublicUnion iUnion)

-- | Extract a public union if it is not private.
toPublicUnion :: Interface.Union -> Maybe Can.Union
toPublicUnion (Interface.OpenUnion u) = Just u
toPublicUnion (Interface.ClosedUnion u) = Just u
toPublicUnion (Interface.PrivateUnion _) = Nothing

-- | Format a public union as @type Name vars = Ctor1 | Ctor2@.
formatPublicUnion :: Name.Name -> Can.Union -> [String]
formatPublicUnion name (Can.Union tvars ctors _ _) =
  [typeDecl]
  where
    tvarsStr = concatMap (\v -> " " ++ Name.toChars v) tvars
    ctorsStr = formatCtors ctors
    typeDecl = "type " ++ Name.toChars name ++ tvarsStr ++ ctorsStr

-- | Format union constructors.
formatCtors :: [Can.Ctor] -> String
formatCtors [] = ""
formatCtors (first : rest) =
  " = " ++ formatCtor first ++ concatMap (\c -> " | " ++ formatCtor c) rest

-- | Format a single constructor.
formatCtor :: Can.Ctor -> String
formatCtor (Can.Ctor ctorName _ _ args) =
  Name.toChars ctorName ++ concatMap formatCtorArg args

-- | Format a constructor argument.
formatCtorArg :: Can.Type -> String
formatCtorArg tipe =
  " " ++ Doc.toLine (Type.toDoc Localizer.empty RT.App (Extract.fromType tipe))

-- | Format a binop export as @(op) : Type@.
formatBinopExport :: (Name.Name, Interface.Binop) -> String
formatBinopExport (name, Interface.Binop _ annotation _ _) =
  "(" ++ Name.toChars name ++ ") : " ++ formatAnnotation annotation

-- STATE BROWSING

-- | Format the current REPL state for @:browse@ with no module argument.
--
-- Lists all imports, type definitions, and value declarations
-- currently in scope.
--
-- @since 0.19.2
formatBrowseState :: Build.Artifacts -> String
formatBrowseState artifacts =
  unlines (header : "" : depLines)
  where
    header = "-- Available modules"
    deps = Build._artifactsDeps artifacts
    depLines = concatMap formatDepEntry (Map.toAscList deps)

-- | Format a dependency entry showing the module name.
formatDepEntry :: (ModuleName.Canonical, Interface.DependencyInterface) -> [String]
formatDepEntry (ModuleName.Canonical _pkg name, Interface.Public _iface) =
  [Name.toChars name]
formatDepEntry (ModuleName.Canonical _pkg name, Interface.Private _ _ _) =
  [Name.toChars name ++ " (private)"]
