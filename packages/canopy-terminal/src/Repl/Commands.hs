
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
import qualified Data.Name as N
import qualified Parse.Declaration as PD
import qualified Parse.Expression as PE
import qualified Parse.Module as PM
import qualified Parse.Primitives as P
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
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Error.Syntax as ES
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
    parser = P.specialize (\_ _ _ -> ()) PM.chompImport
    parseResult = P.fromByteString parser (\_ _ -> ()) src

    successHandler (Src.Import (A.At _ name) _ _ _) = Done (Import name src)
    failHandler () = ifFail inputLines (Import (N.fromChars "ERR") src)

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
    exprParser = P.specialize (toExprPosition src) PE.expression
    declParser = P.specialize (toDeclPosition src) PD.declaration
    declResult = P.fromByteString declParser (,) src

-- | Process successfully parsed declaration.
--
-- @since 0.19.1
processDeclaration :: Lines -> ByteString -> PD.Decl -> CategorizedInput
processDeclaration inputLines src decl =
  case decl of
    PD.Value _ (A.At _ (Src.Value (A.At _ name) _ _ _)) ->
      ifDone inputLines (Decl name src)
    PD.Union _ (A.At _ (Src.Union (A.At _ name) _ _)) ->
      ifDone inputLines (Type name src)
    PD.Alias _ (A.At _ (Src.Alias (A.At _ name) _ _)) ->
      ifDone inputLines (Type name src)
    PD.Port _ _ -> Done Port

-- | Handle declaration parsing error.
--
-- @since 0.19.1
handleDeclError :: Lines -> ByteString -> P.Parser (P.Row, P.Col) (Src.Expr, a) -> (P.Row, P.Col) -> CategorizedInput
handleDeclError inputLines src exprParser declPosition
  | startsWithKeyword "type" inputLines = ifFail inputLines (Type (N.fromChars "ERR") src)
  | startsWithKeyword "port" inputLines = Done Port
  | otherwise = tryParseExpression inputLines src exprParser declPosition

-- | Try parsing as expression after declaration failed.
--
-- @since 0.19.1
tryParseExpression :: Lines -> ByteString -> P.Parser (P.Row, P.Col) (Src.Expr, a) -> (P.Row, P.Col) -> CategorizedInput
tryParseExpression inputLines src exprParser declPosition =
  case P.fromByteString exprParser (,) src of
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
  case P.fromByteString annotation (\_ _ -> ()) src of
    Right name -> Continue (DefStart name)
    Left () -> ifFail inputLines (Decl (N.fromChars "ERR") src)

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
  case drop 1 (dropWhile (== ' ') (getFirstLine inputLines)) of
    "reset" -> Reset
    "exit" -> Exit
    "quit" -> Exit
    "help" -> Help Nothing
    rest -> Help (Just (takeWhile (/= ' ') rest))

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
toExprPosition :: ByteString -> ES.Expr -> P.Row -> P.Col -> (P.Row, P.Col)
toExprPosition src expr row col =
  toDeclPosition src (ES.DeclDef N.replValueToPrint (ES.DeclDefBody expr row col) row col) row col

-- | Convert declaration position for error reporting.
--
-- @since 0.19.1
toDeclPosition :: ByteString -> ES.Decl -> P.Row -> P.Col -> (P.Row, P.Col)
toDeclPosition src decl r c =
  (row, col)
  where
    err = ES.ParseError (ES.Declarations decl r c)
    diag = ES.toDiagnostic (Code.toSource src) err
    A.Region (A.Position row col) _ = Diag._spanRegion (Diag._diagPrimary diag)

-- | Parse type annotation.
--
-- @since 0.19.1
annotation :: P.Parser () N.Name
annotation = do
  name <- PV.lower err
  PS.chompAndCheckIndent err_ err
  P.word1 0x3A {-:-} err
  PS.chompAndCheckIndent err_ err
  (_, _) <- P.specialize err_ PT.expression
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
    DefStart name -> N.toChars name <> " "

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
-- @since 0.19.1
genericHelpMessage :: String
genericHelpMessage =
  "Valid commands include:\n\
  \\n\
  \  :exit    Exit the REPL\n\
  \  :help    Show this information\n\
  \  :reset   Clear all previous imports and definitions\n\
  \\n\
  \More info at "
    <> D.makeLink "repl"
    <> "\n"
