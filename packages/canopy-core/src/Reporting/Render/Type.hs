{-# LANGUAGE OverloadedStrings #-}

module Reporting.Render.Type
  ( Context (..),
    lambda,
    apply,
    tuple,
    record,
    vrecordSnippet,
    vrecord,
    srcToDoc,
    canToDoc,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Reporting.Annotation as Ann
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type.Localizer as Localizer

-- TO DOC

data Context
  = None
  | Func
  | App

lambda :: Context -> Doc -> Doc -> [Doc] -> Doc
lambda context arg1 arg2 args =
  let lambdaDoc =
        Doc.align $ Doc.sep (arg1 : fmap ("->" <+>) (arg2 : args))
   in case context of
        None -> lambdaDoc
        Func -> Doc.cat ["(", lambdaDoc, ")"]
        App -> Doc.cat ["(", lambdaDoc, ")"]

apply :: Context -> Doc -> [Doc] -> Doc
apply context name args =
  case args of
    [] ->
      name
    _ : _ ->
      let applyDoc =
            Doc.hang 4 (Doc.sep (name : args))
       in case context of
            App -> Doc.cat ["(", applyDoc, ")"]
            Func -> applyDoc
            None -> applyDoc

tuple :: Doc -> Doc -> [Doc] -> Doc
tuple a b cs =
  let entries =
        zipWith (<+>) ("(" : repeat ",") (a : b : cs)
   in Doc.align $ Doc.sep [Doc.cat entries, ")"]

record :: [(Doc, Doc)] -> Maybe Doc -> Doc
record entries maybeExt =
  case (fmap entryToDoc entries, maybeExt) of
    ([], Nothing) ->
      "{}"
    (fields, Nothing) ->
      Doc.align . Doc.sep $
        [ Doc.cat (zipWith (<+>) ("{" : repeat ",") fields),
          "}"
        ]
    (fields, Just ext) ->
      Doc.align . Doc.sep $
        [ Doc.hang 4 . Doc.sep $
            [ "{" <+> ext,
              Doc.cat (zipWith (<+>) ("|" : repeat ",") fields)
            ],
          "}"
        ]

entryToDoc :: (Doc, Doc) -> Doc
entryToDoc (fieldName, fieldType) =
  Doc.hang 4 (Doc.sep [fieldName <+> ":", fieldType])

vrecordSnippet :: (Doc, Doc) -> [(Doc, Doc)] -> Doc
vrecordSnippet entry entries =
  let field = "{" <+> entryToDoc entry
      fields = fmap (((<+>)) ",") (fmap entryToDoc entries <> ["..."])
   in Doc.vcat (field : (fields <> ["}"]))

vrecord :: [(Doc, Doc)] -> Maybe Doc -> Doc
vrecord entries maybeExt =
  case (fmap entryToDoc entries, maybeExt) of
    ([], Nothing) ->
      "{}"
    (fields, Nothing) ->
      Doc.vcat (zipWith (<+>) ("{" : repeat ",") fields <> ["}"])
    (fields, Just ext) ->
      Doc.vcat
        [ Doc.hang 4 . Doc.vcat $
            [ "{" <+> ext,
              Doc.cat (zipWith (<+>) ("|" : repeat ",") fields)
            ],
          "}"
        ]

-- SOURCE TYPE TO DOC

srcToDoc :: Context -> Src.Type -> Doc
srcToDoc context (Ann.At _ tipe) =
  case tipe of
    Src.TLambda arg1 result ->
      let (arg2, rest) = collectSrcArgs result
       in lambda
            context
            (srcToDoc Func arg1)
            (srcToDoc Func arg2)
            (fmap (srcToDoc Func) rest)
    Src.TVar name ->
      Doc.fromName name
    Src.TType _ name args ->
      apply
        context
        (Doc.fromName name)
        (fmap (srcToDoc App) args)
    Src.TTypeQual _ home name args ->
      apply
        context
        (Doc.fromName home <> "." <> Doc.fromName name)
        (fmap (srcToDoc App) args)
    Src.TRecord fields ext ->
      record
        (fmap srcFieldToDocs fields)
        (fmap (Doc.fromName . Ann.toValue) ext)
    Src.TUnit ->
      "()"
    Src.TTuple a b cs ->
      tuple
        (srcToDoc None a)
        (srcToDoc None b)
        (fmap (srcToDoc None) cs)

srcFieldToDocs :: (Ann.Located Name.Name, Src.Type) -> (Doc, Doc)
srcFieldToDocs (Ann.At _ fieldName, fieldType) =
  ( Doc.fromName fieldName,
    srcToDoc None fieldType
  )

collectSrcArgs :: Src.Type -> (Src.Type, [Src.Type])
collectSrcArgs tipe =
  case tipe of
    Ann.At _ (Src.TLambda a result) ->
      let (b, cs) = collectSrcArgs result
       in (a, b : cs)
    _ ->
      (tipe, [])

-- CANONICAL TYPE TO DOC

canToDoc :: Localizer.Localizer -> Context -> Can.Type -> Doc
canToDoc localizer context tipe =
  case tipe of
    Can.TLambda arg1 result ->
      let (arg2, rest) = collectArgs result
       in lambda
            context
            (canToDoc localizer Func arg1)
            (canToDoc localizer Func arg2)
            (fmap (canToDoc localizer Func) rest)
    Can.TVar name ->
      Doc.fromName name
    Can.TType home name args ->
      apply
        context
        (Localizer.toDoc localizer home name)
        (fmap (canToDoc localizer App) args)
    Can.TRecord fields ext ->
      record
        (fmap (canFieldToDoc localizer) (Can.fieldsToList fields))
        (fmap Doc.fromName ext)
    Can.TUnit ->
      "()"
    Can.TTuple a b maybeC ->
      tuple
        (canToDoc localizer None a)
        (canToDoc localizer None b)
        (fmap (canToDoc localizer None) (Maybe.maybeToList maybeC))
    Can.TAlias home name args _ ->
      apply
        context
        (Localizer.toDoc localizer home name)
        (fmap (canToDoc localizer App . snd) args)

canFieldToDoc :: Localizer.Localizer -> (Name.Name, Can.Type) -> (Doc, Doc)
canFieldToDoc localizer (name, tipe) =
  ( Doc.fromName name,
    canToDoc localizer None tipe
  )

collectArgs :: Can.Type -> (Can.Type, [Can.Type])
collectArgs tipe =
  case tipe of
    Can.TLambda a rest ->
      let (b, cs) = collectArgs rest
       in (a, b : cs)
    _ ->
      (tipe, [])
