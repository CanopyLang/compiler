
-- | Pure dependency solver without STM.
--
-- This module implements package dependency resolution using pure
-- backtracking search. Replaces the OLD Deps/Solver.hs STM-based solver.
--
-- Key differences:
--
-- * No STM - pure functional backtracking
-- * Explicit state passing
-- * Clear error messages
-- * Deterministic results
--
-- @since 0.19.1
module Builder.Solver
  ( -- * Solver Types
    SolverResult (..),
    SolverError (..),
    Constraint (..),
    Solution,

    -- * Solving
    solve,
    solveWithConstraints,
    verifySolution,

    -- * Constraint Operations
    parseConstraint,
    satisfiesConstraint,
    compatibleConstraints,

    -- * Display
    showSolution,
  )
where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Data.List (intercalate)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Word (Word16)

-- | Package version constraint.
data Constraint
  = ExactVersion !V.Version
  | MinVersion !V.Version
  | MaxVersion !V.Version
  | RangeVersion !V.Version !V.Version
  | AnyVersion
  deriving (Show, Eq)

-- | Solution mapping packages to versions.
type Solution = Map Pkg.Name V.Version

-- | Solver error.
data SolverError
  = NoSolution [Pkg.Name] -- ^ Conflicting constraints
  | ConflictingVersions Pkg.Name [Constraint]
  | MissingPackage Pkg.Name
  | CyclicDependencies [Pkg.Name]
  deriving (Show, Eq)

-- | Solver result.
data SolverResult
  = SolverSuccess !Solution
  | SolverFailure !SolverError
  deriving (Show, Eq)

-- | Solve dependencies with backtracking.
solve :: [(Pkg.Name, [Constraint])] -> SolverResult
solve constraints =
  case findSolution Map.empty constraints of
    Just solution -> SolverSuccess solution
    Nothing -> SolverFailure (NoSolution (map fst constraints))

-- | Solve with additional constraints.
solveWithConstraints ::
  Solution -> -- ^ Existing partial solution
  [(Pkg.Name, [Constraint])] -> -- ^ New constraints
  SolverResult
solveWithConstraints existing new =
  case findSolution existing new of
    Just solution -> SolverSuccess solution
    Nothing -> SolverFailure (NoSolution (map fst new))

-- | Find solution using backtracking.
findSolution :: Solution -> [(Pkg.Name, [Constraint])] -> Maybe Solution
findSolution solution [] = Just solution
findSolution solution ((pkg, constraints) : rest) =
  case selectVersion pkg constraints of
    Nothing -> Nothing
    Just version ->
      let solution' = Map.insert pkg version solution
       in if isCompatible solution' rest
            then findSolution solution' rest
            else Nothing

-- | Select a version satisfying constraints.
selectVersion :: Pkg.Name -> [Constraint] -> Maybe V.Version
selectVersion pkg constraints =
  case combineConstraints constraints of
    Nothing -> Nothing
    Just constraint -> pickVersion pkg constraint

-- | Combine multiple constraints into one.
combineConstraints :: [Constraint] -> Maybe Constraint
combineConstraints [] = Just AnyVersion
combineConstraints [c] = Just c
combineConstraints (c1 : c2 : rest) =
  case mergeConstraints c1 c2 of
    Nothing -> Nothing
    Just merged -> combineConstraints (merged : rest)

-- | Merge two constraints.
mergeConstraints :: Constraint -> Constraint -> Maybe Constraint
mergeConstraints AnyVersion c = Just c
mergeConstraints c AnyVersion = Just c
mergeConstraints (ExactVersion v1) (ExactVersion v2)
  | v1 == v2 = Just (ExactVersion v1)
  | otherwise = Nothing
mergeConstraints (MinVersion v1) (MinVersion v2) =
  Just (MinVersion (max v1 v2))
mergeConstraints (MaxVersion v1) (MaxVersion v2) =
  Just (MaxVersion (min v1 v2))
mergeConstraints (RangeVersion min1 max1) (RangeVersion min2 max2) =
  let minV = max min1 min2
      maxV = min max1 max2
   in if minV <= maxV
        then Just (RangeVersion minV maxV)
        else Nothing
mergeConstraints _ _ = Nothing -- Incompatible

