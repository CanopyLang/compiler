{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Terminal error handling and help display system.
--
-- This module provides comprehensive error reporting and help text
-- generation for the Terminal framework. It handles all error
-- conditions that can occur during command-line argument parsing
-- and provides user-friendly error messages with suggestions.
--
-- == Key Functions
--
-- * 'exitWithHelp' - Display detailed help for commands
-- * 'exitWithError' - Display formatted error messages  
-- * 'exitWithUnknown' - Handle unknown command errors with suggestions
-- * 'exitWithOverview' - Display application overview
--
-- == Error Types
--
-- The module defines comprehensive error types:
--
-- * 'Error' - Top-level errors (bad args, bad flags)
-- * 'ArgError' - Argument-specific errors (missing, invalid, extra)
-- * 'FlagError' - Flag-specific errors (value issues, unknown flags)
-- * 'Expectation' - Type expectations for validation
--
-- @since 0.19.1
module Terminal.Error
  ( Error (..),
    ArgError (..),
    FlagError (..),
    Expectation (..),
    exitWithHelp,
    exitWithError,
    exitWithUnknown,
    exitWithOverview,
  )
where

import qualified Data.List as List
import qualified Data.Maybe as Maybe
import GHC.IO.Handle (hIsTerminalDevice)
import Reporting.Suggest as Suggest
import qualified System.Environment as Env
import qualified System.Exit as Exit
import qualified System.FilePath as FP
import System.IO (hPutStrLn, stderr)
import Terminal.Internal
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- ERROR

data Error where
  BadArgs :: [(CompleteArgs a, ArgError)] -> Error
  BadFlag :: FlagError -> Error

data ArgError
  = ArgMissing Expectation
  | ArgBad String Expectation
  | ArgExtras [String]

data FlagError where
  FlagWithValue :: String -> String -> FlagError
  FlagWithBadValue :: String -> String -> Expectation -> FlagError
  FlagWithNoValue :: String -> Expectation -> FlagError
  FlagUnknown :: String -> Flags a -> FlagError

data Expectation = Expectation
  { _type :: String,
    _examples :: IO [String]
  }

-- EXIT

exitSuccess :: [P.Doc] -> IO a
exitSuccess =
  exitWith Exit.ExitSuccess

exitFailure :: [P.Doc] -> IO a
exitFailure =
  exitWith (Exit.ExitFailure 1)

exitWith :: Exit.ExitCode -> [P.Doc] -> IO a
exitWith code docs = do
  isTerminal <- hIsTerminalDevice stderr
  let adjust = if isTerminal then id else P.plain
      formattedDocs = P.vcat $ concatMap (\d -> [d, ""]) docs
  ((P.displayIO stderr . P.renderPretty 1 80) . adjust) formattedDocs
  hPutStrLn stderr ""
  Exit.exitWith code

getExeName :: IO String
getExeName =
  FP.takeFileName <$> Env.getProgName

stack :: [P.Doc] -> P.Doc
stack docs =
  P.vcat $ List.intersperse "" docs

reflow :: String -> P.Doc
reflow string =
  P.fillSep . fmap P.text $ words string

-- HELP

exitWithHelp :: Maybe String -> String -> P.Doc -> Args args -> Flags flags -> IO a
exitWithHelp maybeCommand details example (Args args) flags = do
  command <- toCommand maybeCommand
  let basicDocs = createBasicHelpDocs command details example args
      flagDocs = createFlagHelpDocs flags
  exitSuccess (basicDocs <> flagDocs)

-- | Create basic help documentation components.
createBasicHelpDocs :: String -> String -> P.Doc -> [CompleteArgs a] -> [P.Doc]
createBasicHelpDocs command details example args =
  [ reflow details,
    (P.indent 4 . P.cyan) . P.vcat $ fmap (argsToDoc command) args,
    example
  ]

-- | Create flag documentation if flags exist.
createFlagHelpDocs :: Flags flags -> [P.Doc]
createFlagHelpDocs flags =
  case flagsToDocs flags [] of
    [] -> []
    docs@(_ : _) ->
      [ "You can customize this command with the following flags:",
        P.indent 4 $ stack docs
      ]

toCommand :: Maybe String -> IO String
toCommand maybeCommand =
  do
    exeName <- getExeName
    return $
      case maybeCommand of
        Nothing ->
          exeName
        Just command ->
          exeName <> (" " <> command)

argsToDoc :: String -> CompleteArgs a -> P.Doc
argsToDoc command args =
  case args of
    Exactly required ->
      argsToDocHelp command required []
    Multiple required (Parser _ plural _ _ _) ->
      argsToDocHelp command required ["zero or more " <> plural]
    Optional required (Parser singular _ _ _ _) ->
      argsToDocHelp command required ["optional " <> singular]

argsToDocHelp :: String -> RequiredArgs a -> [String] -> P.Doc
argsToDocHelp command args names =
  case args of
    Done _ ->
      (P.hang 4 . P.hsep) . fmap P.text $ (command : fmap toToken names)
    Required others (Parser singular _ _ _ _) ->
      argsToDocHelp command others (singular : names)

toToken :: String -> String
toToken string =
  "<" <> (fmap (\c -> if c == ' ' then '-' else c) string <> ">")

flagsToDocs :: Flags flags -> [P.Doc] -> [P.Doc]
flagsToDocs flags docs =
  case flags of
    FDone _ ->
      docs
    FMore more flag ->
      let flagDoc =
            P.vcat $
              case flag of
                Flag name (Parser singular _ _ _ _) description ->
                  [ P.dullcyan . P.text $ ("--" <> (name <> ("=" <> toToken singular))),
                    P.indent 4 $ reflow description
                  ]
                OnOff name description ->
                  [ P.dullcyan . P.text $ ("--" <> name),
                    P.indent 4 $ reflow description
                  ]
       in flagsToDocs more (flagDoc : docs)

-- OVERVIEW

exitWithOverview :: P.Doc -> P.Doc -> [Command] -> IO a
exitWithOverview intro outro commands = do
  exeName <- getExeName
  let overviewDocs = createOverviewDocs exeName intro outro commands
  exitSuccess overviewDocs

-- | Create overview documentation sections.
createOverviewDocs :: String -> P.Doc -> P.Doc -> [Command] -> [P.Doc]
createOverviewDocs exeName intro outro commands =
  [ intro,
    "The most common commands are:",
    P.indent 4 . stack $ Maybe.mapMaybe (toSummary exeName) commands,
    "There are a bunch of other commands as well though. Here is a full list:",
    P.indent 4 . P.dullcyan $ toCommandList exeName commands,
    "Adding the --help flag gives a bunch of additional details about each one.",
    outro
  ]

toSummary :: String -> Command -> Maybe P.Doc
toSummary exeName (Command name summary _ _ (Args args) _ _) =
  case summary of
    Uncommon ->
      Nothing
    Common summaryString ->
      Just $
        P.vcat
          [ P.cyan $ argsToDoc (exeName <> (" " <> name)) (case args of arg : _ -> arg; [] -> error "empty args list"),
            P.indent 4 $ reflow summaryString
          ]

toCommandList :: String -> [Command] -> P.Doc
toCommandList exeName commands =
  let names = fmap toName commands
      width = maximum (fmap length names)

      toExample name =
        P.text (exeName <> (" " <> (name <> (replicate (width - length name) ' ' <> " --help"))))
   in P.vcat (fmap toExample names)

-- UNKNOWN

exitWithUnknown :: String -> [String] -> IO a
exitWithUnknown unknown knowns = do
  exeName <- getExeName
  let suggestions = createSuggestions unknown knowns
      errorDocs = createUnknownCommandDocs exeName unknown suggestions
  exitFailure errorDocs

-- | Create suggestions based on similar known commands.
createSuggestions :: String -> [String] -> [P.Doc]
createSuggestions unknown knowns =
  let nearbyKnowns = takeWhile (\(r, _) -> r <= 3) (Suggest.rank unknown id knowns)
  in formatSuggestionText (fmap (toGreen . snd) nearbyKnowns)

-- | Format suggestion text based on number of suggestions.
formatSuggestionText :: [P.Doc] -> [P.Doc]
formatSuggestionText suggestions =
  case suggestions of
    [] -> []
    [nearby] -> ["Try", nearby, "instead?"]
    [a, b] -> ["Try", a, "or", b, "instead?"]
    abcs@(_ : _ : _ : _) ->
      ["Try"] <> (fmap (<> ",") (init abcs) <> ["or", last abcs, "instead?"])

-- | Create error documentation for unknown commands.
createUnknownCommandDocs :: String -> String -> [P.Doc] -> [P.Doc]
createUnknownCommandDocs exeName unknown suggestions =
  [ P.fillSep (["There", "is", "no", toRed unknown, "command."] <> suggestions),
    reflow ("Run `" <> (exeName <> "` with no arguments to get more hints."))
  ]

-- ERROR TO DOC

exitWithError :: Error -> IO a
exitWithError err = do
  errorDocs <- convertErrorToDocs err
  exitFailure errorDocs

-- | Convert different error types to documentation.
convertErrorToDocs :: Error -> IO [P.Doc]
convertErrorToDocs err =
  case err of
    BadFlag flagError ->
      flagErrorToDocs flagError
    BadArgs argErrors ->
      processArgErrors argErrors

-- | Process argument errors into documentation.
processArgErrors :: [(CompleteArgs a, ArgError)] -> IO [P.Doc]
processArgErrors argErrors =
  case argErrors of
    [] ->
      return
        [ reflow "I was not expecting any arguments for this command.",
          reflow "Try removing them?"
        ]
    [(_args, argError)] ->
      argErrorToDocs argError
    _ : _ : _ ->
      let topError = getTopArgError argErrors
      in argErrorToDocs topError

-- | Get the highest priority argument error.
getTopArgError :: [(CompleteArgs a, ArgError)] -> ArgError
getTopArgError argErrors =
  case List.sortOn toArgErrorRank (fmap snd argErrors) of
    topErr : _ -> topErr
    [] -> error "impossible: empty list in _:_:_ pattern"

toArgErrorRank :: ArgError -> Int -- lower is better
toArgErrorRank err =
  case err of
    ArgBad _ _ -> 0
    ArgMissing _ -> 1
    ArgExtras _ -> 2

toGreen :: String -> P.Doc
toGreen str =
  P.green (P.text str)

toYellow :: String -> P.Doc
toYellow str =
  P.yellow (P.text str)

toRed :: String -> P.Doc
toRed str =
  P.red (P.text str)

-- ARG ERROR TO DOC

argErrorToDocs :: ArgError -> IO [P.Doc]
argErrorToDocs argError =
  case argError of
    ArgMissing (Expectation tipe makeExamples) ->
      do
        examples <- makeExamples
        return
          [ P.fillSep
              [ "The",
                "arguments",
                "you",
                "have",
                "are",
                "fine,",
                "but",
                "in",
                "addition,",
                "I",
                "was",
                "expecting",
                "a",
                toYellow (toToken tipe),
                "value.",
                "For",
                "example:"
              ],
            (P.indent 4 . P.green) . P.vcat $ fmap P.text examples
          ]
    ArgBad string (Expectation tipe makeExamples) ->
      do
        examples <- makeExamples
        return
          [ "I am having trouble with this argument:",
            P.indent 4 $ toRed string,
            P.fillSep
              ( [ "It",
                  "is",
                  "supposed",
                  "to",
                  "be",
                  "a",
                  toYellow (toToken tipe),
                  "value,",
                  "like"
                ]
                  <> (if length examples == 1 then ["this:"] else ["one", "of", "these:"])
              ),
            (P.indent 4 . P.green) . P.vcat $ fmap P.text examples
          ]
    ArgExtras extras ->
      let (these, them) =
            case extras of
              [_] -> ("this argument", "it")
              _ -> ("these arguments", "them")
       in return
            [ reflow ("I was not expecting " <> (these <> ":")),
              (P.indent 4 . P.red) . P.vcat $ fmap P.text extras,
              reflow ("Try removing " <> (them <> "?"))
            ]

-- FLAG ERROR TO DOC

flagErrorHelp :: String -> String -> [P.Doc] -> IO [P.Doc]
flagErrorHelp summary original explanation =
  return
    ( [ reflow summary,
        P.indent 4 (toRed original)
      ]
        <> explanation
    )

flagErrorToDocs :: FlagError -> IO [P.Doc]
flagErrorToDocs flagError =
  case flagError of
    FlagWithValue flagName value ->
      flagErrorHelp
        "This on/off flag was given a value:"
        ("--" <> (flagName <> ("=" <> value)))
        [ "An on/off flag either exists or not. It cannot have an equals sign and value.\n\
          \Maybe you want this instead?",
          P.indent 4 . toGreen $ ("--" <> flagName)
        ]
    FlagWithNoValue flagName (Expectation tipe makeExamples) ->
      do
        examples <- makeExamples
        flagErrorHelp
          "This flag needs more information:"
          ("--" <> flagName)
          [ P.fillSep ["It", "needs", "a", toYellow (toToken tipe), "like", "this:"],
            (P.indent 4 . P.vcat) . fmap toGreen $
              ( case take 4 examples of
                  [] ->
                    ["--" <> (flagName <> ("=" <> toToken tipe))]
                  _ : _ ->
                    fmap (\example -> "--" <> (flagName <> ("=" <> example))) examples
              )
          ]
    FlagWithBadValue flagName badValue (Expectation tipe makeExamples) ->
      do
        examples <- makeExamples
        flagErrorHelp
          "This flag was given a bad value:"
          ("--" <> (flagName <> ("=" <> badValue)))
          [ P.fillSep
              [ "I",
                "need",
                "a",
                "valid",
                toYellow (toToken tipe),
                "value.",
                "For",
                "example:"
              ],
            (P.indent 4 . P.vcat) . fmap toGreen $
              ( case take 4 examples of
                  [] ->
                    ["--" <> (flagName <> ("=" <> toToken tipe))]
                  _ : _ ->
                    fmap (\example -> "--" <> (flagName <> ("=" <> example))) examples
              )
          ]
    FlagUnknown unknown flags ->
      flagErrorHelp
        "I do not recognize this flag:"
        unknown
        ( let unknownName = takeWhile ('=' /=) (dropWhile ('-' ==) unknown)
           in case getNearbyFlags unknownName flags [] of
                [] ->
                  []
                [thisOne] ->
                  [ P.fillSep ["Maybe", "you", "want", P.green thisOne, "instead?"]
                  ]
                suggestions ->
                  [ P.fillSep ["Maybe", "you", "want", "one", "of", "these", "instead?"],
                    P.indent 4 . P.green $ P.vcat suggestions
                  ]
        )

getNearbyFlags :: String -> Flags a -> [(Int, String)] -> [P.Doc]
getNearbyFlags unknown flags unsortedFlags =
  case flags of
    FMore more flag ->
      getNearbyFlags unknown more (getNearbyFlagsHelp unknown flag : unsortedFlags)
    FDone _ ->
      fmap
        (P.text . snd)
        ( List.sortOn fst $
            case filter (\(d, _) -> d < 3) unsortedFlags of
              [] ->
                unsortedFlags
              nearbyUnsortedFlags ->
                nearbyUnsortedFlags
        )

getNearbyFlagsHelp :: String -> Flag a -> (Int, String)
getNearbyFlagsHelp unknown flag =
  case flag of
    OnOff flagName _ ->
      ( Suggest.distance unknown flagName,
        "--" <> flagName
      )
    Flag flagName (Parser singular _ _ _ _) _ ->
      ( Suggest.distance unknown flagName,
        "--" <> (flagName <> ("=" <> toToken singular))
      )
