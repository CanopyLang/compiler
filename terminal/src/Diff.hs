{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Diff
  ( Args (..),
    run,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Details as Details
import Canopy.Docs (Alias, Binop, Documentation, Union, Value)
import qualified Canopy.Docs as Docs
import qualified Canopy.Magnitude as M
import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import Canopy.Version (Version)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData)
import Deps.Diff (Changes (..), ModuleChanges (..), PackageChanges (..))
import qualified Deps.Diff as Diff
import qualified Deps.Registry as Registry
import qualified Http
import qualified Reporting
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as D
import qualified Reporting.Exit as Exit
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Render.Type.Localizer as L
import qualified Reporting.Task as Task
import qualified Stuff

-- RUN

data Args
  = CodeVsLatest
  | CodeVsExactly Version
  | LocalInquiry Version Version
  | GlobalInquiry Name Version Version

run :: Args -> () -> IO ()
run args () =
  Reporting.attempt Exit.diffToReport . Task.run $
    ( do
        env <- getEnv
        runDiff env args
    )

-- ENVIRONMENT

data Env = Env
  { _maybeRoot :: Maybe FilePath,
    _cache :: Stuff.PackageCache,
    _manager :: Http.Manager,
    _registry :: Registry.ZokkaRegistries
  }

getEnv :: Task Env
getEnv =
  do
    maybeRoot <- Task.io Stuff.findRoot
    cache <- Task.io Stuff.getPackageCache
    zokkaCache <- Task.io Stuff.getZokkaCache
    manager <- Task.io Http.getManager
    reposConf <- Task.io Stuff.getOrCreateZokkaCustomRepositoryConfig
    reposData <- Task.eio Exit.DiffCustomReposDataProblem $ loadCustomRepositoriesData reposConf
    registry <- Task.eio Exit.DiffMustHaveLatestRegistry $ Registry.latest manager reposData zokkaCache reposConf
    return (Env maybeRoot cache manager registry)

-- DIFF

type Task a =
  Task.Task Exit.Diff a

runDiff :: Env -> Args -> Task ()
runDiff env@(Env _ _ _ registry) args =
  case args of
    GlobalInquiry name v1 v2 ->
      case Registry.getVersions' name registry of
        Right vsns ->
          do
            oldDocs <- getLocalDocs env name vsns (min v1 v2)
            newDocs <- getLocalDocs env name vsns (max v1 v2)
            writeDiff oldDocs newDocs
        Left suggestions ->
          Task.throw (Exit.DiffUnknownPackage name suggestions)
    LocalInquiry v1 v2 ->
      do
        (name, vsns) <- readOutline env
        oldDocs <- getLocalDocs env name vsns (min v1 v2)
        newDocs <- getLocalDocs env name vsns (max v1 v2)
        writeDiff oldDocs newDocs
    CodeVsLatest ->
      do
        (name, vsns) <- readOutline env
        oldDocs <- getLatestDocs env name vsns
        newDocs <- generateDocs env
        writeDiff oldDocs newDocs
    CodeVsExactly version ->
      do
        (name, vsns) <- readOutline env
        oldDocs <- getLocalDocs env name vsns version
        newDocs <- generateDocs env
        writeDiff oldDocs newDocs

-- GET DOCS

getLocalDocs :: Env -> Name -> Registry.KnownVersions -> Version -> Task Documentation
getLocalDocs (Env _ cache manager registry) name (Registry.KnownVersions latest previous) version =
  if latest == version || elem version previous
    then Task.eio (Exit.DiffDocsProblem version) $ Diff.getDocs cache registry manager name version
    else Task.throw (Exit.DiffUnknownVersion name version (latest : previous))

getLatestDocs :: Env -> Name -> Registry.KnownVersions -> Task Documentation
getLatestDocs (Env _ cache manager registry) name (Registry.KnownVersions latest _) =
  Task.eio (Exit.DiffDocsProblem latest) $ Diff.getDocs cache registry manager name latest

-- READ OUTLINE

readOutline :: Env -> Task (Name, Registry.KnownVersions)
readOutline (Env maybeRoot _ _ registry) =
  case maybeRoot of
    Nothing ->
      Task.throw Exit.DiffNoOutline
    Just root ->
      do
        result <- Task.io $ Outline.read root
        case result of
          Left err ->
            Task.throw (Exit.DiffBadOutline err)
          Right outline ->
            case outline of
              Outline.App _ ->
                Task.throw Exit.DiffApplication
              Outline.Pkg (Outline.PkgOutline pkg _ _ _ _ _ _ _) ->
                case Registry.getVersions pkg registry of
                  Just vsns -> return (pkg, vsns)
                  Nothing -> Task.throw Exit.DiffUnpublished

-- GENERATE DOCS

generateDocs :: Env -> Task Documentation
generateDocs (Env maybeRoot _ _ _) =
  case maybeRoot of
    Nothing ->
      Task.throw Exit.DiffNoOutline
    Just root ->
      do
        details <-
          Task.eio Exit.DiffBadDetails . BW.withScope $
            ( \scope ->
                Details.load Reporting.silent scope root
            )

        case Details._outline details of
          Details.ValidApp _ ->
            Task.throw Exit.DiffApplication
          Details.ValidPkg _ exposed _ ->
            case exposed of
              [] ->
                Task.throw Exit.DiffNoExposed
              e : es ->
                Task.eio Exit.DiffBadBuild $
                  Build.fromExposed Reporting.silent root details Build.KeepDocs (NE.List e es)

-- WRITE DIFF

writeDiff :: Documentation -> Documentation -> Task ()
writeDiff oldDocs newDocs =
  let changes = Diff.diff oldDocs newDocs
      localizer = L.fromNames (Map.union oldDocs newDocs)
   in (Task.io . Help.toStdout $ (toDoc localizer changes <> "\n"))

-- TO DOC

toDoc :: L.Localizer -> PackageChanges -> Doc
toDoc localizer changes@(PackageChanges added changed removed) =
  if null added && Map.null changed && null removed
    then "No API changes detected, so this is a" <+> D.green "PATCH" <+> "change."
    else
      let magDoc =
            D.fromChars (M.toChars (Diff.toMagnitude changes))

          header =
            "This is a" <+> D.green magDoc <+> "change."

          addedChunk =
            if null added
              then []
              else
                [ Chunk "ADDED MODULES" M.MINOR . D.vcat $ fmap D.fromName added
                ]

          removedChunk =
            if null removed
              then []
              else
                [ Chunk "REMOVED MODULES" M.MAJOR . D.vcat $ fmap D.fromName removed
                ]

          chunks =
            (addedChunk <> (removedChunk <> fmap (changesToChunk localizer) (Map.toList changed)))
       in D.vcat (header : "" : fmap chunkToDoc chunks)

data Chunk = Chunk
  { _title :: String,
    _magnitude :: M.Magnitude,
    _details :: Doc
  }

chunkToDoc :: Chunk -> Doc
chunkToDoc (Chunk title magnitude details) =
  let header =
        "----" <+> D.fromChars title <+> "-" <+> D.fromChars (M.toChars magnitude) <+> "----"
   in D.vcat
        [ D.dullcyan header,
          "",
          D.indent 4 details,
          "",
          ""
        ]

changesToChunk :: L.Localizer -> (Name.Name, ModuleChanges) -> Chunk
changesToChunk localizer (name, changes@(ModuleChanges unions aliases values binops)) =
  let magnitude =
        Diff.moduleChangeMagnitude changes

      (unionAdd, unionChange, unionRemove) =
        changesToDocTriple (unionToDoc localizer) unions

      (aliasAdd, aliasChange, aliasRemove) =
        changesToDocTriple (aliasToDoc localizer) aliases

      (valueAdd, valueChange, valueRemove) =
        changesToDocTriple (valueToDoc localizer) values

      (binopAdd, binopChange, binopRemove) =
        changesToDocTriple (binopToDoc localizer) binops
   in ( ((Chunk (Name.toChars name) magnitude . D.vcat) . List.intersperse "") . Maybe.catMaybes $
          [ changesToDoc "Added" unionAdd aliasAdd valueAdd binopAdd,
            changesToDoc "Removed" unionRemove aliasRemove valueRemove binopRemove,
            changesToDoc "Changed" unionChange aliasChange valueChange binopChange
          ]
      )

changesToDocTriple :: (k -> v -> Doc) -> Changes k v -> ([Doc], [Doc], [Doc])
changesToDocTriple entryToDoc (Changes added changed removed) =
  let indented (name, value) =
        D.indent 4 (entryToDoc name value)

      diffed (name, (oldValue, newValue)) =
        D.vcat
          [ "  - " <> entryToDoc name oldValue,
            "  + " <> entryToDoc name newValue,
            ""
          ]
   in ( fmap indented (Map.toList added),
        fmap diffed (Map.toList changed),
        fmap indented (Map.toList removed)
      )

changesToDoc :: String -> [Doc] -> [Doc] -> [Doc] -> [Doc] -> Maybe Doc
changesToDoc categoryName unions aliases values binops =
  if null unions && null aliases && null values && null binops
    then Nothing
    else Just . D.vcat $ (D.fromChars categoryName <> ":" : (unions <> (aliases <> (binops <> values))))

unionToDoc :: L.Localizer -> Name.Name -> Union -> Doc
unionToDoc localizer name (Docs.Union _ tvars ctors) =
  let setup =
        "type" <+> D.fromName name <+> D.hsep (fmap D.fromName tvars)

      ctorDoc (ctor, tipes) =
        typeDoc localizer (Type.Type ctor tipes)
   in D.hang 4 (D.sep (setup : zipWith (<+>) ("=" : repeat "|") (fmap ctorDoc ctors)))

aliasToDoc :: L.Localizer -> Name.Name -> Alias -> Doc
aliasToDoc localizer name (Docs.Alias _ tvars tipe) =
  let declaration =
        "type" <+> "alias" <+> D.hsep (fmap D.fromName (name : tvars)) <+> "="
   in D.hang 4 (D.sep [declaration, typeDoc localizer tipe])

valueToDoc :: L.Localizer -> Name.Name -> Value -> Doc
valueToDoc localizer name (Docs.Value _ tipe) =
  D.hang 4 $ D.sep [D.fromName name <+> ":", typeDoc localizer tipe]

binopToDoc :: L.Localizer -> Name.Name -> Binop -> Doc
binopToDoc localizer name (Docs.Binop _ tipe associativity (Docs.Precedence n)) =
  "(" <> D.fromName name <> ")" <+> ":" <+> typeDoc localizer tipe <> D.black details
  where
    details =
      "    (" <> D.fromName assoc <> "/" <> D.fromInt n <> ")"

    assoc =
      case associativity of
        Docs.Left -> "left"
        Docs.Non -> "non"
        Docs.Right -> "right"

typeDoc :: L.Localizer -> Type.Type -> Doc
typeDoc localizer = Type.toDoc localizer Type.None
