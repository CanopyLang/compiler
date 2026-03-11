
-- | REPL command parsing and input categorization.
--
-- This module handles parsing user input into appropriate categories,
-- including commands, imports, type definitions, declarations, and
-- expressions. It also manages multi-line input continuation.
--
-- @since 0.19.1
module Repl.Commands
  ( -- * Input Categorization
    categorize,

    -- * Input Reading
    stripLegacyBackslash,
    renderPrefill,

    -- * Help System
    toHelpMessage,
  )
where

import qualified AST.Source as Src
import Data.ByteString (ByteString)
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Canopy.Data.Name as Name
import qualified Parse.Declaration as PD
import qualified Parse.Expression as PE
import qualified Parse.Module as PM
import qualified Parse.Primitives as Parse
import qualified Parse.Space as PS
import qualified Parse.Type as PT
import qualified Parse.Variable as PV
import Repl.Types
  ( CategorizedInput (..),
    Input (..),
    Lines (..),
    Prefill (..),
    endsWithBlankLine,
    getFirstLine,
    isSingleLine,
    linesToByteString,
  )
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Error.Syntax as SyntaxError
import qualified Reporting.Render.Code as Code

-- | Categorize user input into appropriate action.
--
-- Determines whether input is complete or needs more inputLines,
-- and what type of input it represents.
--
-- @since 0.19.1
categorize :: Lines -> CategorizedInput
categorize inputLines
  | isBlank inputLines = Done Skip
  | startsWithColon inputLines = Done (toCommand inputLines)
  | startsWithKeyword "import" inputLines = attemptImport inputLines
  | otherwise = attemptDeclOrExpr inputLines

-- | Check if inputLines are blank or whitespace only.
--
-- @since 0.19.1
isBlank :: Lines -> Bool
isBlank (Lines prev rev) = null rev && all (== ' ') prev

-- | Attempt to parse import statement.
--
-- @since 0.19.1
attemptImport :: Lines -> CategorizedInput
attemptImport inputLines =
  either failHandler successHandler parseResult
  where
    src = linesToByteString inputLines
    parser = Parse.specialize (\_ _ _ -> ()) PM.chompImport
    parseResult = Parse.fromByteString parser (\_ _ -> ()) src

    successHandler (Src.Import (Ann.At _ name) _ _ _) = Done (Import name src)
    failHandler () = ifFail inputLines (Import (Name.fromChars "ERR") src)

-- | Handle parsing failure with continuation logic.
--
-- @since 0.19.1
ifFail :: Lines -> Input -> CategorizedInput
ifFail inputLines input =
  if endsWithBlankLine inputLines
    then Done input
    else Continue Indent

-- | Handle successful parsing with completion logic.
--
-- @since 0.19.1
ifDone :: Lines -> Input -> CategorizedInput
ifDone inputLines input =
  if isSingleLine inputLines || endsWithBlankLine inputLines
    then Done input
    else Continue Indent

-- | Attempt to parse declaration or expression.
--
-- @since 0.19.1
attemptDeclOrExpr :: Lines -> CategorizedInput
attemptDeclOrExpr inputLines =
  either handleDeclFailure handleDeclSuccess declResult
  where
    handleDeclFailure = handleDeclError inputLines src exprParser
    handleDeclSuccess (decl, _) = processDeclaration inputLines src decl
    src = linesToByteString inputLines
    exprParser = Parse.specialize (toExprPosition src) PE.expression
    declParser = Parse.specialize (toDeclPosition src) PD.declaration
    declResult = Parse.fromByteString declParser (,) src

-- | Process successfully parsed declaration.
--
-- @since 0.19.1
processDeclaration :: Lines -> ByteString -> PD.Decl -> CategorizedInput
processDeclaration inputLines src decl =
  case decl of
    PD.Value _ (Ann.At _ (Src.Value (Ann.At _ name) _ _ _ _)) ->
      ifDone inputLines (Decl name src)
    PD.Union _ (Ann.At _ (Src.Union (Ann.At _ name) _ _ _ _)) ->
      ifDone inputLines (Type name src)
    PD.Alias _ (Ann.At _ (Src.Alias (Ann.At _ name) _ _ _ _ _)) ->
      ifDone inputLines (Type name src)
    PD.Port _ _ -> Done Port
    PD.Ability _ (Ann.At _ (Src.AbilityDecl (Ann.At _ name) _ _ _)) ->
      ifDone inputLines (Type name src)
    PD.Impl _ (Ann.At _ (Src.ImplDecl (Ann.At _ abilityName) _ _)) ->
      ifDone inputLines (Decl abilityName src)

-- | Handle declaration parsing error.
--
-- @since 0.19.1
handleDeclError :: Lines -> ByteString -> Parse.Parser (Parse.Row, Parse.Col) (Src.Expr, a) -> (Parse.Row, Parse.Col) -> CategorizedInput
handleDeclError inputLines src exprParser declPosition
  | startsWithKeyword "type" inputLines = ifFail inputLines (Type (Name.fromChars "ERR") src)
  | startsWithKeyword "port" inputLines = Done Port
  | otherwise = tryParseExpression inputLines src exprParser declPosition

