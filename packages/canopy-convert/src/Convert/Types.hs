{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Types for the Elm-to-Canopy package conversion pipeline.
--
-- Defines the options, results, and error types used throughout the conversion
-- process. All record types use lenses for access and updates.
--
-- @since 0.19.2
module Convert.Types
  ( -- * Options
    ConvertOptions (..),
    convertSourceDir,
    convertOutputDir,
    convertDryRun,

    -- * Results
    ConvertResult (..),
    convertFilesRenamed,
    convertProjectConverted,
    convertErrors,

    -- * Errors
    ConvertError (..),
  )
where

import Control.Lens (makeLenses)
import Data.Text (Text)

-- | Errors that can occur during package conversion.
--
-- @since 0.19.2
data ConvertError
  = -- | The source directory does not exist.
    SourceDirNotFound !FilePath
  | -- | No @elm.json@ found in the source directory.
    NoElmJson !FilePath
  | -- | The package uses ports or kernel code and cannot be auto-converted.
    UnsupportedFeature !FilePath !Text
  | -- | A file operation failed.
    FileError !FilePath !Text
  deriving (Eq, Show)

-- | Options controlling a package conversion run.
--
-- @since 0.19.2
data ConvertOptions = ConvertOptions
  { -- | Root directory of the Elm package to convert.
    _convertSourceDir :: !FilePath,
    -- | Output directory for the converted Canopy package.
    --   When 'Nothing', conversion happens in-place.
    _convertOutputDir :: !(Maybe FilePath),
    -- | When 'True', report what would change without writing files.
    _convertDryRun :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''ConvertOptions

-- | Summary of a completed conversion run.
--
-- @since 0.19.2
data ConvertResult = ConvertResult
  { -- | Number of source files renamed from @.elm@ to @.can@.
    _convertFilesRenamed :: !Int,
    -- | Whether the project file was converted.
    _convertProjectConverted :: !Bool,
    -- | Errors encountered during conversion.
    _convertErrors :: ![ConvertError]
  }
  deriving (Eq, Show)

makeLenses ''ConvertResult
