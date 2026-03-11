{-# LANGUAGE OverloadedStrings #-}

-- | Kit.Route.Scanner -- Filesystem-based route discovery.
--
-- Walks the @src\/routes\/@ directory tree and produces a 'RouteManifest'
-- containing every route, layout, and error boundary.
--
-- Directory structure conventions:
--
-- * @page.can@ files define page routes.
-- * @layout.can@ files define layout wrappers that apply to all sibling
--   and descendant routes.
-- * @error.can@ files define error boundary modules.
-- * Plain directories become 'StaticSegment' values.
-- * Directories named @[param]@ become 'DynamicSegment' values.
-- * Directories named @[...param]@ become 'CatchAll' values.
-- * Directories named @api\/@ mark their @page.can@ children as 'ApiRoute'.
--
-- @since 0.19.2
module Kit.Route.Scanner
  ( scanRoutes
  ) where

import qualified Control.Exception as Exception
import qualified Control.Monad.Trans as Trans
import Control.Monad.Trans.Except (ExceptT)
import qualified Control.Monad.Trans.Except as ExceptT
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types
  ( LayoutEntry (..)
  , PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , ScanError (..)
  )
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | Scan the @src\/routes\/@ directory and build a 'RouteManifest'.
--
-- Returns 'DirectoryNotFound' when the routes directory does not exist,
-- or 'IOScanError' when an IO operation fails during traversal.
--
-- @since 0.19.2
scanRoutes :: FilePath -> IO (Either ScanError RouteManifest)
scanRoutes root =
  ExceptT.runExceptT (scanRoutesDir routesDir)
  where
    routesDir = root FP.</> "src" FP.</> "routes"

-- | Top-level scan that checks directory existence, then delegates.
scanRoutesDir :: FilePath -> ExceptT ScanError IO RouteManifest
scanRoutesDir dir = do
  exists <- Trans.liftIO (Dir.doesDirectoryExist dir)
  guardDirectoryExists exists dir
  walkDirectory dir []

-- | Abort with 'DirectoryNotFound' when the directory is missing.
guardDirectoryExists :: Bool -> FilePath -> ExceptT ScanError IO ()
guardDirectoryExists True _ = pure ()
guardDirectoryExists False dir = ExceptT.throwE (DirectoryNotFound dir)

-- | Recursively walk a directory, accumulating the route prefix.
walkDirectory
  :: FilePath -> [RouteSegment] -> ExceptT ScanError IO RouteManifest
walkDirectory dir prefix = do
  entries <- listDirectorySafe dir
  processEntries dir prefix entries

-- | List directory contents, converting IO exceptions to 'ScanError'.
listDirectorySafe :: FilePath -> ExceptT ScanError IO [FilePath]
listDirectorySafe dir =
  Trans.liftIO (tryListDirectory dir) >>= liftEitherScan
  where
    liftEitherScan (Right xs) = pure xs
    liftEitherScan (Left msg) = ExceptT.throwE (IOScanError dir msg)

-- | Attempt to list a directory, catching IO exceptions.
tryListDirectory :: FilePath -> IO (Either Text [FilePath])
tryListDirectory dir =
  fmap (either formatErr Right) (safeTry (Dir.listDirectory dir))
  where
    formatErr = Left . Text.pack . show

-- | Run an IO action, catching synchronous 'IOError' exceptions.
safeTry :: IO a -> IO (Either IOError a)
safeTry action =
  Exception.catch (fmap Right action) (pure . Left)

-- | Process all entries in a single directory level.
processEntries
  :: FilePath
  -> [RouteSegment]
  -> [FilePath]
  -> ExceptT ScanError IO RouteManifest
processEntries dir prefix entries = do
  children <- collectChildren dir prefix entries
  pure (mergeManifests pageManifest layoutManifest errorManifest children)
  where
    pageManifest = collectPages dir prefix entries
    layoutManifest = collectLayouts dir prefix entries
    errorManifest = collectErrorBoundaries dir prefix entries

-- | Find @page.can@ entries and convert them to 'RouteEntry' values.
collectPages
  :: FilePath -> [RouteSegment] -> [FilePath] -> RouteManifest
collectPages dir prefix entries =
  emptyManifest { _rmRoutes = routes }
  where
    routes = maybe [] pure (findPage dir prefix entries)

-- | Build a 'RouteEntry' when @page.can@ exists among the entries.
findPage :: FilePath -> [RouteSegment] -> [FilePath] -> Maybe RouteEntry
findPage dir prefix entries
  | "page.can" `elem` entries = Just (buildRouteEntry dir prefix)
  | otherwise = Nothing

-- | Construct a 'RouteEntry' from a directory path and segment prefix.
buildRouteEntry :: FilePath -> [RouteSegment] -> RouteEntry
buildRouteEntry dir prefix = RouteEntry
  { _rePattern = RoutePattern
      { _rpSegments = prefix
      , _rpFilePath = pagePath
      }
  , _rePageKind = classifyPageKind prefix
  , _reSourceFile = pagePath
  , _reModuleName = segmentsToModuleName prefix
  }
  where
    pagePath = dir FP.</> "page.can"

-- | Classify a page based on its route prefix.
--
-- Routes under an @api@ static segment are 'ApiRoute'. Routes containing
-- any dynamic or catch-all segment are 'DynamicPage'. Everything else
-- is 'StaticPage'.
--
-- @since 0.19.2
classifyPageKind :: [RouteSegment] -> PageKind
classifyPageKind segments
  | any isApiSegment segments = ApiRoute
  | any isDynamic segments = DynamicPage
  | otherwise = StaticPage

-- | Test whether a segment is the literal @api@ prefix.
isApiSegment :: RouteSegment -> Bool
isApiSegment (StaticSegment "api") = True
isApiSegment _ = False

-- | Test whether a segment captures a dynamic parameter.
isDynamic :: RouteSegment -> Bool
isDynamic (DynamicSegment _) = True
isDynamic (CatchAll _) = True
isDynamic (StaticSegment _) = False

-- | Find @layout.can@ files and produce layout entries.
collectLayouts :: FilePath -> [RouteSegment] -> [FilePath] -> RouteManifest
collectLayouts dir prefix entries =
  emptyManifest { _rmLayouts = layouts }
  where
    layouts = collectSpecialFile "layout.can" dir prefix entries

-- | Find @error.can@ files and produce error boundary entries.
collectErrorBoundaries
  :: FilePath -> [RouteSegment] -> [FilePath] -> RouteManifest
collectErrorBoundaries dir prefix entries =
  emptyManifest { _rmErrorBoundaries = boundaries }
  where
    boundaries = collectSpecialFile "error.can" dir prefix entries

-- | Build a 'LayoutEntry' when the named file exists in the entry list.
collectSpecialFile
  :: FilePath -> FilePath -> [RouteSegment] -> [FilePath] -> [LayoutEntry]
collectSpecialFile name dir prefix entries
  | name `elem` entries = [LayoutEntry prefix (dir FP.</> name)]
  | otherwise = []

-- | Recursively scan subdirectories and merge their manifests.
collectChildren
  :: FilePath
  -> [RouteSegment]
  -> [FilePath]
  -> ExceptT ScanError IO RouteManifest
collectChildren dir prefix entries = do
  subdirs <- filterSubdirectories dir entries
  manifests <- traverse (scanSubdirectory dir prefix) subdirs
  pure (foldl mergeTwo emptyManifest manifests)

-- | Keep only entries that are directories.
filterSubdirectories
  :: FilePath -> [FilePath] -> ExceptT ScanError IO [FilePath]
filterSubdirectories dir entries =
  Trans.liftIO (filterByDirectory dir entries)

-- | Filter a list of names to those that are directories under a parent.
filterByDirectory :: FilePath -> [FilePath] -> IO [FilePath]
filterByDirectory _ [] = pure []
filterByDirectory parent (x : xs) = do
  isDir <- Dir.doesDirectoryExist (parent FP.</> x)
  rest <- filterByDirectory parent xs
  pure (if isDir then x : rest else rest)

-- | Scan a single subdirectory after parsing its name into a segment.
scanSubdirectory
  :: FilePath
  -> [RouteSegment]
  -> FilePath
  -> ExceptT ScanError IO RouteManifest
scanSubdirectory parentDir prefix dirName = do
  segment <- parseSegment parentDir dirName
  walkDirectory (parentDir FP.</> dirName) (prefix <> [segment])

-- | Parse a directory name into a 'RouteSegment'.
--
-- Recognises three forms:
--
-- * @[...name]@ -- catch-all segment
-- * @[name]@ -- dynamic segment
-- * @plainName@ -- static segment
--
-- Returns 'InvalidSegmentName' for malformed bracket expressions such
-- as empty brackets or unterminated @[...@.
--
-- @since 0.19.2
parseSegment :: FilePath -> FilePath -> ExceptT ScanError IO RouteSegment
parseSegment parentDir dirName =
  either ExceptT.throwE pure (parseSegmentPure parentDir nameText)
  where
    nameText = Text.pack dirName

-- | Pure segment parser extracted for testability.
parseSegmentPure :: FilePath -> Text -> Either ScanError RouteSegment
parseSegmentPure parentDir name
  | isCatchAllBracket name = parseCatchAll parentDir name
  | isDynamicBracket name = parseDynamic parentDir name
  | otherwise = Right (StaticSegment name)

-- | Test for @[...@ prefix and @]@ suffix.
isCatchAllBracket :: Text -> Bool
isCatchAllBracket t =
  Text.isPrefixOf "[..." t && Text.isSuffixOf "]" t

-- | Test for @[@ prefix and @]@ suffix (but not catch-all).
isDynamicBracket :: Text -> Bool
isDynamicBracket t =
  Text.isPrefixOf "[" t
    && Text.isSuffixOf "]" t
    && not (Text.isPrefixOf "[..." t)

-- | Extract the parameter name from a @[...name]@ directory.
parseCatchAll :: FilePath -> Text -> Either ScanError RouteSegment
parseCatchAll parentDir name =
  validateParamName parentDir paramName (CatchAll paramName)
  where
    paramName = Text.drop 4 (Text.dropEnd 1 name)

-- | Extract the parameter name from a @[name]@ directory.
parseDynamic :: FilePath -> Text -> Either ScanError RouteSegment
parseDynamic parentDir name =
  validateParamName parentDir paramName (DynamicSegment paramName)
  where
    paramName = Text.drop 1 (Text.dropEnd 1 name)

-- | Reject empty or whitespace-only parameter names.
validateParamName
  :: FilePath -> Text -> RouteSegment -> Either ScanError RouteSegment
validateParamName parentDir paramName segment
  | Text.null (Text.strip paramName) =
      Left (InvalidSegmentName parentDir paramName)
  | otherwise = Right segment

-- | Convert route segments to a dotted Canopy module name.
--
-- Static segments are capitalised. Dynamic segments use the parameter
-- name capitalised with a @Param_@ prefix. Catch-all segments use
-- a @CatchAll_@ prefix.
--
-- @since 0.19.2
segmentsToModuleName :: [RouteSegment] -> Text
segmentsToModuleName [] = "Routes.Index"
segmentsToModuleName segs =
  Text.intercalate "." ("Routes" : fmap segmentToModule segs)

-- | Convert a single segment to its module name component.
segmentToModule :: RouteSegment -> Text
segmentToModule (StaticSegment t) = capitalise t
segmentToModule (DynamicSegment t) = "Param_" <> capitalise t
segmentToModule (CatchAll t) = "CatchAll_" <> capitalise t

-- | Capitalise the first character of a text value.
capitalise :: Text -> Text
capitalise t =
  maybe t applyUpper (Text.uncons t)
  where
    applyUpper (c, rest) = Text.cons (toUpper c) rest
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

-- | A manifest with no entries.
emptyManifest :: RouteManifest
emptyManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

-- | Merge child manifests into the pages/layouts/errors result.
mergeManifests
  :: RouteManifest
  -> RouteManifest
  -> RouteManifest
  -> RouteManifest
  -> RouteManifest
mergeManifests pages layouts errors children =
  foldl mergeTwo emptyManifest [pages, layouts, errors, children]

-- | Combine two manifests by concatenating their entry lists.
mergeTwo :: RouteManifest -> RouteManifest -> RouteManifest
mergeTwo a b = RouteManifest
  { _rmRoutes = _rmRoutes a <> _rmRoutes b
  , _rmLayouts = _rmLayouts a <> _rmLayouts b
  , _rmErrorBoundaries = _rmErrorBoundaries a <> _rmErrorBoundaries b
  }
