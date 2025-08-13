{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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

import Canopy.Docs (Alias, Binop, Documentation, Union, Value)
import qualified Canopy.Docs as Docs
import qualified Canopy.Magnitude as M
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import Deps.Diff (Changes (..), ModuleChanges (..), PackageChanges (..))
import qualified Deps.Diff as Diff
import Diff.Types (Chunk (..), chunkDetails, chunkMagnitude, chunkTitle)
import Control.Lens ((^.))
import qualified Reporting.Doc as D
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Render.Type.Localizer as L
import qualified Canopy.Compiler.Type as Type

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
      localizer = L.fromNames (Map.union oldDocs newDocs)
      formattedDoc = formatChanges localizer changes
  Help.toStdout (formattedDoc <> "\n")

-- | Format package changes into documentation.
--
-- Transforms computed package changes into structured documentation
-- with appropriate magnitude classification and sectioning.
--
-- @since 0.19.1
formatChanges :: L.Localizer -> PackageChanges -> D.Doc
formatChanges localizer changes@(PackageChanges added changed removed) =
  if hasNoChanges added changed removed
    then "No API changes detected, so this is a" <+> D.green "PATCH" <+> "change."
    else createFormattedDoc localizer changes added changed removed

-- | Check if package has any changes.
hasNoChanges :: [a] -> Map.Map b c -> [d] -> Bool
hasNoChanges added changed removed =
  null added && Map.null changed && null removed

-- | Create formatted documentation for changes.
createFormattedDoc :: L.Localizer -> PackageChanges -> [Name.Name] -> Map.Map Name.Name ModuleChanges -> [Name.Name] -> D.Doc
createFormattedDoc localizer changes added changed removed =
  D.vcat (createHeader changes : "" : formatSections)
  where
    sections = buildSections localizer added changed removed
    formatSections = fmap formatSection sections

-- | Create magnitude header.
createHeader :: PackageChanges -> D.Doc
createHeader changes =
  "This is a" <+> D.green magDoc <+> "change."
  where
    magDoc = D.fromChars (M.toChars (Diff.toMagnitude changes))

-- | Build formatted sections from changes.
--
-- Creates sections for added modules, removed modules, and changed modules
-- with appropriate magnitude classification and content.
--
-- @since 0.19.1
buildSections :: L.Localizer -> [Name.Name] -> Map.Map Name.Name ModuleChanges -> [Name.Name] -> [Chunk]
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
  Chunk "ADDED MODULES" M.MINOR (D.vcat (fmap D.fromName added))

-- | Create removed modules section.  
createRemovedModuleSection :: [Name.Name] -> Chunk
createRemovedModuleSection removed =
  Chunk "REMOVED MODULES" M.MAJOR (D.vcat (fmap D.fromName removed))

-- | Create sections for changed modules.
createChangeSections :: L.Localizer -> Map.Map Name.Name ModuleChanges -> [Chunk]
createChangeSections localizer changed =
  fmap (formatModuleChange localizer) (Map.toList changed)

-- | Format section to documentation.
formatSection :: Chunk -> D.Doc
formatSection chunk =
  D.vcat
    [ D.dullcyan header,
      "",
      D.indent 4 (chunk ^. chunkDetails),
      "",
      ""
    ]
  where
    title = chunk ^. chunkTitle
    magnitude = chunk ^. chunkMagnitude
    header = "----" <+> D.fromChars title <+> "-" <+> D.fromChars (M.toChars magnitude) <+> "----"

-- | Format individual module change.
formatModuleChange :: L.Localizer -> (Name.Name, ModuleChanges) -> Chunk
formatModuleChange localizer (name, changes@(ModuleChanges unions aliases values binops)) =
  Chunk (Name.toChars name) magnitude formattedContent
  where
    magnitude = Diff.moduleChangeMagnitude changes
    formattedContent = D.vcat (List.intersperse "" (Maybe.catMaybes sections))
    sections = createChangeTypeSections localizer unions aliases values binops

-- | Create sections for different change types.
createChangeTypeSections :: L.Localizer -> Changes Name.Name Union -> Changes Name.Name Alias -> Changes Name.Name Value -> Changes Name.Name Binop -> [Maybe D.Doc]
createChangeTypeSections localizer unions aliases values binops =
  [ formatChangesSection "Added" unionAdd aliasAdd valueAdd binopAdd,
    formatChangesSection "Removed" unionRemove aliasRemove valueRemove binopRemove,
    formatChangesSection "Changed" unionChange aliasChange valueChange binopChange
  ]
  where
    (unionAdd, unionChange, unionRemove, aliasAdd, aliasChange, aliasRemove, 
     valueAdd, valueChange, valueRemove, binopAdd, binopChange, binopRemove) = 
       formatChangeTriples localizer unions aliases values binops

-- | Format change triples for all entry types.
formatChangeTriples :: L.Localizer -> Changes Name.Name Union -> Changes Name.Name Alias -> Changes Name.Name Value -> Changes Name.Name Binop -> ([D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc], [D.Doc])
formatChangeTriples localizer unions aliases values binops =
  (unionAdd, unionChange, unionRemove, aliasAdd, aliasChange, aliasRemove,
   valueAdd, valueChange, valueRemove, binopAdd, binopChange, binopRemove)
  where
    (unionAdd, unionChange, unionRemove) = formatEntryChanges (formatUnion localizer) unions
    (aliasAdd, aliasChange, aliasRemove) = formatEntryChanges (formatAlias localizer) aliases
    (valueAdd, valueChange, valueRemove) = formatEntryChanges (formatValue localizer) values
    (binopAdd, binopChange, binopRemove) = formatEntryChanges (formatBinop localizer) binops

-- | Format entry changes to documentation triples.
formatEntryChanges :: (k -> v -> D.Doc) -> Changes k v -> ([D.Doc], [D.Doc], [D.Doc])
formatEntryChanges entryFormatter (Changes added changed removed) =
  (fmap formatAdded addedList, fmap formatChanged changedList, fmap formatRemoved removedList)
  where
    addedList = Map.toList added
    changedList = Map.toList changed  
    removedList = Map.toList removed
    formatAdded (name, value) = D.indent 4 (entryFormatter name value)
    formatRemoved (name, value) = D.indent 4 (entryFormatter name value)
    formatChanged (name, (oldValue, newValue)) = D.vcat
      [ "  - " <> entryFormatter name oldValue,
        "  + " <> entryFormatter name newValue,
        ""
      ]

-- | Format changes section if any exist.
formatChangesSection :: String -> [D.Doc] -> [D.Doc] -> [D.Doc] -> [D.Doc] -> Maybe D.Doc
formatChangesSection categoryName unions aliases values binops =
  if null unions && null aliases && null values && null binops
    then Nothing
    else Just (D.vcat (D.fromChars categoryName <> ":" : (unions <> aliases <> binops <> values)))

-- | Format individual API entry types.

formatUnion :: L.Localizer -> Name.Name -> Union -> D.Doc
formatUnion localizer name (Docs.Union _ tvars ctors) =
  let setup = "type" <+> D.fromName name <+> D.hsep (fmap D.fromName tvars)
      ctorDoc (ctor, tipes) = formatType localizer (Type.Type ctor tipes)
  in D.hang 4 (D.sep (setup : zipWith (<+>) ("=" : repeat "|") (fmap ctorDoc ctors)))

formatAlias :: L.Localizer -> Name.Name -> Alias -> D.Doc  
formatAlias localizer name (Docs.Alias _ tvars tipe) =
  let declaration = "type" <+> "alias" <+> D.hsep (fmap D.fromName (name : tvars)) <+> "="
  in D.hang 4 (D.sep [declaration, formatType localizer tipe])

formatValue :: L.Localizer -> Name.Name -> Value -> D.Doc
formatValue localizer name (Docs.Value _ tipe) =
  D.hang 4 (D.sep [D.fromName name <+> ":", formatType localizer tipe])

formatBinop :: L.Localizer -> Name.Name -> Binop -> D.Doc
formatBinop localizer name (Docs.Binop _ tipe associativity (Docs.Precedence n)) =
  "(" <> D.fromName name <> ")" <+> ":" <+> formatType localizer tipe <> D.black details
  where
    details = "    (" <> D.fromName assoc <> "/" <> D.fromInt n <> ")"
    assoc = case associativity of
      Docs.Left -> "left"
      Docs.Non -> "non" 
      Docs.Right -> "right"

-- | Format type with localizer.
formatType :: L.Localizer -> Type.Type -> D.Doc
formatType localizer = Type.toDoc localizer Type.None

-- Operator for improved readability
(<+>) :: D.Doc -> D.Doc -> D.Doc
(<+>) = (D.<+>)