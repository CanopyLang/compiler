{-# LANGUAGE OverloadedStrings #-}

module Reporting.Doc
  ( PP.Doc,
    (PP.<+>),
    (<>),
    PP.align,
    PP.cat,
    PP.empty,
    PP.fill,
    PP.fillSep,
    PP.hang,
    PP.hcat,
    PP.hsep,
    PP.indent,
    PP.sep,
    PP.vcat,
    PP.red,
    PP.cyan,
    PP.magenta,
    PP.green,
    PP.blue,
    PP.black,
    PP.yellow,
    PP.dullred,
    PP.dullcyan,
    PP.dullyellow,
    PP.dullgreen,
    PP.dullblue,
    PP.dullmagenta,
    PP.bold,
    PP.underline,
    PP.white,
    --
    fromChars,
    fromName,
    fromVersion,
    fromPackage,
    fromInt,
    --
    toAnsi,
    toString,
    toLine,
    --
    encode,
    --
    stack,
    reflow,
    commaSep,
    --
    toSimpleNote,
    toFancyNote,
    toSimpleHint,
    toFancyHint,
    --
    link,
    fancyLink,
    reflowLink,
    makeLink,
    makeNakedLink,
    --
    args,
    moreArgs,
    ordinal,
    intToOrdinal,
    cycle,
  )
where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Canopy.Data.Index as Index
import qualified Data.List as List
import qualified Canopy.Data.Name as Name
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Json.String as Json
import qualified System.Console.ANSI.Types as Ansi
import System.IO (Handle)
import qualified System.Info as Info
import qualified Text.PrettyPrint.ANSI.Leijen as PP
import Prelude hiding (cycle)

-- FROM

fromChars :: String -> PP.Doc
fromChars =
  PP.text

fromName :: Name.Name -> PP.Doc
fromName name =
  PP.text (Name.toChars name)

fromVersion :: Version.Version -> PP.Doc
fromVersion vsn =
  PP.text (Version.toChars vsn)

fromPackage :: Pkg.Name -> PP.Doc
fromPackage pkg =
  PP.text (Pkg.toChars pkg)

fromInt :: Int -> PP.Doc
fromInt n =
  PP.text (show n)

-- TO STRING

toAnsi :: Handle -> PP.Doc -> IO ()
toAnsi handle doc =
  PP.displayIO handle (PP.renderPretty 1 80 doc)

toString :: PP.Doc -> String
toString doc =
  PP.displayS (PP.renderPretty 1 80 (PP.plain doc)) ""

toLine :: PP.Doc -> String
toLine doc =
  PP.displayS (PP.renderPretty 1 (div maxBound 2) (PP.plain doc)) ""

-- FORMATTING

stack :: [PP.Doc] -> PP.Doc
stack docs =
  PP.vcat (List.intersperse "" docs)

reflow :: String -> PP.Doc
reflow paragraph =
  PP.fillSep (fmap PP.text (words paragraph))

commaSep :: PP.Doc -> (PP.Doc -> PP.Doc) -> [PP.Doc] -> [PP.Doc]
commaSep conjunction addStyle names =
  case names of
    [name] ->
      [addStyle name]
    [name1, name2] ->
      [addStyle name1, conjunction, addStyle name2]
    _ ->
      fmap (\name -> addStyle name <> ",") (init names)
        <> [ conjunction,
             addStyle (last names)
           ]

-- NOTES

toSimpleNote :: String -> PP.Doc
toSimpleNote message =
  toFancyNote (fmap PP.text (words message))

toFancyNote :: [PP.Doc] -> PP.Doc
toFancyNote chunks =
  PP.fillSep (PP.underline "Note" <> ":" : chunks)

-- HINTS

toSimpleHint :: String -> PP.Doc
toSimpleHint message =
  toFancyHint (fmap PP.text (words message))

toFancyHint :: [PP.Doc] -> PP.Doc
toFancyHint chunks =
  PP.fillSep (PP.underline "Hint" <> ":" : chunks)

-- LINKS

link :: String -> String -> String -> String -> PP.Doc
link word before fileName after =
  PP.fillSep $
    (PP.underline (PP.text word) <> ":") :
    ( fmap PP.text (words before)
        <> ( PP.text (makeLink fileName) :
             fmap PP.text (words after)
           )
    )

fancyLink :: String -> [PP.Doc] -> String -> [PP.Doc] -> PP.Doc
fancyLink word before fileName after =
  PP.fillSep $
    (PP.underline (PP.text word) <> ":") : (before <> (PP.text (makeLink fileName) : after))

makeLink :: String -> String
makeLink fileName =
  "<https://canopy-lang.org/" <> Version.toChars Version.compiler <> "/" <> fileName <> ">"

makeNakedLink :: String -> String
makeNakedLink fileName =
  "https://canopy-lang.org/" <> Version.toChars Version.compiler <> "/" <> fileName

reflowLink :: String -> String -> String -> PP.Doc
reflowLink before fileName after =
  PP.fillSep
    ( fmap PP.text (words before)
        <> ( PP.text (makeLink fileName) :
             fmap PP.text (words after)
           )
    )

-- HELPERS

args :: Int -> String
args n =
  show n <> if n == 1 then " argument" else " arguments"

moreArgs :: Int -> String
moreArgs n =
  show n <> " more" <> if n == 1 then " argument" else " arguments"

ordinal :: Index.ZeroBased -> String
ordinal index =
  intToOrdinal (Index.toHuman index)

intToOrdinal :: Int -> String
intToOrdinal number =
  let remainder10 =
        number `mod` 10

      remainder100 =
        number `mod` 100

      ending
        | remainder100 `elem` [11 .. 13] = "th"
        | remainder10 == 1 = "st"
        | remainder10 == 2 = "nd"
        | remainder10 == 3 = "rd"
        | otherwise = "th"
   in show number <> ending

cycle :: Int -> Name.Name -> [Name.Name] -> PP.Doc
cycle indent name names =
  let toLn n = cycleLn <> PP.dullyellow (fromName n)
   in (PP.indent indent . PP.vcat $ (cycleTop : (List.intersperse cycleMid (toLn name : fmap toLn names) <> [cycleEnd])))

cycleTop, cycleLn, cycleMid, cycleEnd :: PP.Doc
cycleTop = if isWindows then "+-----+" else "┌─────┐"
cycleLn = if isWindows then "|    " else "│    "
cycleMid = if isWindows then "|     |" else "│     ↓"
cycleEnd = if isWindows then "+-<---+" else "└─────┘"

isWindows :: Bool
isWindows =
  Info.os == "mingw32"

-- JSON

encode :: PP.Doc -> Encode.Value
encode doc =
  Encode.array (toJsonHelp noStyle [] (PP.renderPretty 1 80 doc))

data Style = Style
  { _bold :: Bool,
    _underline :: Bool,
    _color :: Maybe Color
  }

noStyle :: Style
noStyle =
  Style False False Nothing

data Color
  = Red
  | RED
  | Magenta
  | MAGENTA
  | Yellow
  | YELLOW
  | Green
  | GREEN
  | Cyan
  | CYAN
  | Blue
  | BLUE
  | Black
  | BLACK
  | White
  | WHITE

toJsonHelp :: Style -> [String] -> PP.SimpleDoc -> [Encode.Value]
toJsonHelp style revChunks simpleDoc =
  case simpleDoc of
    PP.SFail ->
      error
        "according to the main implementation, @SFail@ can not\
        \ appear uncaught in a rendered @SimpleDoc@"
    PP.SEmpty ->
      [encodeChunks style revChunks]
    PP.SChar char rest ->
      toJsonHelp style ([char] : revChunks) rest
    PP.SText _ string rest ->
      toJsonHelp style (string : revChunks) rest
    PP.SLine indent rest ->
      toJsonHelp style (replicate indent ' ' : "\n" : revChunks) rest
    PP.SSGR sgrs rest ->
      encodeChunks style revChunks : toJsonHelp (sgrToStyle sgrs style) [] rest

sgrToStyle :: [Ansi.SGR] -> Style -> Style
sgrToStyle sgrs style@(Style bold underline color) =
  case sgrs of
    [] ->
      style
    sgr : rest ->
      sgrToStyle rest $
        case sgr of
          Ansi.Reset -> noStyle
          Ansi.SetConsoleIntensity i -> Style (isBold i) underline color
          Ansi.SetItalicized _ -> style
          Ansi.SetUnderlining u -> Style bold (isUnderline u) color
          Ansi.SetBlinkSpeed _ -> style
          Ansi.SetVisible _ -> style
          Ansi.SetSwapForegroundBackground _ -> style
          Ansi.SetColor l i c -> Style bold underline (toColor l i c)
          Ansi.SetRGBColor _ _ -> style
          -- Palette and default color commands are passed through without
          -- modification since they don't map to the simplified color model.
          Ansi.SetPaletteColor _ _ -> style
          Ansi.SetDefaultColor _ -> style

isBold :: Ansi.ConsoleIntensity -> Bool
isBold intensity =
  case intensity of
    Ansi.BoldIntensity -> True
    Ansi.FaintIntensity -> False
    Ansi.NormalIntensity -> False

isUnderline :: Ansi.Underlining -> Bool
isUnderline underlining =
  case underlining of
    Ansi.SingleUnderline -> True
    Ansi.DoubleUnderline -> False
    Ansi.NoUnderline -> False

toColor :: Ansi.ConsoleLayer -> Ansi.ColorIntensity -> Ansi.Color -> Maybe Color
toColor layer intensity color =
  case layer of
    Ansi.Background ->
      Nothing
    Ansi.Foreground ->
      let pick dull vivid =
            case intensity of
              Ansi.Dull -> dull
              Ansi.Vivid -> vivid
       in Just $
            case color of
              Ansi.Red -> pick Red RED
              Ansi.Magenta -> pick Magenta MAGENTA
              Ansi.Yellow -> pick Yellow YELLOW
              Ansi.Green -> pick Green GREEN
              Ansi.Cyan -> pick Cyan CYAN
              Ansi.Blue -> pick Blue BLUE
              Ansi.White -> pick White WHITE
              Ansi.Black -> pick Black BLACK

encodeChunks :: Style -> [String] -> Encode.Value
encodeChunks (Style bold underline color) revChunks =
  let chars = concat (reverse revChunks)
   in case color of
        Nothing
          | not bold && not underline ->
            Encode.chars chars
        _ ->
          Encode.object
            [ "bold" ==> Encode.bool bold,
              "underline" ==> Encode.bool underline,
              "color" ==> maybe Encode.null encodeColor color,
              "string" ==> Encode.chars chars
            ]

encodeColor :: Color -> Encode.Value
encodeColor color =
  Encode.string . Json.fromChars $
    ( case color of
        Red -> "red"
        RED -> "RED"
        Magenta -> "magenta"
        MAGENTA -> "MAGENTA"
        Yellow -> "yellow"
        YELLOW -> "YELLOW"
        Green -> "green"
        GREEN -> "GREEN"
        Cyan -> "cyan"
        CYAN -> "CYAN"
        Blue -> "blue"
        BLUE -> "BLUE"
        Black -> "black"
        BLACK -> "BLACK"
        White -> "white"
        WHITE -> "WHITE"
    )