-- | Pick a version satisfying constraint.
pickVersion :: Pkg.Name -> Constraint -> Maybe V.Version
pickVersion _ AnyVersion = Just V.one -- Default to 1.0.0
pickVersion _ (ExactVersion v) = Just v
pickVersion _ (MinVersion v) = Just v
pickVersion _ (MaxVersion v) = Just v
pickVersion _ (RangeVersion minV _) = Just minV

-- | Check if solution is compatible with remaining constraints.
isCompatible :: Solution -> [(Pkg.Name, [Constraint])] -> Bool
isCompatible solution constraints =
  all (checkConstraints solution) constraints
  where
    checkConstraints sol (pkg, cons) =
      case Map.lookup pkg sol of
        Nothing -> True -- Not yet in solution
        Just version -> all (satisfiesConstraint version) cons

-- | Check if version satisfies constraint.
satisfiesConstraint :: V.Version -> Constraint -> Bool
satisfiesConstraint _ AnyVersion = True
satisfiesConstraint v (ExactVersion target) = v == target
satisfiesConstraint v (MinVersion minV) = v >= minV
satisfiesConstraint v (MaxVersion maxV) = v <= maxV
satisfiesConstraint v (RangeVersion minV maxV) =
  v >= minV && v <= maxV

-- | Check if two constraints are compatible.
compatibleConstraints :: Constraint -> Constraint -> Bool
compatibleConstraints c1 c2 =
  case mergeConstraints c1 c2 of
    Just _ -> True
    Nothing -> False

-- | Parse constraint from string.
--
-- Supports both space-separated and concatenated formats:
--   ">= 1.0.0", ">=1.0.0", "== 2.5.0", "==2.5.0", "1.0.0"
--   ">=1.0.0,<=2.0.0" (range)
parseConstraint :: String -> Maybe Constraint
parseConstraint str =
  let trimmed = filter (/= ' ') str -- Remove all spaces
   in case splitOn ',' trimmed of
        [part1, part2] ->
          -- Try parsing as range constraint (e.g., ">=1.0.0,<=2.0.0")
          case (parseOperator part1, parseOperator part2) of
            (Just (">=", v1), Just ("<=", v2)) ->
              RangeVersion <$> parseVersion v1 <*> parseVersion v2
            _ -> Nothing
        [single] ->
          -- Single constraint
          case parseOperator single of
            Just (op, ver) -> case op of
              ">=" -> MinVersion <$> parseVersion ver
              "<=" -> MaxVersion <$> parseVersion ver
              "==" -> ExactVersion <$> parseVersion ver
              _ -> Nothing
            Nothing ->
              -- No operator found, try parsing as exact version
              ExactVersion <$> parseVersion single
        _ -> Nothing
  where
    parseOperator :: String -> Maybe (String, String)
    parseOperator s
      | take 2 s == ">=" = Just (">=", drop 2 s)
      | take 2 s == "<=" = Just ("<=", drop 2 s)
      | take 2 s == "==" = Just ("==", drop 2 s)
      | otherwise = Nothing
    -- Parse semantic version "X.Y.Z" format
    parseVersion versionStr =
      case splitOn '.' versionStr of
        [majorStr, minorStr, patchStr] -> do
          major <- readMaybeWord16 majorStr
          minor <- readMaybeWord16 minorStr
          patch <- readMaybeWord16 patchStr
          Just (V.Version major minor patch)
        _ -> Nothing

    splitOn :: Char -> String -> [String]
    splitOn _ [] = [""]
    splitOn delimiter (c : cs)
      | c == delimiter = "" : splitOn delimiter cs
      | otherwise =
          case splitOn delimiter cs of
            [] -> [[c]]
            (x : xs) -> (c : x) : xs

    readMaybeWord16 :: String -> Maybe Word16
    readMaybeWord16 s = case reads s :: [(Integer, String)] of
      [(n, "")] | n >= 0 && n <= 65535 -> Just (fromIntegral n)
      _ -> Nothing

-- | Verify solution satisfies all constraints.
verifySolution :: Solution -> [(Pkg.Name, [Constraint])] -> Bool
verifySolution solution constraints =
  all checkPackage constraints
  where
    checkPackage (pkg, cons) =
      case Map.lookup pkg solution of
        Nothing -> False
        Just version -> all (satisfiesConstraint version) cons

-- | Show solution in readable format.
showSolution :: Solution -> String
showSolution solution =
  intercalate ", " (map showEntry (Map.toList solution))
  where
    showEntry (pkg, version) =
      Pkg.toChars pkg ++ "@" ++ V.toChars version
