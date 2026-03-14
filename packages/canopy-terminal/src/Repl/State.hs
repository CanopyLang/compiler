
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
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Control.Lens ((%~), (&))
import Repl.Types (M, Output (..), State (..), decls, imports, outputToBuilder, types)
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
toByteString (State stImports stTypes stDecls) output =
  LBS.toStrict (BB.toLazyByteString moduleBuilder)
  where
    moduleBuilder =
      mconcat
        [ moduleHeader,
          Map.foldr mappend mempty stImports,
          Map.foldr mappend mempty stTypes,
          Map.foldr mappend mempty stDecls,
          outputToBuilder output
        ]

    moduleHeader =
      mconcat
        [ BB.stringUtf8 "module ",
          Name.toBuilder Name.replModule,
          BB.stringUtf8 " exposing (..)\n"
        ]

-- | Add an import to the REPL state.
--
-- @since 0.19.1
addImport :: Name.Name -> ByteString -> State -> State
addImport name src state =
  state & imports %~ Map.insert name (BB.byteString src)

-- | Add a type definition to the REPL state.
--
-- @since 0.19.1
addType :: Name.Name -> ByteString -> State -> State
addType name src state =
  state & types %~ Map.insert name (BB.byteString src)

-- | Add a declaration to the REPL state.
--
-- @since 0.19.1
addDecl :: Name.Name -> ByteString -> State -> State
addDecl name src state =
  state & decls %~ Map.insert name (BB.byteString src)

-- | Generate auto-completion suggestions.
--
-- Provides completions for imports, types, declarations, and commands
-- based on the current input prefix.
--
-- @since 0.19.1
lookupCompletions :: String -> M [Completion]
lookupCompletions string = do
  State stImports stTypes stDecls <- State.get
  pure (buildCompletions string stImports stTypes stDecls)
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
-- @since 0.19.2
commands :: Map Name.Name ()
commands =
  Map.fromList
    [ (Name.fromChars ":exit", ()),
      (Name.fromChars ":quit", ()),
      (Name.fromChars ":reset", ()),
      (Name.fromChars ":help", ()),
      (Name.fromChars ":type", ()),
      (Name.fromChars ":t", ()),
      (Name.fromChars ":browse", ())
    ]

-- | Add matching completions from a name map.
--
-- @since 0.19.1
addMatches :: String -> Bool -> Map Name.Name v -> [Completion] -> [Completion]
addMatches string isFinished dict completions =
  Map.foldrWithKey (addMatch string isFinished) completions dict

-- | Add a single completion if it matches the prefix.
--
-- @since 0.19.1
addMatch :: String -> Bool -> Name.Name -> v -> [Completion] -> [Completion]
addMatch string isFinished name _ completions =
  if string `List.isPrefixOf` suggestion
    then Repl.Completion suggestion suggestion isFinished : completions
    else completions
  where
    suggestion = Name.toChars name