-- | Try parsing as expression after declaration failed.
--
-- @since 0.19.1
tryParseExpression :: Lines -> ByteString -> Parse.Parser (Parse.Row, Parse.Col) (Src.Expr, a) -> (Parse.Row, Parse.Col) -> CategorizedInput
tryParseExpression inputLines src exprParser declPosition =
  case Parse.fromByteString exprParser (,) src of
    Right _ -> ifDone inputLines (Expr src)
    Left exprPosition ->
      if exprPosition >= declPosition
        then ifFail inputLines (Expr src)
        else handleAnnotation inputLines src

-- | Handle type annotation parsing.
--
-- @since 0.19.1
handleAnnotation :: Lines -> ByteString -> CategorizedInput
handleAnnotation inputLines src =
  case Parse.fromByteString annotation (\_ _ -> ()) src of
    Right name -> Continue (DefStart name)
    Left () -> ifFail inputLines (Decl (Name.fromChars "ERR") src)

-- | Check if input starts with colon (command).
--
-- @since 0.19.1
startsWithColon :: Lines -> Bool
startsWithColon inputLines =
  case dropWhile (== ' ') (getFirstLine inputLines) of
    [] -> False
    c : _ -> c == ':'

-- | Parse command from input.
--
-- @since 0.19.1
toCommand :: Lines -> Input
toCommand inputLines =
  parseCommand (drop 1 (dropWhile (== ' ') (getFirstLine inputLines)))

-- | Dispatch to the appropriate command based on the command name.
--
-- @since 0.19.2
parseCommand :: String -> Input
parseCommand "reset" = Reset
parseCommand "exit" = Exit
parseCommand "quit" = Exit
parseCommand "help" = Help Nothing
parseCommand cmdLine
  | "type " `List.isPrefixOf` cmdLine = TypeOf (dropWhile (== ' ') (drop 5 cmdLine))
  | "t " `List.isPrefixOf` cmdLine = TypeOf (dropWhile (== ' ') (drop 2 cmdLine))
  | "browse" == cmdLine = Browse Nothing
  | "browse " `List.isPrefixOf` cmdLine = Browse (Just (dropWhile (== ' ') (drop 7 cmdLine)))
  | otherwise = Help (Just (takeWhile (/= ' ') cmdLine))

-- | Check if input starts with specific keyword.
--
-- @since 0.19.1
startsWithKeyword :: String -> Lines -> Bool
startsWithKeyword keyword inputLines =
  List.isPrefixOf keyword line && isWordBoundary (drop (length keyword) line)
  where
    line = getFirstLine inputLines
    isWordBoundary [] = True
    isWordBoundary (c : _) = not (Char.isAlphaNum c)

-- | Convert expression position for error reporting.
--
-- @since 0.19.1
toExprPosition :: ByteString -> SyntaxError.Expr -> Parse.Row -> Parse.Col -> (Parse.Row, Parse.Col)
toExprPosition src expr row col =
  toDeclPosition src (SyntaxError.DeclDef Name.replValueToPrint (SyntaxError.DeclDefBody expr row col) row col) row col

-- | Convert declaration position for error reporting.
--
-- @since 0.19.1
toDeclPosition :: ByteString -> SyntaxError.Decl -> Parse.Row -> Parse.Col -> (Parse.Row, Parse.Col)
toDeclPosition src decl r c =
  (row, col)
  where
    err = SyntaxError.ParseError (SyntaxError.Declarations decl r c)
    diag = SyntaxError.toDiagnostic (Code.toSource src) err
    Ann.Region (Ann.Position row col) _ = Diag._spanRegion (Diag._diagPrimary diag)

-- | Parse type annotation.
--
-- @since 0.19.1
annotation :: Parse.Parser () Name.Name
annotation = do
  name <- PV.lower err
  PS.chompAndCheckIndent err_ err
  Parse.word1 0x3A {-:-} err
  PS.chompAndCheckIndent err_ err
  (_, _) <- Parse.specialize err_ PT.expression
  PS.checkFreshLine err
  pure name
  where
    err _ _ = ()
    err_ _ _ _ = ()

-- | Remove legacy backslash continuation (for 0.19.0 compatibility).
--
-- Kept for backward compatibility with 0.19.0 REPL input.
--
-- @since 0.19.1
stripLegacyBackslash :: String -> String
stripLegacyBackslash chars =
  case chars of
    [] -> []
    _ : _ -> if last chars == '\\' then init chars else chars

-- | Render prefill for multi-line input.
--
-- @since 0.19.1
renderPrefill :: Prefill -> String
renderPrefill prefill =
  case prefill of
    Indent -> "  "
    DefStart name -> Name.toChars name <> " "

-- | Generate help message for commands.
--
-- @since 0.19.1
toHelpMessage :: Maybe String -> String
toHelpMessage maybeBadCommand =
  case maybeBadCommand of
    Nothing -> genericHelpMessage
    Just command -> "I do not recognize the :" <> command <> " command. " <> genericHelpMessage

-- | Generic help message text.
--
-- @since 0.19.2
genericHelpMessage :: String
genericHelpMessage =
  "Valid commands include:\n\
  \\n\
  \  :exit          Exit the REPL\n\
  \  :help          Show this information\n\
  \  :reset         Clear all previous imports and definitions\n\
  \  :type <expr>   Show the type of an expression (alias: :t)\n\
  \  :browse [mod]  List exports of the current or specified module\n\
  \\n\
  \More info at "
    <> Doc.makeLink "repl"
    <> "\n"
