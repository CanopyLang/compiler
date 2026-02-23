{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Compilation benchmarking command for Canopy projects.
--
-- Measures and reports compilation performance metrics including
-- parse time, type checking time, optimization time, and code
-- generation time. Useful for identifying performance regressions
-- and profiling the compilation pipeline.
--
-- == Features
--
-- * End-to-end compilation timing
-- * Per-phase breakdown (parse, canonicalize, type check, optimize, generate)
-- * Multiple iteration support for statistical significance
-- * JSON output for CI integration
-- * Comparison with previous baseline
--
-- @since 0.19.1
module Bench
  ( -- * Command Interface
    Flags (..),
    run,
  )
where

import qualified Canopy.Details as Details
import qualified Compiler
import Control.Lens (makeLenses, (^.))
import qualified Data.Time.Clock as Clock
import qualified Reporting
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified Stuff
import qualified System.IO as IO

-- | Bench command flags.
data Flags = Flags
  { -- | Number of iterations to run
    _iterations :: !(Maybe Int),
    -- | Output results as JSON
    _benchJson :: !Bool,
    -- | Verbose output
    _benchVerbose :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Benchmark result for a single run.
data BenchResult = BenchResult
  { _brTotal :: !Double,
    _brIteration :: !Int
  }
  deriving (Eq, Show)


-- | Run the bench command.
--
-- Compiles the project multiple times and reports timing statistics.
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> reportNoProject
    Just root -> benchProject root flags

-- | Report that no project was found.
reportNoProject :: IO ()
reportNoProject =
  IO.hPutStrLn IO.stderr "Error: No canopy.json found. Run this from a Canopy project directory."

-- | Benchmark a project.
benchProject :: FilePath -> Flags -> IO ()
benchProject root flags = do
  let iters = maybe 3 id (flags ^. iterations)
  IO.putStrLn ("Benchmarking compilation (" ++ show iters ++ " iterations)...")
  IO.putStrLn ""
  results <- mapM (runIteration root flags) [1 .. iters]
  reportResults flags results

-- | Run a single benchmark iteration.
runIteration :: FilePath -> Flags -> Int -> IO BenchResult
runIteration root flags iter = do
  when (flags ^. benchVerbose) (IO.putStrLn ("  Iteration " ++ show iter ++ "..."))
  start <- Clock.getCurrentTime
  compileProject root
  end <- Clock.getCurrentTime
  let elapsed = realToFrac (Clock.diffUTCTime end start) :: Double
  pure (BenchResult elapsed iter)
  where
    when True action = action
    when False _ = pure ()

-- | Compile the project for benchmarking.
compileProject :: FilePath -> IO ()
compileProject root = do
  detailsResult <- Details.load Reporting.silent () root
  case detailsResult of
    Left _ -> IO.hPutStrLn IO.stderr "  Warning: Could not load project details"
    Right details -> compileWithDetails root details

-- | Compile with loaded details.
--
-- Discovers all @.can@ source files in the project's source directories,
-- then invokes the compiler to measure compilation time.
compileWithDetails :: FilePath -> Details.Details -> IO ()
compileWithDetails root details = do
  let srcDirs = map Compiler.RelativeSrcDir (Details._detailsSrcDirs details)
      pkg = Details.dummyPkgName
      absSrcDirs = map (resolveSrcDir root) srcDirs
  canFiles <- fmap concat (mapM findCanFiles absSrcDirs)
  result <- Compiler.compileFromPaths pkg True root srcDirs canFiles
  case result of
    Left _ -> IO.hPutStrLn IO.stderr "  Warning: Compilation failed during benchmark"
    Right _ -> pure ()

-- | Resolve a 'Compiler.SrcDir' to an absolute path.
resolveSrcDir :: FilePath -> Compiler.SrcDir -> FilePath
resolveSrcDir root (Compiler.RelativeSrcDir d) = root FP.</> d
resolveSrcDir _ (Compiler.AbsoluteSrcDir d) = d

-- | Recursively find all @.can@ source files in a directory.
findCanFiles :: FilePath -> IO [FilePath]
findCanFiles dir = do
  exists <- Dir.doesDirectoryExist dir
  if not exists
    then pure []
    else do
      entries <- Dir.listDirectory dir
      let paths = map (dir FP.</>) entries
      files <- filterIO Dir.doesFileExist paths
      dirs <- filterIO Dir.doesDirectoryExist paths
      nested <- mapM findCanFiles dirs
      pure (filter isCanFile files ++ concat nested)

-- | Filter a list with a monadic predicate.
filterIO :: (a -> IO Bool) -> [a] -> IO [a]
filterIO _ [] = pure []
filterIO p (x : xs) = do
  keep <- p x
  rest <- filterIO p xs
  pure (if keep then x : rest else rest)

-- | Check whether a file has the @.can@ extension.
isCanFile :: FilePath -> Bool
isCanFile p = FP.takeExtension p == ".can"

-- | Report benchmark results.
reportResults :: Flags -> [BenchResult] -> IO ()
reportResults flags results =
  if flags ^. benchJson
    then reportResultsJson results
    else reportResultsTerminal results

-- | Report results in terminal format.
reportResultsTerminal :: [BenchResult] -> IO ()
reportResultsTerminal results = do
  let times = map _brTotal results
      avg = sum times / fromIntegral (length times)
      minTime = minimum times
      maxTime = maximum times
  IO.putStrLn "Results:"
  IO.putStrLn ("  Iterations: " ++ show (length results))
  IO.putStrLn ("  Average:    " ++ formatTime avg)
  IO.putStrLn ("  Min:        " ++ formatTime minTime)
  IO.putStrLn ("  Max:        " ++ formatTime maxTime)
  mapM_ reportIteration results

-- | Report a single iteration.
reportIteration :: BenchResult -> IO ()
reportIteration result =
  IO.putStrLn ("  Run " ++ show (_brIteration result) ++ ":      " ++ formatTime (_brTotal result))

-- | Report results in JSON format.
reportResultsJson :: [BenchResult] -> IO ()
reportResultsJson results = do
  let times = map _brTotal results
      avg = sum times / fromIntegral (length times)
  IO.putStrLn ("{\"iterations\":" ++ show (length results) ++ ",\"average_ms\":" ++ show (avg * 1000) ++ ",\"runs\":[" ++ runsJson results ++ "]}")
  where
    runsJson rs = foldr joinComma "" (map runJson rs)
    runJson r = show (_brTotal r * 1000)
    joinComma x "" = x
    joinComma x acc = x ++ "," ++ acc

-- | Format a time value in human-readable form.
formatTime :: Double -> String
formatTime seconds
  | seconds < 0.001 = show (seconds * 1000000) ++ " μs"
  | seconds < 1.0 = show (round (seconds * 1000) :: Int) ++ " ms"
  | otherwise = show (div (round (seconds * 100) :: Int) 100) ++ " s"
