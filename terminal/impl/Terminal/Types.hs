{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core data types and lens definitions for the Terminal framework.
--
-- This module defines all fundamental data structures used throughout
-- the Terminal framework, including commands, arguments, flags, and
-- parsers. It provides comprehensive lens support for all record types
-- and maintains type safety through GADTs for complex parsing scenarios.
--
-- == Type Hierarchy
--
-- * 'Command' - Complete command definition with metadata and handler
-- * 'Args' and 'Flags' - Argument and flag parsing specifications
-- * 'Parser' - Generic parsing functions with validation and completion
-- * 'AppConfig' - Application-level configuration with lenses
--
-- == Design Principles
--
-- The type system uses GADTs to ensure compile-time safety while
-- maintaining flexibility for complex CLI patterns. All record types
-- include comprehensive lens definitions for functional updates.
--
-- == Usage Examples
--
-- @
-- import Control.Lens ((&), (.~), (^.))
-- import qualified Terminal.Types as Types
--
-- -- Create configuration with lenses
-- config <- Types.defaultAppConfig 
--   & Types.acIntro .~ "My App"
--   & Types.acOutro .~ "Thank you"
--
-- -- Access configuration
-- appName = config ^. Types.acIntro
-- @
--
-- @since 0.19.1
module Terminal.Types
  ( -- * Application Configuration
    AppConfig (..),
    defaultAppConfig,
    -- * Lenses for AppConfig
    acIntro,
    acOutro,
    acCommands,
    
    -- * Type Aliases
    CommandArgs,
    CommandFlags,
    
    -- * Command Types
    Command (..),
    CommandMeta (..),
    Summary (..),
    defaultCommandMeta,
    -- * Lenses for Command
    cmdName,
    cmdMeta,
    cmdHandler,
    -- * Lenses for CommandMeta
    cmSummary,
    cmDetails,
    cmExample,
    cmArgs,
    cmFlags,
    
    -- * Parser Types  
    Parser (..),
    ParserConfig (..),
    defaultParserConfig,
    -- * Lenses for Parser
    pcSingular,
    pcPlural, 
    pcParser,
    pcSuggest,
    pcExamples,
    
    -- * Argument Types
    Args (..),
    CompleteArgs (..),
    RequiredArgs (..),
    
    -- * Flag Types
    Flags (..),
    Flag (..),
    FlagConfig (..),
    defaultFlagConfig,
    -- * Lenses for FlagConfig
    fcName,
    fcParser,
    fcDescription,
    
    -- * Completion Types
    CompletionContext (..),
    SuggestionIndex (..),
    -- * Lenses for CompletionContext
    ccIndex,
    ccChunks,
    ccLine,
    ccPoint,
  )
where

import Control.Lens (makeLenses)
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Application-level configuration with introduction, outro, and commands.
data AppConfig = AppConfig
  { _acIntro :: !Doc.Doc
  , _acOutro :: !Doc.Doc  
  , _acCommands :: ![Command]
  }

-- | Create default application configuration.
defaultAppConfig :: AppConfig
defaultAppConfig = AppConfig
  { _acIntro = Doc.empty
  , _acOutro = Doc.empty
  , _acCommands = []
  }

-- | Complete command definition with metadata and execution handler.
data Command = Command
  { _cmdName :: !String
  , _cmdMeta :: !CommandMeta
  , _cmdHandler :: !(CommandArgs -> CommandFlags -> IO ())
  }

-- | Command metadata including documentation and argument specifications.
data CommandMeta = CommandMeta
  { _cmSummary :: !Summary
  , _cmDetails :: !String
  , _cmExample :: !Doc.Doc
  , _cmArgs :: !CommandArgs
  , _cmFlags :: !CommandFlags
  }

-- | Create default command metadata.
defaultCommandMeta :: CommandMeta
defaultCommandMeta = CommandMeta
  { _cmSummary = Uncommon
  , _cmDetails = ""
  , _cmExample = Doc.empty
  , _cmArgs = ()
  , _cmFlags = ()
  }

-- | Command summary for help display.
-- 'Common' commands show in overview, 'Uncommon' commands require --help.
data Summary 
  = Common !String
  | Uncommon
  deriving (Eq, Show)

-- | Generic parser with validation, suggestions, and examples.
data Parser a = Parser
  { _parserConfig :: !(ParserConfig a)
  }

-- | Parser configuration with all parsing functions.
data ParserConfig a = ParserConfig
  { _pcSingular :: !String
  , _pcPlural :: !String
  , _pcParser :: !(String -> Maybe a)
  , _pcSuggest :: !(String -> IO [String])
  , _pcExamples :: !(String -> IO [String])
  }

-- | Create default parser configuration.
defaultParserConfig :: ParserConfig a
defaultParserConfig = ParserConfig
  { _pcSingular = "value"
  , _pcPlural = "values"
  , _pcParser = const Nothing
  , _pcSuggest = const (pure [])
  , _pcExamples = const (pure [])
  }

-- | Argument parsing specification using GADTs for type safety.
data Args a where
  ArgsExact :: RequiredArgs a -> Args a
  ArgsOptional :: RequiredArgs (Maybe a -> b) -> Parser a -> Args b
  ArgsMultiple :: RequiredArgs ([a] -> b) -> Parser a -> Args b
  ArgsOneOf :: [Args a] -> Args a

-- | Complete argument specification alternatives.
data CompleteArgs args where
  Exactly :: RequiredArgs args -> CompleteArgs args
  Multiple :: RequiredArgs ([a] -> args) -> Parser a -> CompleteArgs args
  Optional :: RequiredArgs (Maybe a -> args) -> Parser a -> CompleteArgs args

-- | Required argument chain using applicative-style composition.
data RequiredArgs a where
  Done :: a -> RequiredArgs a
  Required :: RequiredArgs (a -> b) -> Parser a -> RequiredArgs b

-- | Flag parsing specification using GADTs for type safety.
data Flags a where
  FDone :: a -> Flags a
  FMore :: Flags (a -> b) -> Flag a -> Flags b

-- | Individual flag definition with parsing and documentation.
data Flag a where
  FlagValue :: FlagConfig a -> Flag (Maybe a)
  FlagOnOff :: String -> String -> Flag Bool

-- | Flag configuration with name, parser, and documentation.
data FlagConfig a = FlagConfig
  { _fcName :: !String
  , _fcParser :: !(Parser a)
  , _fcDescription :: !String
  }

-- | Create default flag configuration.
defaultFlagConfig :: FlagConfig a
defaultFlagConfig = FlagConfig
  { _fcName = ""
  , _fcParser = Parser defaultParserConfig
  , _fcDescription = ""
  }

-- | Shell completion context with index and command line information.
data CompletionContext = CompletionContext
  { _ccIndex :: !SuggestionIndex
  , _ccChunks :: ![String]
  , _ccLine :: !String
  , _ccPoint :: !Int
  }

-- | Suggestion index for completion context.
newtype SuggestionIndex = SuggestionIndex Int
  deriving (Eq, Show)

-- Type aliases for command arguments and flags
type CommandArgs = ()
type CommandFlags = ()

-- Generate lenses for all record types
makeLenses ''AppConfig
makeLenses ''Command
makeLenses ''CommandMeta
makeLenses ''ParserConfig
makeLenses ''FlagConfig  
makeLenses ''CompletionContext

-- Functor instance for Parser
instance Functor Parser where
  fmap :: (a -> b) -> Parser a -> Parser b
  fmap f (Parser config) = Parser $ config 
    { _pcParser = fmap f . _pcParser config
    }