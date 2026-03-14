{-# LANGUAGE BangPatterns, EmptyDataDecls, OverloadedStrings, UnboxedTuples #-}
module Canopy.Kernel
  ( Content(..)
  , Chunk(..)
  , fromByteString
  , countFields
  )
  where


import qualified Control.Monad as Monad
import Data.Binary (Binary, get, put, getWord8, putWord8)
import qualified Data.ByteString.Internal as BSI
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Data.Word (Word8)
import Foreign.Ptr (Ptr, plusPtr, minusPtr)
import Foreign.ForeignPtr (ForeignPtr)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)

import qualified AST.Source as Src
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Parse.Module as Module
import qualified Parse.Space as Space
import qualified Parse.Variable as Var
import Parse.Primitives hiding (fromByteString)
import qualified Parse.Primitives as Parse
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError



-- CHUNK


data Chunk
  = JS BSI.ByteString
  | CanopyVar ModuleName.Canonical Name.Name
  | JsVar Name.Name Name.Name
  | CanopyField Name.Name
  | JsField Int
  | JsEnum Int
  | Debug
  | Prod
  deriving Show



-- COUNT FIELDS


countFields :: [Chunk] -> Map.Map Name.Name Int
countFields = foldr addField Map.empty


addField :: Chunk -> Map.Map Name.Name Int -> Map.Map Name.Name Int
addField chunk fields =
  case chunk of
    JS _       -> fields
    CanopyVar _ _ -> fields
    JsVar _ _  -> fields
    CanopyField f -> Map.insertWith (+) f 1 fields
    JsField _  -> fields
    JsEnum _   -> fields
    Debug      -> fields
    Prod       -> fields



-- FROM FILE


data Content =
  Content [Src.Import] [Chunk]


type Foreigns =
  Map.Map ModuleName.Raw Pkg.Name


fromByteString :: Pkg.Name -> Foreigns -> BSI.ByteString -> Maybe Content
fromByteString pkg foreigns bytes =
  case Parse.fromByteString (parser pkg foreigns) toError bytes of
    Right content ->
      Just content

    Left () ->
      Nothing


parser :: Pkg.Name -> Foreigns -> Parser () Content
parser pkg foreigns =
  do  word2 0x2F 0x2A {-/*-} toError
      Space.chomp ignoreError
      Space.checkFreshLine toError
      imports <- specialize ignoreError (Module.chompImports [])
      word2 0x2A 0x2F {-*/-} toError
      chunks <- parseChunks (toVarTable pkg foreigns imports) Map.empty Map.empty
      return (Content imports chunks)


toError :: Row -> Col -> ()
toError _ _ =
  ()


ignoreError :: a -> Row -> Col -> ()
ignoreError _ _ _ =
  ()



-- PARSE CHUNKS


