{-# LANGUAGE OverloadedStrings #-}

-- | Output formatting and display for diff results.
--
-- This module handles the formatting and display of API difference
-- analysis results. It transforms computed diffs into user-friendly
-- documentation with proper semantic versioning classification,
-- following CLAUDE.md patterns for clear, functional design.
--
-- == Key Functions
--
-- * 'display' - Main output formatting and display function
-- * 'formatChanges' - Convert changes to formatted documentation
-- * 'buildSections' - Create formatted sections for different change types
-- * 'formatEntry' - Format individual API entry changes
--
-- == Output Structure
--
-- The formatted output includes:
--
-- * Overall magnitude classification (MAJOR/MINOR/PATCH)
-- * Sectioned changes by type (modules, values, types, etc.)
-- * Color-coded diff indicators for additions/changes/removals
-- * Detailed type signatures and documentation
--
-- == Design Philosophy
--
-- All functions are pure and focused on single responsibilities.
-- Complex formatting is decomposed into smaller, testable functions
-- that can be easily verified and maintained.
--
-- @since 0.19.1
module Diff.Output
  ( -- * Main Display
    display,

    -- * Formatting
    formatChanges,
    buildSections,

    -- * Section Building
    createModuleSections,
    createChangeSections,
    formatChangeTriples,
  )
where

import qualified Canopy.Compiler.Type as Type
import Canopy.Docs (Alias, Binop, Documentation, Union, Value)
import qualified Canopy.Docs as Docs
import qualified Canopy.Magnitude as Magnitude
import Control.Lens ((^.))
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import Deps.Diff (Changes (..), ModuleChanges (..), PackageChanges (..))
import qualified Deps.Diff as Diff
import Diff.Types (Chunk (..), chunkDetails, chunkMagnitude, chunkTitle)
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Render.Type.Localizer as Localizer

-- | Display formatted diff results.
--
-- Computes API differences, formats them for display, and outputs
-- to stdout with appropriate color coding and structure.
--
-- ==== Examples
--
-- >>> display oldDocs newDocs
-- -- Outputs formatted diff to stdout
--
-- @since 0.19.1
display :: Documentation -> Documentation -> IO ()
display oldDocs newDocs = do
  let changes = Diff.diff oldDocs newDocs
      localizer = Localizer.fromNames (Map.union oldDocs newDocs)
      formattedDoc = formatChanges localizer changes
  Help.toStdout (formattedDoc <> "\n")

-- | Format package changes into documentation.
--
-- Transforms computed package changes into structured documentation
-- with appropriate magnitude classification and sectioning.
--
-- @since 0.19.1
formatChanges :: Localizer.Localizer -> PackageChanges -> Doc.Doc
formatChanges localizer changes@(PackageChanges added changed removed) =
  if hasNoChanges added changed removed
    then "No API changes detected, so this is a" <+> Doc.green "PATCH" <+> "change."
    else createFormattedDoc localizer changes added changed removed

-- | Check if package has any changes.
hasNoChanges :: [a] -> Map.Map b c -> [d] -> Bool
hasNoChanges added changed removed =
  null added && Map.null changed && null removed

-- | Create formatted documentation for changes.
createFormattedDoc :: Localizer.Localizer -> PackageChanges -> [Name.Name] -> Map.Map Name.Name ModuleChanges -> [Name.Name] -> Doc.Doc
createFormattedDoc localizer changes added changed removed =
  Doc.vcat (createHeader changes : "" : formatSections)
  where
    sections = buildSections localizer added changed removed
    formatSections = fmap formatSection sections

-- | Create magnitude header.
createHeader :: PackageChanges -> Doc.Doc
createHeader changes =
  "This is a" <+> Doc.green magDoc <+> "change."
  where
    magDoc = Doc.fromChars (Magnitude.toChars (Diff.toMagnitude changes))

-- | Build formatted sections from changes.
--
-- Creates sections for added modules, removed modules, and changed modules
-- with appropriate magnitude classification and content.
--
-- @since 0.19.1
buildSections :: Localizer.Localizer -> [Name.Name] -> Map.Map Name.Name ModuleChanges -> [Name.Name] -> [Chunk]
buildSections localizer added changed removed =
  createModuleSections added removed <> createChangeSections localizer changed

-- | Create sections for module additions/removals.
createModuleSections :: [Name.Name] -> [Name.Name] -> [Chunk]
createModuleSections added removed =
  addedSection <> removedSection
  where
    addedSection = if null added then [] else [createAddedModuleSection added]
    removedSection = if null removed then [] else [createRemovedModuleSection removed]

-- | Create added modules section.
createAddedModuleSection :: [Name.Name] -> Chunk
createAddedModuleSection added =
  Chunk "ADDED MODULES" Magnitude.MINOR (Doc.vcat (fmap Doc.fromName added))

-- | Create removed modules section.
createRemovedModuleSection :: [Name.Name] -> Chunk
createRemovedModuleSection removed =
  Chunk "REMOVED MODULES" Magnitude.MAJOR (Doc.vcat (fmap Doc.fromName removed))

-- | Create sections for changed modules.
createChangeSections :: Localizer.Localizer -> Map.Map Name.Name ModuleChanges -> [Chunk]
createChangeSections localizer changed =
  fmap (formatModuleChange localizer) (Map.toList changed)

-- | Format section to documentation.
formatSection :: Chunk -> Doc.Doc
formatSection chunk =
  Doc.vcat
    [ Doc.dullcyan header,
      "",
      Doc.indent 4 (chunk ^. chunkDetails),
      "",
      ""
    ]
  where
    title = chunk ^. chunkTitle
    magnitude = chunk ^. chunkMagnitude
    header = "----" <+> Doc.fromChars title <+> "-" <+> Doc.fromChars (Magnitude.toChars magnitude) <+> "----"

-- | Format individual module change.
formatModuleChange :: Localizer.Localizer -> (Name.Name, ModuleChanges) -> Chunk
formatModuleChange localizer (name, changes@(ModuleChanges unions aliases values binops)) =
  Chunk (Name.toChars name) magnitude formattedContent
  where
    magnitude = Diff.moduleChangeMagnitude changes
    formattedContent = Doc.vcat (List.intersperse "" (Maybe.catMaybes sections))
    sections = createChangeTypeSections localizer unions aliases values binops

-- | Create sections for different change types.
createChangeTypeSections :: Localizer.Localizer -> Changes Name.Name Union -> Changes Name.Name Alias -> Changes Name.Name Value -> Changes Name.Name Binop -> [Maybe Doc.Doc]
createChangeTypeSections localizer unions aliases values binops =
  [ formatChangesSection "Added" unionAdd aliasAdd valueAdd binopAdd,
    formatChangesSection "Removed" unionRemove aliasRemove valueRemove binopRemove,
    formatChangesSection "Changed" unionChange aliasChange valueChange binopChange
  ]
  where
    ( unionAdd,
      unionChange,
      unionRemove,
      aliasAdd,
      aliasChange,
      aliasRemove,
      valueAdd,
      valueChange,
      valueRemove,
      binopAdd,
      binopChange,
      binopRemove
      ) =
        formatChangeTriples localizer unions aliases values binops

-- | Format change triples for all entry types.
formatChangeTriples :: Localizer.Localizer -> Changes Name.Name Union -> Changes Name.Name Alias -> Changes Name.Name Value -> Changes Name.Name Binop -> ([Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc], [Doc.Doc])
formatChangeTriples localizer unions aliases values binops =
  ( unionAdd,
    unionChange,
    unionRemove,
    aliasAdd,
    aliasChange,
    aliasRemove,
    valueAdd,
    valueChange,
    valueRemove,
    binopAdd,
    binopChange,
    binopRemove
  )
  where
    (unionAdd, unionChange, unionRemove) = formatEntryChanges (formatUnion localizer) unions
    (aliasAdd, aliasChange, aliasRemove) = formatEntryChanges (formatAlias localizer) aliases
    (valueAdd, valueChange, valueRemove) = formatEntryChanges (formatValue localizer) values
    (binopAdd, binopChange, binopRemove) = formatEntryChanges (formatBinop localizer) binops

-- | Format entry changes to documentation triples.
formatEntryChanges :: (k -> v -> Doc.Doc) -> Changes k v -> ([Doc.Doc], [Doc.Doc], [Doc.Doc])
formatEntryChanges entryFormatter (Changes added changed removed) =
  (fmap formatAdded addedList, fmap formatChanged changedList, fmap formatRemoved removedList)
  where
    addedList = Map.toList added
    changedList = Map.toList changed
    removedList = Map.toList removed
    formatAdded (name, value) = Doc.indent 4 (entryFormatter name value)
    formatRemoved (name, value) = Doc.indent 4 (entryFormatter name value)
    formatChanged (name, (oldValue, newValue)) =
      Doc.vcat
        [ "  - " <> entryFormatter name oldValue,
          "  + " <> entryFormatter name newValue,
          ""
        ]

-- | Format changes section if any exist.
formatChangesSection :: String -> [Doc.Doc] -> [Doc.Doc] -> [Doc.Doc] -> [Doc.Doc] -> Maybe Doc.Doc
formatChangesSection categoryName unions aliases values binops =
  if null unions && null aliases && null values && null binops
    then Nothing
    else Just (Doc.vcat (Doc.fromChars categoryName <> ":" : (unions <> aliases <> binops <> values)))

-- | Format individual API entry types.
formatUnion :: Localizer.Localizer -> Name.Name -> Union -> Doc.Doc
formatUnion localizer name (Docs.Union _ tvars ctors) =
  let setup = "type" <+> Doc.fromName name <+> Doc.hsep (fmap Doc.fromName tvars)
      ctorDoc (ctor, tipes) = formatType localizer (Type.Type ctor tipes)
   in Doc.hang 4 (Doc.sep (setup : zipWith (<+>) ("=" : repeat "|") (fmap ctorDoc ctors)))

formatAlias :: Localizer.Localizer -> Name.Name -> Alias -> Doc.Doc
formatAlias localizer name (Docs.Alias _ tvars tipe) =
  let declaration = "type" <+> "alias" <+> Doc.hsep (fmap Doc.fromName (name : tvars)) <+> "="
   in Doc.hang 4 (Doc.sep [declaration, formatType localizer tipe])

formatValue :: Localizer.Localizer -> Name.Name -> Value -> Doc.Doc
formatValue localizer name (Docs.Value _ tipe) =
  Doc.hang 4 (Doc.sep [Doc.fromName name <+> ":", formatType localizer tipe])

formatBinop :: Localizer.Localizer -> Name.Name -> Binop -> Doc.Doc
formatBinop localizer name (Docs.Binop _ tipe associativity (Docs.Precedence n)) =
  "(" <> Doc.fromName name <> ")" <+> ":" <+> formatType localizer tipe <> Doc.black details
  where
    details = "    (" <> Doc.fromName assoc <> "/" <> Doc.fromInt n <> ")"
    assoc = case associativity of
      Docs.Left -> "left"
      Docs.Non -> "non"
      Docs.Right -> "right"

-- | Format type with localizer.
formatType :: Localizer.Localizer -> Type.Type -> Doc.Doc
formatType localizer = Type.toDoc localizer Type.None

-- Operator for improved readability
(<+>) :: Doc.Doc -> Doc.Doc -> Doc.Doc
(<+>) = (Doc.<+>)
