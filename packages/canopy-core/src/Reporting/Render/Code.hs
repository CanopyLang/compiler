{-# LANGUAGE OverloadedStrings #-}

module Reporting.Render.Code
  ( Source,
    toSource,
    toSnippet,
    toPair,
    Next (..),
    whatIsNext,
    nextLineStartsWithKeyword,
    nextLineStartsWithCloseCurly,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as UTF8_BS
import qualified Data.Char as Char
import qualified Data.IntSet as IntSet
import qualified Data.List as List
import qualified Data.Maybe
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Data.Word (Word32)
import Parse.Primitives (Col, Row)
import Parse.Symbol (binopCharSet)
import Parse.Variable (reservedWords)
import qualified Reporting.Annotation as Ann
import Reporting.Doc (Doc)
import qualified Reporting.Doc as Doc

-- CODE

newtype Source
  = Source [(Word32, String)]

toSource :: BS.ByteString -> Source
toSource source =
  Source . zip [1 ..] $ (lines (UTF8_BS.toString source) <> [""])

-- CODE FORMATTING

toSnippet :: Source -> Ann.Region -> Maybe Ann.Region -> (Doc.Doc, Doc.Doc) -> Doc.Doc
toSnippet source region highlight (preHint, postHint) =
  Doc.vcat
    [ preHint,
      "",
      render source region highlight,
      postHint
    ]

toPair :: Source -> Ann.Region -> Ann.Region -> (Doc.Doc, Doc.Doc) -> (Doc.Doc, Doc.Doc, Doc.Doc) -> Doc.Doc
toPair source r1 r2 (oneStart, oneEnd) (twoStart, twoMiddle, twoEnd) =
  case renderPair source r1 r2 of
    OneLine codeDocs ->
      Doc.vcat
        [ oneStart,
          "",
          codeDocs,
          oneEnd
        ]
    TwoChunks code1 code2 ->
      Doc.vcat
        [ twoStart,
          "",
          code1,
          twoMiddle,
          "",
          code2,
          twoEnd
        ]

-- RENDER SNIPPET

(|>) :: a -> (a -> b) -> b
(|>) a f =
  f a

render :: Source -> Ann.Region -> Maybe Ann.Region -> Doc
render (Source sourceLines) region@(Ann.Region (Ann.Position startLine _) (Ann.Position endLine _)) maybeSubRegion =
  let relevantLines =
        sourceLines
          |> drop (fromIntegral (startLine - 1))
          |> take (fromIntegral (1 + endLine - startLine))

      width =
        maybe 0 (length . show . fst) (safeLast relevantLines)

      smallerRegion =
        Data.Maybe.fromMaybe region maybeSubRegion
   in case makeUnderline width endLine smallerRegion of
        Nothing ->
          drawLines True width smallerRegion relevantLines Doc.empty
        Just underline ->
          drawLines False width smallerRegion relevantLines underline

-- | Safe last element extraction.
safeLast :: [a] -> Maybe a
safeLast [] = Nothing
safeLast xs = Just (List.last xs)

makeUnderline :: Int -> Word32 -> Ann.Region -> Maybe Doc
makeUnderline width realEndLine (Ann.Region (Ann.Position start c1) (Ann.Position end c2)) =
  if start /= end || end < realEndLine
    then Nothing
    else
      let spaces = replicate (fromIntegral c1 + width + 1) ' '
          zigzag = replicate (max 1 (fromIntegral (c2 - c1))) '^'
       in Just (Doc.fromChars spaces <> Doc.red (Doc.fromChars zigzag))

drawLines :: Bool -> Int -> Ann.Region -> [(Word32, String)] -> Doc -> Doc
drawLines addZigZag width (Ann.Region (Ann.Position startLine _) (Ann.Position endLine _)) sourceLines finalLine =
  Doc.vcat (fmap (drawLine addZigZag width startLine endLine) sourceLines <> [finalLine])

drawLine :: Bool -> Int -> Word32 -> Word32 -> (Word32, String) -> Doc
drawLine addZigZag width startLine endLine (n, line) =
  addLineNumber addZigZag width startLine endLine n (Doc.fromChars line)

addLineNumber :: Bool -> Int -> Word32 -> Word32 -> Word32 -> Doc -> Doc
addLineNumber addZigZag width start end n line =
  let number =
        show n

      lineNumber =
        (replicate (width - length number) ' ' <> (number <> "|"))

      spacer =
        if addZigZag && start <= n && n <= end
          then Doc.red ">"
          else " "
   in Doc.fromChars lineNumber <> spacer <> line

-- RENDER PAIR

data CodePair
  = OneLine Doc
  | TwoChunks Doc Doc

renderPair :: Source -> Ann.Region -> Ann.Region -> CodePair
renderPair source@(Source sourceLines) region1 region2 =
  let (Ann.Region (Ann.Position startRow1 startCol1) (Ann.Position endRow1 endCol1)) = region1
      (Ann.Region (Ann.Position startRow2 startCol2) (Ann.Position endRow2 endCol2)) = region2
   in if startRow1 == endRow1 && endRow1 == startRow2 && startRow2 == endRow2
        then
          let lineNumber = show startRow1
              spaces1 = replicate (fromIntegral startCol1 + length lineNumber + 1) ' '
              zigzag1 = replicate (fromIntegral (endCol1 - startCol1)) '^'
              spaces2 = replicate (fromIntegral (startCol2 - endCol1)) ' '
              zigzag2 = replicate (fromIntegral (endCol2 - startCol2)) '^'

              line = Data.Maybe.fromMaybe "" (List.lookup startRow1 sourceLines)
           in OneLine $
                Doc.vcat
                  [ Doc.fromChars lineNumber <> "| " <> Doc.fromChars line,
                    Doc.fromChars spaces1 <> Doc.red (Doc.fromChars zigzag1)
                      <> Doc.fromChars spaces2
                      <> Doc.red (Doc.fromChars zigzag2)
                  ]
        else
          TwoChunks
            (render source region1 Nothing)
            (render source region2 Nothing)

-- WHAT IS NEXT?

data Next
  = Keyword String
  | Operator String
  | Close String Char
  | Upper Char String
  | Lower Char String
  | Other (Maybe Char)

whatIsNext :: Source -> Row -> Col -> Next
whatIsNext (Source sourceLines) row col =
  case List.lookup row sourceLines of
    Nothing ->
      Other Nothing
    Just line ->
      case drop (fromIntegral col - 1) line of
        [] ->
          Other Nothing
        c : cs
          | Char.isUpper c -> Upper c (takeWhile isInner cs)
          | Char.isLower c -> detectKeywords c cs
          | isSymbol c -> Operator (c : takeWhile isSymbol cs)
          | c == ')' -> Close "parenthesis" ')'
          | c == ']' -> Close "square bracket" ']'
          | c == '}' -> Close "curly brace" '}'
          | otherwise -> Other (Just c)

detectKeywords :: Char -> String -> Next
detectKeywords c rest =
  let cs = takeWhile isInner rest
      name = c : cs
   in if Set.member (Name.fromChars name) reservedWords
        then Keyword name
        else Lower c name

isInner :: Char -> Bool
isInner char =
  Char.isAlphaNum char || char == '_'

isSymbol :: Char -> Bool
isSymbol char =
  IntSet.member (Char.ord char) binopCharSet

startsWithKeyword :: String -> String -> Bool
startsWithKeyword restOfLine keyword =
  List.isPrefixOf keyword restOfLine
    && case drop (length keyword) restOfLine of
      [] ->
        True
      c : _ ->
        not (isInner c)

nextLineStartsWithKeyword :: String -> Source -> Row -> Maybe (Row, Col)
nextLineStartsWithKeyword keyword (Source sourceLines) row =
  case List.lookup (row + 1) sourceLines of
    Nothing ->
      Nothing
    Just line ->
      if startsWithKeyword (dropWhile (== ' ') line) keyword
        then Just (row + 1, 1 + fromIntegral (length (takeWhile (== ' ') line)))
        else Nothing

nextLineStartsWithCloseCurly :: Source -> Row -> Maybe (Row, Col)
nextLineStartsWithCloseCurly (Source sourceLines) row =
  case List.lookup (row + 1) sourceLines of
    Nothing ->
      Nothing
    Just line ->
      case dropWhile (== ' ') line of
        '}' : _ ->
          Just (row + 1, 1 + fromIntegral (length (takeWhile (== ' ') line)))
        _ ->
          Nothing
