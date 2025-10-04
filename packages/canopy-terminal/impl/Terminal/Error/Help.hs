{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Help text generation and display system for Terminal framework.
--
-- This module handles the generation of comprehensive help documentation
-- for commands, including argument descriptions, flag documentation,
-- and usage examples. It provides consistent formatting and structure
-- across all Terminal help displays.
--
-- == Key Features
--
-- * Structured help generation for commands with args and flags
-- * Consistent formatting and color scheme for readability
-- * Automatic usage pattern generation from argument specifications
-- * Overview generation for multi-command applications
--
-- == Help Structure
--
-- Help documentation follows a standard structure:
--
-- 1. Command description and details
-- 2. Usage patterns with argument placeholders
-- 3. Flag documentation with examples
-- 4. Usage examples and additional guidance
--
-- == Usage Examples
--
-- @
-- -- Generate help for a command
-- helpDocs <- generateCommandHelp "build" details example args flags
-- exitWithHelp helpDocs
--
-- -- Create application overview
-- overviewDocs <- generateAppOverview intro outro commands
-- exitWithOverview overviewDocs
-- @
--
-- @since 0.19.1
module Terminal.Error.Help
  ( -- * Main Help Functions
    generateCommandHelp,
    generateAppOverview,

    -- * Command Help Components
    createUsagePattern,
    createFlagDocumentation,
    createArgumentDocumentation,

    -- * Overview Functions
    createCommandSummary,
    createCompleteCommandList,

    -- * Utilities
    getExecutableName,
    formatCommandName,
  )
where

import qualified Data.Maybe as Maybe
import qualified System.Environment as Env
import qualified System.FilePath as FilePath
import Terminal.Error.Formatting
  ( createStackedDocs,
    formatCommandList,
    reflowText,
    toCyanText,
  )
import Terminal.Internal
  ( Args (..),
    Command (..),
    CompleteArgs (..),
    Flag (..),
    Flags (..),
    Parser (..),
    RequiredArgs (..),
    Summary (..),
  )
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

-- | Generate complete help documentation for a command.
--
-- Creates comprehensive help text including description, usage patterns,
-- argument documentation, and flag information.
--
-- ==== Examples
--
-- >>> helpDocs <- generateCommandHelp (Just "build") details example args flags
-- >>> length helpDocs >= 3
-- True
--
-- @since 0.19.1
generateCommandHelp :: Maybe String -> String -> Doc.Doc -> Args args -> Flags flags -> IO [Doc.Doc]
generateCommandHelp maybeCommand details example args flags = do
  commandName <- formatCommandName maybeCommand
  let usageDocs = createArgumentDocumentation commandName args
      flagDocs = createFlagDocumentation flags
  return (createHelpStructure details example usageDocs flagDocs)

-- | Create structured help documentation.
--
-- @since 0.19.1
createHelpStructure :: String -> Doc.Doc -> [Doc.Doc] -> [Doc.Doc] -> [Doc.Doc]
createHelpStructure details example usageDocs flagDocs =
  [ reflowText details,
    createStackedDocs usageDocs,
    example
  ]
    ++ flagDocs

-- | Generate application overview with command list.
--
-- Creates overview documentation for multi-command applications
-- showing common commands and complete command list.
--
-- @since 0.19.1
generateAppOverview :: Doc.Doc -> Doc.Doc -> [Command] -> IO [Doc.Doc]
generateAppOverview intro outro commands = do
  exeName <- getExecutableName
  let commonCommands = createCommonCommandList exeName commands
      allCommands = createCompleteCommandList exeName commands
  return (createOverviewStructure intro outro commonCommands allCommands)

-- | Create overview structure with all sections.
--
-- @since 0.19.1
createOverviewStructure :: Doc.Doc -> Doc.Doc -> [Doc.Doc] -> Doc.Doc -> [Doc.Doc]
createOverviewStructure intro outro commonCommands allCommands =
  [ intro,
    "The most common commands are:",
    Doc.indent 4 (createStackedDocs commonCommands),
    "There are a bunch of other commands as well though. Here is a full list:",
    Doc.indent 4 allCommands,
    "Adding the --help flag gives a bunch of additional details about each one.",
    outro
  ]

-- | Create argument usage documentation.
--
-- @since 0.19.1
createArgumentDocumentation :: String -> Args args -> [Doc.Doc]
createArgumentDocumentation commandName (Args argsList) =
  map (createUsagePattern commandName) argsList

-- | Create usage pattern for argument specification.
--
-- Converts argument specifications into formatted usage patterns
-- with proper token formatting and color coding.
--
-- @since 0.19.1
createUsagePattern :: String -> CompleteArgs a -> Doc.Doc
createUsagePattern commandName args =
  case args of
    Exactly required ->
      createRequiredPattern commandName required []
    Multiple required (Parser _ plural _ _ _) ->
      createRequiredPattern commandName required ["zero or more " ++ plural]
    Optional required (Parser singular _ _ _ _) ->
      createRequiredPattern commandName required ["optional " ++ singular]

-- | Create pattern for required arguments.
--
-- @since 0.19.1
createRequiredPattern :: String -> RequiredArgs a -> [String] -> Doc.Doc
createRequiredPattern commandName args extraTokens =
  case args of
    Done _ ->
      formatUsageLine commandName extraTokens
    Required others (Parser singular _ _ _ _) ->
      createRequiredPattern commandName others (singular : extraTokens)

-- | Format complete usage line with command and tokens.
--
-- @since 0.19.1
formatUsageLine :: String -> [String] -> Doc.Doc
formatUsageLine commandName tokens =
  Doc.hang 4 . Doc.hsep $
    map Doc.text (commandName : map formatArgumentToken tokens)

-- | Format argument token for usage display.
--
-- @since 0.19.1
formatArgumentToken :: String -> String
formatArgumentToken token =
  "<" ++ map replaceSpace token ++ ">"
  where
    replaceSpace ' ' = '-'
    replaceSpace c = c

-- | Create flag documentation if flags exist.
--
-- @since 0.19.1
createFlagDocumentation :: Flags flags -> [Doc.Doc]
createFlagDocumentation flags =
  case collectFlagDocs flags [] of
    [] -> []
    flagDocs ->
      [ "You can customize this command with the following flags:",
        Doc.indent 4 (createStackedDocs flagDocs)
      ]

-- | Collect flag documentation recursively.
--
-- @since 0.19.1
collectFlagDocs :: Flags flags -> [Doc.Doc] -> [Doc.Doc]
collectFlagDocs flags docs =
  case flags of
    FDone _ -> docs
    FMore more flag ->
      let flagDoc = createFlagDoc flag
       in collectFlagDocs more (flagDoc : docs)

-- | Create documentation for individual flag.
--
-- @since 0.19.1
createFlagDoc :: Flag a -> Doc.Doc
createFlagDoc flag =
  case flag of
    Flag name (Parser singular _ _ _ _) description ->
      Doc.vcat
        [ toCyanText ("--" ++ name ++ "=" ++ formatArgumentToken singular),
          Doc.indent 4 (reflowText description)
        ]
    OnOff name description ->
      Doc.vcat
        [ toCyanText ("--" ++ name),
          Doc.indent 4 (reflowText description)
        ]

-- | Create command summary for overview.
--
-- @since 0.19.1
createCommandSummary :: String -> Command -> Maybe Doc.Doc
createCommandSummary exeName (Command name summary _ _ (Args args) _ _) =
  case summary of
    Uncommon -> Nothing
    Common summaryText ->
      let usagePattern = case args of
            arg : _ -> createUsagePattern (exeName ++ " " ++ name) arg
            [] -> Doc.text (exeName ++ " " ++ name)
       in Just $
            Doc.vcat
              [ Doc.cyan usagePattern,
                Doc.indent 4 (reflowText summaryText)
              ]

-- | Create list of common commands.
--
-- @since 0.19.1
createCommonCommandList :: String -> [Command] -> [Doc.Doc]
createCommonCommandList exeName commands =
  Maybe.mapMaybe (createCommandSummary exeName) commands

-- | Create complete command list with help text.
--
-- @since 0.19.1
createCompleteCommandList :: String -> [Command] -> Doc.Doc
createCompleteCommandList exeName commands =
  let commandNames = map extractCommandName commands
   in formatCommandList exeName commandNames

-- | Extract command name from Command structure.
--
-- @since 0.19.1
extractCommandName :: Command -> String
extractCommandName (Command name _ _ _ _ _ _) = name

-- | Get executable name for help text.
--
-- @since 0.19.1
getExecutableName :: IO String
getExecutableName = FilePath.takeFileName <$> Env.getProgName

-- | Format command name with executable.
--
-- @since 0.19.1
formatCommandName :: Maybe String -> IO String
formatCommandName maybeCommand = do
  exeName <- getExecutableName
  return $ case maybeCommand of
    Nothing -> exeName
    Just command -> exeName ++ " " ++ command