parseChunks :: VarTable -> Enums -> Fields -> Parser () [Chunk]
parseChunks vtable enums fields =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr _ ->
    let
      (# chunks, newPos, newRow, newCol #) =
        chompChunks vtable enums fields src pos end row col pos []
    in
    if newPos == end then
      cok chunks (Parse.State src newPos end indent newRow newCol)
    else
      cerr row col toError


chompChunks :: VarTable -> Enums -> Fields -> ForeignPtr Word8 -> Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [Chunk] -> (# [Chunk], Ptr Word8, Row, Col #)
chompChunks vs es fs src pos end row col lastPos revChunks =
  if pos >= end then
    let !js = toByteString src lastPos end in
    (# reverse (JS js : revChunks), pos, row, col #)

  else
    let !word = unsafeIndex pos in
    if word == 0x5F {-_-} then
      let
        !pos1 = plusPtr pos 1
        !pos3 = plusPtr pos 3
      in
      if pos3 <= end && unsafeIndex pos1 == 0x5F {-_-} then
        let !js = toByteString src lastPos pos in
        chompTag vs es fs src pos3 end row (col + 3) (JS js : revChunks)
      else
        chompChunks vs es fs src pos1 end row (col + 1) lastPos revChunks

    else if word == 0x0A {-\n-} then
      chompChunks vs es fs src (plusPtr pos 1) end (row + 1) 1 lastPos revChunks

    else
      let
        !newPos = plusPtr pos (getCharWidth word)
      in
      chompChunks vs es fs src newPos end row (col + 1) lastPos revChunks


toByteString :: ForeignPtr Word8 -> Ptr Word8 -> Ptr Word8 -> BSI.ByteString
toByteString src pos end =
  let
    !off = minusPtr pos (unsafeForeignPtrToPtr src)
    !len = minusPtr end pos
  in
  BSI.PS src off len



-- relies on external checks in chompChunks
chompTag :: VarTable -> Enums -> Fields -> ForeignPtr Word8 -> Ptr Word8 -> Ptr Word8 -> Row -> Col -> [Chunk] -> (# [Chunk], Ptr Word8, Row, Col #)
chompTag vs es fs src pos end row col revChunks =
  let
    (# newPos, newCol #) = Var.chompInnerChars pos end col
    !tagPos = plusPtr pos (-1)
    !word = unsafeIndex tagPos
  in
  if word == 0x24 {- $ -} then
    let
      !name = Name.fromPtr pos newPos
    in
    chompChunks vs es fs src newPos end row newCol newPos $
      CanopyField name : revChunks
  else
    let
      !name = Name.fromPtr tagPos newPos
    in
    if 0x30 {-0-} <= word && word <= 0x39 {-9-} then
      let
        (enum, newEnums) =
          lookupEnum (word - 0x30) name es
      in
      chompChunks vs newEnums fs src newPos end row newCol newPos $
        JsEnum enum : revChunks

    else if 0x61 {-a-} <= word && word <= 0x7A {-z-} then
      let
        (field, newFields) =
          lookupField name fs
      in
      chompChunks vs es newFields src newPos end row newCol newPos $
        JsField field : revChunks

    else if name == "DEBUG" then
      chompChunks vs es fs src newPos end row newCol newPos (Debug : revChunks)

    else if name == "PROD" then
      chompChunks vs es fs src newPos end row newCol newPos (Prod : revChunks)

    else
      case Map.lookup name vs of
        Just chunk ->
          chompChunks vs es fs src newPos end row newCol newPos (chunk : revChunks)

        Nothing ->
          (# revChunks, pos, row, col #)



-- FIELDS


type Fields =
  Map.Map Name.Name Int


lookupField :: Name.Name -> Fields -> (Int, Fields)
lookupField name fields =
  case Map.lookup name fields of
    Just n ->
      ( n, fields )

    Nothing ->
      let n = Map.size fields in
      ( n, Map.insert name n fields )



-- ENUMS


type Enums =
  Map.Map Word8 (Map.Map Name.Name Int)


lookupEnum :: Word8 -> Name.Name -> Enums -> (Int, Enums)
lookupEnum word var allEnums =
  let
    enums =
      Map.findWithDefault Map.empty word allEnums
  in
    case Map.lookup var enums of
      Just n ->
        ( n, allEnums )

      Nothing ->
        let n = Map.size enums in
        ( n, Map.insert word (Map.insert var n enums) allEnums )



-- PROCESS IMPORTS


type VarTable =
  Map.Map Name.Name Chunk


toVarTable :: Pkg.Name -> Foreigns -> [Src.Import] -> VarTable
toVarTable pkg foreigns = List.foldl' (addImport pkg foreigns) Map.empty


addImport :: Pkg.Name -> Foreigns -> VarTable -> Src.Import -> VarTable
addImport pkg foreigns vtable (Src.Import (Ann.At _ importName) maybeAlias exposing _isLazy) =
  if Name.isKernel importName then
    case maybeAlias of
      Just alias ->
        InternalError.report
          "Canopy.Kernel.addImport"
          ("Cannot use `as " <> Text.pack (Name.toChars alias) <> "` with kernel import `" <> Text.pack (Name.toChars importName) <> "`")
          "Kernel modules cannot be aliased with `as`. The parser should have rejected this syntax."

      Nothing ->
        let
          home = Name.getKernel importName
          add table name =
            Map.insert (Name.sepBy 0x5F {-_-} home name) (JsVar home name) table
        in
        List.foldl' add vtable (toNames exposing)

  else
    let
      home = ModuleName.Canonical (Map.findWithDefault pkg importName foreigns) importName
      prefix = toPrefix importName maybeAlias
      add table name =
        Map.insert (Name.sepBy 0x5F {-_-} prefix name) (CanopyVar home name) table
    in
    List.foldl' add vtable (toNames exposing)


toPrefix :: Name.Name -> Maybe Name.Name -> Name.Name
toPrefix home maybeAlias =
  case maybeAlias of
    Just alias ->
      alias

    Nothing ->
      if Name.hasDot home then
        InternalError.report
          "Canopy.Kernel.toPrefix"
          ("Kernel import `" <> Text.pack (Name.toChars home) <> "` contains dots and needs an `as` alias")
          "Kernel modules with dots in the name must be imported with an `as` alias so JavaScript generation can resolve names unambiguously."
      else
        home


toNames :: Src.Exposing -> [Name.Name]
toNames exposing =
  case exposing of
    Src.Open ->
      InternalError.report
        "Canopy.Kernel.toNames"
        "cannot have `exposing (..)` in kernel code"
        "Kernel modules must explicitly list every exported name so the JavaScript generator can produce correct variable table entries. Open exports are not permitted in kernel source files."

    Src.Explicit exposedList ->
      fmap toName exposedList


toName :: Src.Exposed -> Name.Name
toName exposed =
  case exposed of
    Src.Lower (Ann.At _ name) ->
      name

    Src.Upper (Ann.At _ name) Src.Private ->
      name

    Src.Upper _ (Src.Public _) ->
      InternalError.report
        "Canopy.Kernel.toName"
        "cannot have Maybe(..) syntax in kernel code header"
        "Kernel code headers must not use public union exposure syntax (e.g. Maybe(..)). Only simple names are allowed in kernel exposing lists."

    Src.Operator _ _ ->
      InternalError.report
        "Canopy.Kernel.toName"
        "cannot use binops in kernel code"
        "Kernel source files may only expose lower-case names and upper-case type names. Binary operator exposure is not supported in kernel code."



-- BINARY


instance Binary Chunk where
  put chunk =
    case chunk of
      JS a       -> putWord8 0 >> put a
      CanopyVar a b -> putWord8 1 >> put a >> put b
      JsVar a b  -> putWord8 2 >> put a >> put b
      CanopyField a -> putWord8 3 >> put a
      JsField a  -> putWord8 4 >> put a
      JsEnum a   -> putWord8 5 >> put a
      Debug      -> putWord8 6
      Prod       -> putWord8 7

  get =
    do  word <- getWord8
        case word of
          0 -> fmap  JS get
          1 -> Monad.liftM2 CanopyVar get get
          2 -> Monad.liftM2 JsVar get get
          3 -> fmap  CanopyField get
          4 -> fmap  JsField get
          5 -> fmap  JsEnum get
          6 -> return Debug
          7 -> return Prod
          n -> InternalError.report
            "Canopy.Kernel.Chunk.get"
            ("Unknown Chunk tag " <> Text.pack (show n) <> " during deserialization (valid: 0-7)")
            "Encountered an unknown tag while deserializing a Kernel Chunk. The binary data may be corrupted or from an incompatible compiler version."
