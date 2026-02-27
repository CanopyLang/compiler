
-- | REPL state management and serialization.
--
-- This module handles the REPL's evaluation state, including
-- imports, type definitions, and value declarations. It also
-- provides functionality to serialize state to ByteString
-- for compilation.
--
-- @since 0.19.1
module Repl.State
  ( -- * State Operations
    initialState,
    toByteString,

    -- * State Updates
    addImport,
    addType,
    addDecl,

    -- * Auto-completion
    lookupCompletions,
  )
where

import qualified Control.Monad.State.Strict as State
import Data.ByteString (ByteString)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as N
import Repl.Types (M, Output (..), State (..), outputToBuilder)
import System.Console.Haskeline (Completion)
import qualified System.Console.Haskeline as Repl

-- | Create initial empty REPL state.
--
-- @since 0.19.1
initialState :: State
initialState = State Map.empty Map.empty Map.empty

-- | Convert REPL state and output to compilable ByteString.
--
-- Generates a complete Canopy module containing all accumulated
-- imports, types, and declarations, plus the current output.
--
-- @since 0.19.1
toByteString :: State -> Output -> ByteString
toByteString (State imports types decls) output =
  LBS.toStrict (B.toLazyByteString moduleBuilder)
  where
    moduleBuilder =
      mconcat
        [ moduleHeader,
          Map.foldr mappend mempty imports,
          Map.foldr mappend mempty types,
          Map.foldr mappend mempty decls,
          outputToBuilder output
        ]

    moduleHeader =
      mconcat
        [ B.stringUtf8 "module ",
          N.toBuilder N.replModule,
          B.stringUtf8 " exposing (..)\n"
        ]

-- | Add an import to the REPL state.
--
-- @since 0.19.1
addImport :: N.Name -> ByteString -> State -> State
addImport name src state =
  state {_imports = Map.insert name (B.byteString src) (_imports state)}

-- | Add a type definition to the REPL state.
--
-- @since 0.19.1
addType :: N.Name -> ByteString -> State -> State
addType name src state =
  state {_types = Map.insert name (B.byteString src) (_types state)}

-- | Add a declaration to the REPL state.
--
-- @since 0.19.1
addDecl :: N.Name -> ByteString -> State -> State
addDecl name src state =
  state {_decls = Map.insert name (B.byteString src) (_decls state)}

-- | Generate auto-completion suggestions.
--
-- Provides completions for imports, types, declarations, and commands
-- based on the current input prefix.
--
-- @since 0.19.1
lookupCompletions :: String -> M [Completion]
lookupCompletions string = do
  State imports types decls <- State.get
  pure (buildCompletions string imports types decls)
  where
    buildCompletions str imp typ dec =
      addMatches
        str
        False
        dec
        ( addMatches
            str
            False
            typ
            ( addMatches
                str
                True
                imp
                (addMatches str False commands [])
            )
        )

-- | REPL command completions.
--
-- @since 0.19.1
commands :: Map N.Name ()
commands =
  Map.fromList
    [ (N.fromChars ":exit", ()),
      (N.fromChars ":quit", ()),
      (N.fromChars ":reset", ()),
      (N.fromChars ":help", ())
    ]

-- | Add matching completions from a name map.
--
-- @since 0.19.1
addMatches :: String -> Bool -> Map N.Name v -> [Completion] -> [Completion]
addMatches string isFinished dict completions =
  Map.foldrWithKey (addMatch string isFinished) completions dict

-- | Add a single completion if it matches the prefix.
--
-- @since 0.19.1
addMatch :: String -> Bool -> N.Name -> v -> [Completion] -> [Completion]
addMatch string isFinished name _ completions =
  if string `List.isPrefixOf` suggestion
    then Repl.Completion suggestion suggestion isFinished : completions
    else completions
  where
    suggestion = N.toChars name
