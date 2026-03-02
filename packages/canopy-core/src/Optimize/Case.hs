
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Optimize.Case
  ( optimize,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import Control.Arrow (second)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Canopy.Data.Name as Name
import qualified Optimize.DecisionTree as DT
import qualified Reporting.InternalError as InternalError

-- OPTIMIZE A CASE EXPRESSION

optimize :: Name.Name -> Name.Name -> [(Can.Pattern, Opt.Expr)] -> Opt.Expr
optimize temp root optBranches =
  let (patterns, indexedBranches) =
        unzip (zipWith indexify [0 ..] optBranches)

      decider = treeToDecider (DT.compile patterns)
      targetCounts = countTargets decider

      reachableBranches = filter (isReachable targetCounts) indexedBranches
      (choices, maybeJumps) =
        unzip (map (createChoices targetCounts) reachableBranches)
      finalDecider = insertChoices (Map.fromList choices) decider
      jumpTable = Maybe.catMaybes maybeJumps
   in validateCaseConsistency finalDecider jumpTable
        (Opt.Case temp root finalDecider jumpTable)

-- | A branch is reachable when the decision tree references its target.
isReachable :: Map.Map Int Int -> (Int, a) -> Bool
isReachable targetCounts (target, _) =
  Map.member target targetCounts

indexify :: Int -> (a, b) -> ((a, Int), (Int, b))
indexify index (pattern, branch) =
  ( (pattern, index),
    (index, branch)
  )

-- TREE TO DECIDER
--
-- Decision trees may have some redundancies, so we convert them to a Decider
-- which has special constructs to avoid code duplication when possible.

treeToDecider :: DT.DecisionTree -> Opt.Decider Int
treeToDecider tree =
  case tree of
    DT.Match target ->
      Opt.Leaf target
    -- zero options
    DT.Decision _ [] Nothing ->
      InternalError.report "Optimize.Case.treeToDecider" "Empty decision tree — no edges and no fallback" "The pattern match compiler produced a decision node with no branches."
    -- one option
    DT.Decision _ [(_, subTree)] Nothing ->
      treeToDecider subTree
    DT.Decision _ [] (Just subTree) ->
      treeToDecider subTree
    -- two options
    DT.Decision path [(test, successTree)] (Just failureTree) ->
      toChain path test successTree failureTree
    DT.Decision path [(test, successTree), (_, failureTree)] Nothing ->
      toChain path test successTree failureTree
    -- many options
    DT.Decision path edges Nothing ->
      let (necessaryTests, fallback) = splitEdges edges
       in Opt.FanOut
            path
            (map (second treeToDecider) necessaryTests)
            (treeToDecider fallback)
    DT.Decision path edges (Just fallback) ->
      Opt.FanOut path (map (second treeToDecider) edges) (treeToDecider fallback)

splitEdges :: [(a, b)] -> ([(a, b)], b)
splitEdges [] = InternalError.report "Optimize.Case.splitEdges" "Empty edges list" "Cannot split an empty edge list into init and last."
splitEdges [x] = ([], snd x)
splitEdges (x : xs) =
  let (rest, final) = splitEdges xs
   in (x : rest, final)

toChain :: DT.Path -> DT.Test -> DT.DecisionTree -> DT.DecisionTree -> Opt.Decider Int
toChain path test successTree failureTree =
  let failure =
        treeToDecider failureTree
   in case treeToDecider successTree of
        Opt.Chain testChain success subFailure
          | failure == subFailure ->
            Opt.Chain ((path, test) : testChain) success failure
        success ->
          Opt.Chain [(path, test)] success failure

-- INSERT CHOICES
--
-- If a target appears exactly once in a Decider, the corresponding expression
-- can be inlined. Whether things are inlined or jumps is called a "choice".

countTargets :: Opt.Decider Int -> Map.Map Int Int
countTargets decisionTree =
  case decisionTree of
    Opt.Leaf target ->
      Map.singleton target 1
    Opt.Chain _ success failure ->
      Map.unionWith (+) (countTargets success) (countTargets failure)
    Opt.FanOut _ tests fallback ->
      Map.unionsWith (+) (map countTargets (fallback : map snd tests))

createChoices ::
  Map.Map Int Int ->
  (Int, Opt.Expr) ->
  ((Int, Opt.Choice), Maybe (Int, Opt.Expr))
createChoices targetCounts (target, branch) =
  let count =
        maybe
          (InternalError.report "Optimize.Case.createChoices"
            ("Target index " <> Text.pack (show target) <> " missing from count map with " <> Text.pack (show (Map.size targetCounts)) <> " entries")
            "All branch targets must appear in the count map built by countTargets. This indicates a pattern match optimization bug.")
          id
          (Map.lookup target targetCounts)
   in if count == 1
        then
          ( (target, Opt.Inline branch),
            Nothing
          )
        else
          ( (target, Opt.Jump target),
            Just (target, branch)
          )

insertChoices ::
  Map.Map Int Opt.Choice ->
  Opt.Decider Int ->
  Opt.Decider Opt.Choice
insertChoices choiceDict decider =
  let go =
        insertChoices choiceDict
   in case decider of
        Opt.Leaf target ->
          Opt.Leaf
            ( maybe
                (InternalError.report "Optimize.Case.insertChoices"
                  ("Target " <> Text.pack (show target) <> " missing from choice map with " <> Text.pack (show (Map.size choiceDict)) <> " entries")
                  "All leaf targets must have a corresponding choice entry. This indicates a pattern match optimization bug.")
                id
                (Map.lookup target choiceDict)
            )
        Opt.Chain testChain success failure ->
          Opt.Chain testChain (go success) (go failure)
        Opt.FanOut path tests fallback ->
          Opt.FanOut path (map (second go) tests) (go fallback)

-- VALIDATION

-- | Verify that every 'Jump' index in the decider has a corresponding
-- entry in the jump table. Reports an internal error on mismatch to
-- catch regressions early rather than producing invalid JavaScript.
validateCaseConsistency :: Opt.Decider Opt.Choice -> [(Int, Opt.Expr)] -> a -> a
validateCaseConsistency decider jumpTable result =
  let jumpIndices = collectJumpIndices decider
      tableIndices = Set.fromList (map fst jumpTable)
      missing = Set.difference jumpIndices tableIndices
   in if Set.null missing
        then result
        else InternalError.report
          "Optimize.Case.validateCaseConsistency"
          ("Jump indices " <> Text.pack (show (Set.toList missing)) <> " have no table entry")
          "Every Jump in the decision tree must have a corresponding expression in the jump table."

-- | Collect all Jump indices from a decision tree.
collectJumpIndices :: Opt.Decider Opt.Choice -> Set.Set Int
collectJumpIndices = \case
  Opt.Leaf (Opt.Jump idx) -> Set.singleton idx
  Opt.Leaf (Opt.Inline _) -> Set.empty
  Opt.Chain _ success failure ->
    Set.union (collectJumpIndices success) (collectJumpIndices failure)
  Opt.FanOut _ tests fallback ->
    Set.unions (collectJumpIndices fallback : map (collectJumpIndices . snd) tests)
