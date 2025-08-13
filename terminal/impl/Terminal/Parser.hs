{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Argument and flag parsing utilities for Terminal framework.
--
-- This module provides high-level functions for creating and working
-- with argument and flag parsers. It offers both simple convenience
-- functions and sophisticated compositional parsing capabilities
-- for complex command-line interfaces.
--
-- == Parser Creation
--
-- * 'createParser' - Build custom parsers with validation and completion
-- * 'stringParser' - Simple string argument parser
-- * 'intParser' - Integer argument parser with validation
-- * 'fileParser' - File path parser with completion
--
-- == Argument Builders
--
-- * 'required', 'optional' - Basic argument specifications
-- * 'oneOrMore', 'zeroOrMore' - Repeating argument patterns
-- * 'oneOf' - Alternative argument patterns
--
-- == Flag Builders
--
-- * 'flag' - Value flag with parser
-- * 'onOffFlag' - Boolean on/off flag
-- * 'flagChain' - Compose multiple flags
--
-- == Usage Examples
--
-- @
-- import qualified Terminal.Parser as Parser
--
-- -- Simple parsers
-- nameArg = Parser.required (Parser.stringParser "name" "project name")
-- countFlag = Parser.flag "count" (Parser.intParser 1 100) "number of items"
--
-- -- Complex combinations
-- buildArgs = Parser.oneOf
--   [ Parser.required (Parser.fileParser ["hs"])
--   , Parser.zeroOrMore (Parser.stringParser "module" "module name")
--   ]
-- @
--
-- @since 0.19.1
module Terminal.Parser
  ( -- * Parser Creation
    createParser,
    createParserWithExamples,
    
    -- * Basic Parsers
    stringParser,
    intParser,
    floatParser,
    boolParser,
    fileParser,
    
    -- * Argument Builders
    required,
    optional,
    zeroOrMore,
    oneOrMore,
    oneOf,
    noArgs,
    
    -- * Argument Composition
    require0,
    require1,
    require2,
    require3,
    require4,
    require5,
    
    -- * Flag Builders
    flag,
    onOffFlag,
    noFlags,
    flagChain,
    
    -- * Parser Combinators
    mapParser,
    validateParser,
    suggestFiles,
  )
where

import qualified Data.List as List
import qualified System.Directory as Directory
import qualified System.FilePath as FilePath
import Terminal.Internal
  ( Args (..),
    Flag (..),
    Flags (..),
    Parser (..),
    CompleteArgs (..),
    RequiredArgs (..)
  )
import qualified Text.Read as Read

-- | Create custom parser with validation and completion.
--
-- @since 0.19.1
createParser
  :: String
  -- ^ Singular form (e.g., "file")
  -> String
  -- ^ Plural form (e.g., "files")
  -> (String -> Maybe a)
  -- ^ Parsing function
  -> (String -> IO [String])
  -- ^ Suggestion function
  -> (String -> IO [String])
  -- ^ Examples function
  -> Parser a
  -- ^ Complete parser
createParser singular plural parseFunc suggestFunc exampleFunc =
  Parser
    { _singular = singular
    , _plural = plural
    , _parser = parseFunc
    , _suggest = suggestFunc
    , _examples = exampleFunc
    }

-- | Create parser with dynamic examples (same as createParser).
--
-- @since 0.19.1
createParserWithExamples
  :: String
  -- ^ Singular form
  -> String
  -- ^ Plural form
  -> (String -> Maybe a)
  -- ^ Parsing function
  -> (String -> IO [String])
  -- ^ Suggestion function
  -> (String -> IO [String])
  -- ^ Examples function
  -> Parser a
  -- ^ Complete parser
createParserWithExamples = createParser

-- | Simple string parser with no validation.
--
-- @since 0.19.1
stringParser
  :: String
  -- ^ Singular form
  -> String
  -- ^ Description for help
  -> Parser String
  -- ^ String parser
stringParser singular _description =
  createParser singular (singular ++ "s") Just (const (pure [])) (const (pure []))

-- | Integer parser with optional bounds validation.
--
-- @since 0.19.1
intParser
  :: Int
  -- ^ Minimum value
  -> Int
  -- ^ Maximum value
  -> Parser Int
  -- ^ Integer parser
intParser minVal maxVal =
  createParser "number" "numbers" parseWithBounds (const (pure [])) (const (pure examples))
  where
    parseWithBounds input = do
      value <- Read.readMaybe input
      if value >= minVal && value <= maxVal
        then Just value
        else Nothing
    
    examples = [show minVal, show maxVal, show ((minVal + maxVal) `div` 2)]

-- | Float parser with validation.
--
-- @since 0.19.1
floatParser :: Parser Float
floatParser =
  createParser "number" "numbers" Read.readMaybe (const (pure [])) (const (pure ["1.0", "2.5"]))

-- | Boolean parser accepting common boolean representations.
--
-- @since 0.19.1
boolParser :: Parser Bool
boolParser =
  createParser "boolean" "booleans" parseBool suggestBool (const (pure examples))
  where
    parseBool input = case input of
      "true" -> Just True
      "false" -> Just False
      "yes" -> Just True
      "no" -> Just False
      "1" -> Just True
      "0" -> Just False
      _ -> Nothing
    
    suggestBool _ = pure ["true", "false", "yes", "no"]
    examples = ["true", "false"]

-- | File parser with extension filtering and completion.
--
-- @since 0.19.1
fileParser
  :: [String]
  -- ^ Allowed extensions (empty for any)
  -> Parser String
  -- ^ File path parser
fileParser extensions =
  createParser "file" "files" Just (suggestFiles extensions) (const (pure []))

-- | Required argument specification.
--
-- @since 0.19.1
required :: Parser a -> Args a
required parser = Args [Exactly (Required (Done id) parser)]

-- | Optional argument specification.
--
-- @since 0.19.1
optional :: Parser a -> Args (Maybe a)
optional parser = Args [Optional (Done id) parser]

-- | Zero or more arguments specification.
--
-- @since 0.19.1
zeroOrMore :: Parser a -> Args [a]
zeroOrMore parser = Args [Multiple (Done id) parser]

-- | One or more arguments specification.
--
-- @since 0.19.1
oneOrMore :: Parser a -> Args (a, [a])
oneOrMore parser = Args [Multiple (Done (\xs -> (head xs, tail xs))) parser]

-- | Alternative argument patterns.
--
-- @since 0.19.1
oneOf :: [Args a] -> Args a
oneOf argsList = Args (concatMap (\(Args a) -> a) argsList)

-- | No arguments specification.
--
-- @since 0.19.1
noArgs :: Args ()
noArgs = Args [Exactly (Done ())]

-- | Exactly zero arguments.
--
-- @since 0.19.1
require0 :: args -> Args args
require0 value = Args [Exactly (Done value)]

-- | Exactly one argument.
--
-- @since 0.19.1
require1 :: (a -> args) -> Parser a -> Args args
require1 func parser = Args [Exactly (Required (Done func) parser)]

-- | Exactly two arguments.
--
-- @since 0.19.1
require2 :: (a -> b -> args) -> Parser a -> Parser b -> Args args
require2 func parserA parserB = 
  Args [Exactly (Required (Required (Done func) parserA) parserB)]

-- | Exactly three arguments.
--
-- @since 0.19.1
require3 :: (a -> b -> c -> args) -> Parser a -> Parser b -> Parser c -> Args args
require3 func parserA parserB parserC =
  Args [Exactly (Required (Required (Required (Done func) parserA) parserB) parserC)]

-- | Exactly four arguments.
--
-- @since 0.19.1
require4 
  :: (a -> b -> c -> d -> args) 
  -> Parser a -> Parser b -> Parser c -> Parser d 
  -> Args args
require4 func parserA parserB parserC parserD =
  Args [Exactly $ Required 
    (Required (Required (Required (Done func) parserA) parserB) parserC) 
    parserD]

-- | Exactly five arguments.
--
-- @since 0.19.1
require5 
  :: (a -> b -> c -> d -> e -> args) 
  -> Parser a -> Parser b -> Parser c -> Parser d -> Parser e
  -> Args args
require5 func parserA parserB parserC parserD parserE =
  Args [Exactly $ Required 
    (Required (Required (Required (Required (Done func) parserA) parserB) parserC) parserD)
    parserE]

-- | Create flag with value parser.
--
-- @since 0.19.1
flag
  :: String
  -- ^ Flag name
  -> Parser a
  -- ^ Value parser
  -> String
  -- ^ Description
  -> Flag (Maybe a)
  -- ^ Flag specification
flag name parser description = Flag name parser description

-- | Create boolean on/off flag.
--
-- @since 0.19.1
onOffFlag
  :: String
  -- ^ Flag name
  -> String
  -- ^ Description
  -> Flag Bool
  -- ^ Boolean flag specification
onOffFlag name description = OnOff name description

-- | No flags specification.
--
-- @since 0.19.1
noFlags :: Flags ()
noFlags = FDone ()

-- | Chain multiple flags together.
--
-- @since 0.19.1
flagChain :: Flags (a -> b) -> Flag a -> Flags b
flagChain = FMore

-- | Transform parser output with function.
--
-- @since 0.19.1
mapParser :: (a -> b) -> Parser a -> Parser b
mapParser func parser = parser { _parser = fmap func . _parser parser }

-- | Add validation to existing parser.
--
-- @since 0.19.1
validateParser :: (a -> Bool) -> Parser a -> Parser a
validateParser predicate parser = parser
  { _parser = \input -> do
      value <- _parser parser input
      if predicate value then Just value else Nothing
  }

-- | Suggest files with extension filtering.
--
-- @since 0.19.1
suggestFiles
  :: [String]
  -- ^ Allowed extensions
  -> String
  -- ^ Current input
  -> IO [String]
  -- ^ File suggestions
suggestFiles extensions input = do
  let (dir, prefix) = FilePath.splitFileName input
  contents <- Directory.getDirectoryContents dir
  validFiles <- filterValidFiles extensions prefix dir contents
  pure validFiles

-- Helper Functions

-- | Filter directory contents for valid file suggestions.
filterValidFiles
  :: [String]
  -- ^ Allowed extensions
  -> String
  -- ^ Filename prefix
  -> FilePath
  -- ^ Directory path
  -> [FilePath]
  -- ^ Directory contents
  -> IO [FilePath]
  -- ^ Valid suggestions
filterValidFiles extensions prefix dir contents = do
  let candidates = filter (List.isPrefixOf prefix) contents
  validCandidates <- mapM (checkFileCandidate extensions dir) candidates
  pure $ concat validCandidates

-- | Check if file candidate is valid suggestion.
checkFileCandidate
  :: [String]
  -- ^ Allowed extensions
  -> FilePath
  -- ^ Directory path
  -> FilePath
  -- ^ Candidate filename
  -> IO [FilePath]
  -- ^ Valid paths (empty or singleton)
checkFileCandidate extensions dir candidate = do
  let fullPath = dir FilePath.</> candidate
  isDir <- Directory.doesDirectoryExist fullPath
  if isDir
    then pure [candidate ++ "/"]
    else if hasValidExtension candidate extensions
      then pure [candidate]
      else pure []

-- | Check if file has valid extension.
hasValidExtension :: FilePath -> [String] -> Bool
hasValidExtension _ [] = True  -- No restriction
hasValidExtension path extensions = 
  FilePath.takeExtension path `elem` extensions