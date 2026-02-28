{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}

module Type.UnionFind
  ( Point,
    fresh,
    union,
    equivalent,
    redundant,
    repr,
    get,
    set,
    modify,
    pointId,
  )
where

{- This is based on the following implementations:

  - https://hackage.haskell.org/package/union-find-0.2/docs/src/Data-UnionFind-IO.html
  - http://yann.regis-gianas.org/public/mini/code_UnionFind.html

It seems like the OCaml one came first, but I am not sure.

Compared to the Haskell implementation, the major changes here include:

  1. No more reallocating PointInfo when changing the weight
  2. Using the strict modifyIORef

-}

import Control.Monad (when)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.Word (Word32)
import qualified Reporting.InternalError as InternalError
import System.IO.Unsafe (unsafePerformIO)

-- POINT

-- | A union-find point with a unique integer identity.
--
-- The 'Int' field provides a stable, unique identifier for each point,
-- enabling O(log n) membership checks via 'Data.IntSet' in the occurs
-- check. Without this, the occurs check must use O(n) list membership.
data Point a
  = Pt {-# UNPACK #-} !Int (IORef (PointInfo a))

instance Eq (Point a) where
  (Pt _ ref1) == (Pt _ ref2) = ref1 == ref2

-- | Extract the unique integer identifier from a point.
--
-- This ID is assigned at creation time via 'fresh' and never changes,
-- even as the union-find structure evolves. Useful for building 'IntSet'
-- membership structures in the occurs check.
--
-- @since 0.19.2
pointId :: Point a -> Int
pointId (Pt pid _) = pid

-- | Global counter for assigning unique point IDs.
--
-- __SAFETY__: This use of 'unsafePerformIO' is safe because:
--
--   1. __Single initialization__: The @NOINLINE@ pragma prevents GHC from
--      inlining or duplicating this CAF. The counter starts at 0 and
--      only increases.
--   2. __Thread safety__: All increments use 'atomicModifyIORef'' (see
--      'fresh'), which is safe under concurrent access.
--   3. __No observable side effects__: The counter produces unique IDs
--      for type variables in the union-find. The exact ID values do not
--      matter for correctness -- only uniqueness within a single type
--      checking session matters, and that is guaranteed by the atomic
--      increment.
--
-- __Alternatives rejected__:
--
--   * Threading a counter via 'StateT' would require changing the
--     signature of 'fresh' and every function that transitively calls
--     it throughout the type checker, which is essentially the entire
--     constraint solver.
--
-- @since 0.19.2
{-# NOINLINE nextPointId #-}
nextPointId :: IORef Int
nextPointId = unsafePerformIO (newIORef 0)

data PointInfo a
  = Info {-# UNPACK #-} !(IORef Word32) {-# UNPACK #-} !(IORef a)
  | Link {-# UNPACK #-} !(Point a)

-- HELPERS

fresh :: a -> IO (Point a)
fresh value =
  do
    pid <- atomicModifyIORef' nextPointId (\n -> (n + 1, n))
    weight <- newIORef 1
    desc <- newIORef value
    link <- newIORef (Info weight desc)
    return (Pt pid link)

repr :: Point a -> IO (Point a)
repr point@(Pt _ ref) =
  do
    pInfo <- readIORef ref
    case pInfo of
      Info _ _ ->
        return point
      Link point1@(Pt _ ref1) ->
        do
          point2 <- repr point1
          when (point2 /= point1) $
            do
              pInfo1 <- readIORef ref1
              writeIORef ref pInfo1
          return point2

get :: Point a -> IO a
get point@(Pt _ ref) =
  do
    pInfo <- readIORef ref
    case pInfo of
      Info _ descRef ->
        readIORef descRef
      Link (Pt _ ref1) ->
        do
          link' <- readIORef ref1
          case link' of
            Info _ descRef ->
              readIORef descRef
            Link _ ->
              repr point >>= get

set :: Point a -> a -> IO ()
set point@(Pt _ ref) newDesc =
  do
    pInfo <- readIORef ref
    case pInfo of
      Info _ descRef ->
        writeIORef descRef newDesc
      Link (Pt _ ref1) ->
        do
          link' <- readIORef ref1
          case link' of
            Info _ descRef ->
              writeIORef descRef newDesc
            Link _ ->
              do
                newPoint <- repr point
                set newPoint newDesc

modify :: Point a -> (a -> a) -> IO ()
modify point@(Pt _ ref) func =
  do
    pInfo <- readIORef ref
    case pInfo of
      Info _ descRef ->
        modifyIORef' descRef func
      Link (Pt _ ref1) ->
        do
          link' <- readIORef ref1
          case link' of
            Info _ descRef ->
              modifyIORef' descRef func
            Link _ ->
              do
                newPoint <- repr point
                modify newPoint func

union :: Point a -> Point a -> a -> IO ()
union p1 p2 newDesc =
  do
    point1@(Pt _ ref1) <- repr p1
    point2@(Pt _ ref2) <- repr p2

    desc1 <- readIORef ref1
    desc2 <- readIORef ref2

    case (desc1, desc2) of
      (Info w1 d1, Info w2 d2) ->
        if point1 == point2
          then writeIORef d1 newDesc
          else do
            weight1 <- readIORef w1
            weight2 <- readIORef w2
            let !newWeight = weight1 + weight2
            if weight1 >= weight2
              then do
                writeIORef ref2 (Link point1)
                writeIORef w1 newWeight
                writeIORef d1 newDesc
              else do
                writeIORef ref1 (Link point2)
                writeIORef w2 newWeight
                writeIORef d2 newDesc
      _ ->
        InternalError.report "Type.UnionFind" "repr returned a Link node in union"
          "The repr function should always resolve to an Info node. A Link node here indicates a bug in the union-find implementation."

equivalent :: Point a -> Point a -> IO Bool
equivalent p1 p2 =
  do
    v1 <- repr p1
    v2 <- repr p2
    return (v1 == v2)

redundant :: Point a -> IO Bool
redundant (Pt _ ref) =
  do
    pInfo <- readIORef ref
    case pInfo of
      Info _ _ ->
        return False
      Link _ ->
        return True
