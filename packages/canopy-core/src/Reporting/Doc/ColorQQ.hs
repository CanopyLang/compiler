{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Quasi-quoter for colorized 'P.Doc' values with inline interpolation.
--
-- Provides the @[c|...|]@ quasi-quoter that produces 'P.Doc' values with
-- embedded color markup and variable interpolation, making error messages
-- readable at a glance.
--
-- ==== Syntax
--
-- @
-- [c|Hello, world!|]                       -- literal text
-- [c|Cannot load from \#{path}|]           -- String interpolation
-- [c|{red|ERROR}: not found.|]             -- color markup
-- [c|\@{detailDoc}|]                       -- Doc embedding
-- [c|Use {{red|..}} for color.|]           -- escaped braces
-- @
--
-- ==== Supported styles
--
-- @red@, @green@, @blue@, @cyan@, @magenta@, @yellow@, @black@, @white@,
-- @dullred@, @dullgreen@, @dullblue@, @dullcyan@, @dullmagenta@, @dullyellow@,
-- @bold@, @underline@
--
-- @since 0.19.1
module Reporting.Doc.ColorQQ
  ( c,
    -- Wrappers required by TH-generated splices. Not intended for direct use.
    pText,
    pLine,
    pEmpty,
    pRed,
    pGreen,
    pBlue,
    pCyan,
    pMagenta,
    pYellow,
    pBlack,
    pWhite,
    pDullred,
    pDullgreen,
    pDullblue,
    pDullcyan,
    pDullmagenta,
    pDullyellow,
    pBold,
    pUnderline,
  )
where

import qualified Data.Char as Char
import Language.Haskell.TH (Exp, Q)
import Language.Haskell.TH.Quote (QuasiQuoter (..))
import qualified Language.Haskell.TH as TH
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- FRAGMENT AST

-- | A parsed fragment from the quasi-quote body.
data Fragment
  = Lit !String
  | Var !String
  | DocVar !String
  | Styled !StyleName [Fragment]
  | Newline
  deriving (Show, Eq)

-- | Supported ANSI style names that map to @ansi-wl-pprint@ functions.
data StyleName
  = Red
  | Green
  | Blue
  | Cyan
  | Magenta
  | Yellow
  | Black
  | White
  | DullRed
  | DullGreen
  | DullBlue
  | DullCyan
  | DullMagenta
  | DullYellow
  | Bold
  | Underline
  deriving (Show, Eq)

-- QUASI-QUOTER

-- | Quasi-quoter that produces 'P.Doc' values with color markup and interpolation.
--
-- Only expression splicing is supported. Pattern, type, and declaration
-- contexts produce compile-time errors.
c :: QuasiQuoter
c =
  QuasiQuoter
    { quoteExp = compileColorDoc,
      quotePat = unsupported "pattern",
      quoteType = unsupported "type",
      quoteDec = unsupported "declaration"
    }
  where
    unsupported ctx _ =
      fail ("[c|...|] cannot be used in a " ++ ctx ++ " context")

-- COMPILATION

-- | Parse the QQ body and compile it to a TH expression.
compileColorDoc :: String -> Q Exp
compileColorDoc input =
  either fail fragmentsToExp (parseFragments input)

-- PARSER

-- | Parse a QQ body into a list of fragments.
parseFragments :: String -> Either String [Fragment]
parseFragments = fmap coalesce . parseTop []

-- | Top-level parse loop accumulating fragments in reverse.
parseTop :: [Fragment] -> String -> Either String [Fragment]
parseTop acc [] = Right (reverse acc)
parseTop acc ('\n' : rest) = parseTop (Newline : acc) rest
parseTop acc ('{' : '{' : rest) = parseTop (Lit "{" : acc) rest
parseTop acc ('}' : '}' : rest) = parseTop (Lit "}" : acc) rest
parseTop acc ('#' : '{' : rest) = parseInterp acc rest
parseTop acc ('@' : '{' : rest) = parseDocInterp acc rest
parseTop acc ('{' : rest) = parseStyled acc rest
parseTop acc str = parseLitChunk acc str

-- | Consume a run of literal characters up to the next special sequence.
parseLitChunk :: [Fragment] -> String -> Either String [Fragment]
parseLitChunk acc str =
  parseTop (Lit chunk : acc) remaining
  where
    (chunk, remaining) = spanLiteral str

-- | Span literal characters, stopping at any special sequence boundary.
spanLiteral :: String -> (String, String)
spanLiteral [] = ([], [])
spanLiteral ('\n' : rest) = ([], '\n' : rest)
spanLiteral ('{' : '{' : rest) = ([], '{' : '{' : rest)
spanLiteral ('}' : '}' : rest) = ([], '}' : '}' : rest)
spanLiteral ('#' : '{' : rest) = ([], '#' : '{' : rest)
spanLiteral ('@' : '{' : rest) = ([], '@' : '{' : rest)
spanLiteral ('{' : rest) = ([], '{' : rest)
spanLiteral (ch : rest) =
  let (more, remaining) = spanLiteral rest
   in (ch : more, remaining)

-- | Parse a @\#{expr}@ String interpolation, tracking brace depth.
parseInterp :: [Fragment] -> String -> Either String [Fragment]
parseInterp acc input =
  extractBracedExpr input >>= \(expr, rest) ->
    parseTop (Var expr : acc) rest

-- | Parse a @\@{expr}@ Doc interpolation, tracking brace depth.
parseDocInterp :: [Fragment] -> String -> Either String [Fragment]
parseDocInterp acc input =
  extractBracedExpr input >>= \(expr, rest) ->
    parseTop (DocVar expr : acc) rest

-- | Extract a brace-delimited expression, respecting nested braces.
extractBracedExpr :: String -> Either String (String, String)
extractBracedExpr = extractBraced (0 :: Int) []

-- | Recursive walker for 'extractBracedExpr' tracking brace depth.
extractBraced :: Int -> String -> String -> Either String (String, String)
extractBraced _ _ [] = Left "Unterminated interpolation: missing closing '}'"
extractBraced 0 acc ('}' : rest) = Right (reverse acc, rest)
extractBraced depth acc ('{' : rest) = extractBraced (depth + 1) ('{' : acc) rest
extractBraced depth acc ('}' : rest) = extractBraced (depth - 1) ('}' : acc) rest
extractBraced depth acc (ch : rest) = extractBraced depth (ch : acc) rest

-- | Parse @{styleName|...}@ styled block.
parseStyled :: [Fragment] -> String -> Either String [Fragment]
parseStyled acc input =
  extractStyleName input >>= \(styleName, bodyInput) ->
    parseStyledBody bodyInput >>= \(bodyFrags, rest) ->
      parseTop (Styled styleName bodyFrags : acc) rest

-- | Extract the style name before the @|@ separator.
extractStyleName :: String -> Either String (StyleName, String)
extractStyleName input =
  parseStyleName name >>= \sn ->
    validatePipe remaining >>= \bodyStart ->
      Right (sn, bodyStart)
  where
    (name, remaining) = span (\ch -> Char.isAlpha ch || Char.isDigit ch) input

    validatePipe ('|' : rest) = Right rest
    validatePipe _ = Left ("Expected '|' after style name, got: " ++ take 10 input)

-- | Parse the body of a styled block until the unmatched closing @}@.
--
-- Collects raw characters while tracking brace depth, then recursively
-- parses the collected body as fragments.
parseStyledBody :: String -> Either String ([Fragment], String)
parseStyledBody = collectStyledBody [] (0 :: Int)

-- | Collect characters for a styled block body, tracking brace depth.
collectStyledBody :: String -> Int -> String -> Either String ([Fragment], String)
collectStyledBody _ _ [] = Left "Unterminated style block: missing closing '}'"
collectStyledBody acc 0 ('}' : rest) =
  parseFragments (reverse acc) >>= \frags -> Right (frags, rest)
collectStyledBody acc depth ('{' : rest) = collectStyledBody ('{' : acc) (depth + 1) rest
collectStyledBody acc depth ('}' : rest) = collectStyledBody ('}' : acc) (depth - 1) rest
collectStyledBody acc depth (ch : rest) = collectStyledBody (ch : acc) depth rest

-- | Map a style name string to its 'StyleName' constructor.
parseStyleName :: String -> Either String StyleName
parseStyleName name =
  maybe
    (Left ("Unknown style: '" ++ name ++ "'. Supported: " ++ supportedList))
    Right
    (lookup name styleNameTable)
  where
    supportedList = unwords (fmap fst styleNameTable)

-- | Association list of style name strings to 'StyleName' constructors.
styleNameTable :: [(String, StyleName)]
styleNameTable =
  [ ("red", Red),
    ("green", Green),
    ("blue", Blue),
    ("cyan", Cyan),
    ("magenta", Magenta),
    ("yellow", Yellow),
    ("black", Black),
    ("white", White),
    ("dullred", DullRed),
    ("dullgreen", DullGreen),
    ("dullblue", DullBlue),
    ("dullcyan", DullCyan),
    ("dullmagenta", DullMagenta),
    ("dullyellow", DullYellow),
    ("bold", Bold),
    ("underline", Underline)
  ]

-- COALESCER

-- | Merge adjacent 'Lit' fragments into a single 'Lit'.
coalesce :: [Fragment] -> [Fragment]
coalesce [] = []
coalesce (Lit a : Lit b : rest) = coalesce (Lit (a ++ b) : rest)
coalesce (Styled sn frags : rest) = Styled sn (coalesce frags) : coalesce rest
coalesce (f : rest) = f : coalesce rest

-- CODE GENERATOR

-- | Compile a list of fragments into a TH expression producing a 'P.Doc'.
fragmentsToExp :: [Fragment] -> Q Exp
fragmentsToExp [] = [|pEmpty|]
fragmentsToExp [frag] = fragmentToExp frag
fragmentsToExp frags =
  foldl1 combineExps (fmap fragmentToExp frags)
  where
    combineExps a b = [|$a <> $b|]

-- | Compile a single fragment to a TH expression.
fragmentToExp :: Fragment -> Q Exp
fragmentToExp (Lit s) = [|pText s|]
fragmentToExp (Var expr) = wrapText (resolveExpr expr)
fragmentToExp (DocVar expr) = resolveExpr expr
fragmentToExp Newline = [|pLine|]
fragmentToExp (Styled sn body) = applyStyle sn (fragmentsToExp body)

-- | Resolve a Haskell expression string to a TH 'Exp'.
--
-- Supports simple variable names, qualified names, and expressions
-- containing common operators.
resolveExpr :: String -> Q Exp
resolveExpr expr
  | isSimpleName expr = resolveVarName expr
  | otherwise = fail ("Expression '" ++ expr ++ "' must be a simple or qualified variable name")

-- | Check whether a string looks like a simple or qualified Haskell variable name.
isSimpleName :: String -> Bool
isSimpleName [] = False
isSimpleName s = all (\ch -> Char.isAlphaNum ch || ch `elem` ("._'" :: String)) s

-- | Resolve a possibly-qualified variable name via TH lookup.
resolveVarName :: String -> Q Exp
resolveVarName name =
  TH.lookupValueName name >>= \case
    Just resolved -> TH.varE resolved
    Nothing -> fail ("Variable not in scope: '" ++ name ++ "'")

-- | Wrap an expression with @pText@ to convert String to Doc.
wrapText :: Q Exp -> Q Exp
wrapText expr = [|pText $expr|]

-- | Apply a style function to a 'P.Doc' expression.
applyStyle :: StyleName -> Q Exp -> Q Exp
applyStyle Red e = [|pRed $e|]
applyStyle Green e = [|pGreen $e|]
applyStyle Blue e = [|pBlue $e|]
applyStyle Cyan e = [|pCyan $e|]
applyStyle Magenta e = [|pMagenta $e|]
applyStyle Yellow e = [|pYellow $e|]
applyStyle Black e = [|pBlack $e|]
applyStyle White e = [|pWhite $e|]
applyStyle DullRed e = [|pDullred $e|]
applyStyle DullGreen e = [|pDullgreen $e|]
applyStyle DullBlue e = [|pDullblue $e|]
applyStyle DullCyan e = [|pDullcyan $e|]
applyStyle DullMagenta e = [|pDullmagenta $e|]
applyStyle DullYellow e = [|pDullyellow $e|]
applyStyle Bold e = [|pBold $e|]
applyStyle Underline e = [|pUnderline $e|]

-- TH WRAPPERS
--
-- Template Haskell quotation brackets capture names from the defining module.
-- These thin wrappers around ansi-wl-pprint functions ensure that TH-generated
-- code resolves correctly at any splice site without requiring the user to
-- import Text.PrettyPrint.ANSI.Leijen.

-- | Wrap 'P.text' for TH splice resolution.
pText :: String -> P.Doc
pText = P.text

-- | Wrap 'P.line' for TH splice resolution.
pLine :: P.Doc
pLine = P.line

-- | Wrap 'P.empty' for TH splice resolution.
pEmpty :: P.Doc
pEmpty = P.empty

-- | Wrap 'P.red' for TH splice resolution.
pRed :: P.Doc -> P.Doc
pRed = P.red

-- | Wrap 'P.green' for TH splice resolution.
pGreen :: P.Doc -> P.Doc
pGreen = P.green

-- | Wrap 'P.blue' for TH splice resolution.
pBlue :: P.Doc -> P.Doc
pBlue = P.blue

-- | Wrap 'P.cyan' for TH splice resolution.
pCyan :: P.Doc -> P.Doc
pCyan = P.cyan

-- | Wrap 'P.magenta' for TH splice resolution.
pMagenta :: P.Doc -> P.Doc
pMagenta = P.magenta

-- | Wrap 'P.yellow' for TH splice resolution.
pYellow :: P.Doc -> P.Doc
pYellow = P.yellow

-- | Wrap 'P.black' for TH splice resolution.
pBlack :: P.Doc -> P.Doc
pBlack = P.black

-- | Wrap 'P.white' for TH splice resolution.
pWhite :: P.Doc -> P.Doc
pWhite = P.white

-- | Wrap 'P.dullred' for TH splice resolution.
pDullred :: P.Doc -> P.Doc
pDullred = P.dullred

-- | Wrap 'P.dullgreen' for TH splice resolution.
pDullgreen :: P.Doc -> P.Doc
pDullgreen = P.dullgreen

-- | Wrap 'P.dullblue' for TH splice resolution.
pDullblue :: P.Doc -> P.Doc
pDullblue = P.dullblue

-- | Wrap 'P.dullcyan' for TH splice resolution.
pDullcyan :: P.Doc -> P.Doc
pDullcyan = P.dullcyan

-- | Wrap 'P.dullmagenta' for TH splice resolution.
pDullmagenta :: P.Doc -> P.Doc
pDullmagenta = P.dullmagenta

-- | Wrap 'P.dullyellow' for TH splice resolution.
pDullyellow :: P.Doc -> P.Doc
pDullyellow = P.dullyellow

-- | Wrap 'P.bold' for TH splice resolution.
pBold :: P.Doc -> P.Doc
pBold = P.bold

-- | Wrap 'P.underline' for TH splice resolution.
pUnderline :: P.Doc -> P.Doc
pUnderline = P.underline
