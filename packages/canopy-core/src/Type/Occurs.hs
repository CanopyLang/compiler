{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Occurs check for type unification.
--
-- Detects infinite types by checking whether a type variable appears
-- (directly or transitively) in its own definition. Uses 'IntSet' for
-- O(log n) visited-set membership, avoiding the O(n^2) worst case of
-- the original list-based approach on deeply nested types.
--
-- @since 0.19.1
module Type.Occurs
  ( occurs,
  )
where

import Data.Foldable (foldrM)
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import Type.Type as Type
import qualified Type.UnionFind as UF

-- OCCURS

-- | Check whether a type variable occurs in its own definition.
--
-- Returns 'True' if the variable is part of an infinite type cycle.
-- Uses 'IntSet' for O(log n) visited-set lookups instead of O(n) list scans.
--
-- @since 0.19.1
occurs :: Type.Variable -> IO Bool
occurs var =
  occursHelp IntSet.empty var False

-- | Recursive occurs check with an 'IntSet' of visited variable IDs.
--
-- The 'IntSet' tracks which variables have already been visited to
-- detect cycles. Each variable is identified by its unique 'pointId'.
occursHelp :: IntSet.IntSet -> Type.Variable -> Bool -> IO Bool
occursHelp seen var foundCycle =
  if UF.pointId var `IntSet.member` seen
    then return True
    else do
      (Descriptor content _ _ _) <- UF.get var
      let newSeen = IntSet.insert (UF.pointId var) seen
      occursContent newSeen content foundCycle

-- | Check occurs for a descriptor's content.
occursContent :: IntSet.IntSet -> Content -> Bool -> IO Bool
occursContent _seen (FlexVar _) foundCycle = return foundCycle
occursContent _seen (FlexSuper _ _) foundCycle = return foundCycle
occursContent _seen (RigidVar _) foundCycle = return foundCycle
occursContent _seen (RigidSuper _ _) foundCycle = return foundCycle
occursContent seen (Structure term) foundCycle = occursTerm seen term foundCycle
occursContent seen (Alias _ _ args realVar) foundCycle =
  foldrM (occursHelp seen) foundCycle (fmap snd args)
    >>= occursHelp seen realVar
occursContent _seen Error foundCycle = return foundCycle

-- | Check occurs within a flat type term.
occursTerm :: IntSet.IntSet -> FlatType -> Bool -> IO Bool
occursTerm seen term foundCycle =
  case term of
    App1 _ _ args ->
      foldrM (occursHelp seen) foundCycle args
    Fun1 a b ->
      occursHelp seen b foundCycle >>= occursHelp seen a
    EmptyRecord1 ->
      return foundCycle
    Record1 fields ext ->
      foldrM (occursHelp seen) foundCycle (Map.elems fields) >>= occursHelp seen ext
    Unit1 ->
      return foundCycle
    Tuple1 a b maybeC ->
      occursTuple seen a b maybeC foundCycle

-- | Check occurs within a tuple, handling the optional third element.
occursTuple :: IntSet.IntSet -> Type.Variable -> Type.Variable -> Maybe Type.Variable -> Bool -> IO Bool
occursTuple seen a b Nothing foundCycle =
  occursHelp seen b foundCycle >>= occursHelp seen a
occursTuple seen a b (Just c) foundCycle =
  (occursHelp seen c foundCycle >>= occursHelp seen b) >>= occursHelp seen a
