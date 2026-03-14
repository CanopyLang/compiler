{-# LANGUAGE OverloadedStrings #-}

-- | Lint rule for detecting unused imports.
--
-- An import is considered used when its qualified name (or alias) or any
-- of its explicitly exposed names appear somewhere in the module's value,
-- type, or union declarations.
--
-- @since 0.19.1
module Lint.Rules.Imports
  ( checkUnusedImport,
  )
where

import qualified AST.Source as Src
import qualified Data.Maybe as Maybe
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Lint.Rules.Helpers (collectUsedNames, regionLineRange)
import Lint.Types
  ( LintFix (..),
    LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- | Rule: detect imports that are never used in the module body.
--
-- @since 0.19.1
checkUnusedImport :: Src.Module -> [LintWarning]
checkUnusedImport modul =
  Maybe.mapMaybe (checkOneImport usedNames) (Src._imports modul)
  where
    usedNames = collectUsedNames modul

-- | Produce a warning for an import if none of its exposed names are used.
checkOneImport :: Set.Set String -> Src.Import -> Maybe LintWarning
checkOneImport usedNames imp
  | isImportUsed usedNames imp = Nothing
  | otherwise = Just (unusedImportWarning imp)

-- | Check whether at least one name from the import appears in the module.
isImportUsed :: Set.Set String -> Src.Import -> Bool
isImportUsed usedNames (Src.Import (Ann.At _ modName) alias exposing _isLazy) =
  qualifierUsed || exposedNamesUsed
  where
    qualifier = maybe (Name.toChars modName) Name.toChars alias
    qualifierUsed = Set.member qualifier usedNames
    exposedNamesUsed = any (flip Set.member usedNames) (exposedNames exposing)

-- | Extract the list of explicitly exposed names from an exposing clause.
exposedNames :: Src.Exposing -> [String]
exposedNames Src.Open = []
exposedNames (Src.Explicit items) = Maybe.mapMaybe exposedItemName items

-- | Extract the string representation of a single exposed item.
exposedItemName :: Src.Exposed -> Maybe String
exposedItemName (Src.Lower (Ann.At _ n)) = Just (Name.toChars n)
exposedItemName (Src.Upper (Ann.At _ n) _) = Just (Name.toChars n)
exposedItemName (Src.Operator _ n) = Just (Name.toChars n)

-- | Build the unused-import warning for an import statement.
unusedImportWarning :: Src.Import -> LintWarning
unusedImportWarning (Src.Import (Ann.At region modName) _ _ _) =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnusedImport,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Import of `" ++ Name.toChars modName ++ "` is never used.",
      _warnFix = Just (RemoveLines startLine endLine)
    }
  where
    (startLine, endLine) = regionLineRange region
