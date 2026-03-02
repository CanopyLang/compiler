{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}

module Canopy.Compiler.Type.Extract
  ( fromAnnotation,
    fromType,
    Types (..),
    mergeMany,
    merge,
    fromInterface,
    fromDependencyInterface,
    fromMsg,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Utils.Type as Type
import qualified Canopy.Compiler.Type as CompilerType
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.InternalError as InternalError
import qualified Data.Set as Set

-- EXTRACTION

fromAnnotation :: Can.Annotation -> CompilerType.Type
fromAnnotation (Can.Forall _ astType) =
  fromType astType

fromType :: Can.Type -> CompilerType.Type
fromType astType =
  snd (run (extract astType))

extract :: Can.Type -> Extractor CompilerType.Type
extract astType =
  case astType of
    Can.TLambda arg result ->
      CompilerType.Lambda
        <$> extract arg
        <*> extract result
    Can.TVar x ->
      pure (CompilerType.Var x)
    Can.TType home name args ->
      addUnion (Opt.Global home name) (CompilerType.Type (toPublicName home name))
        <*> traverse extract args
    Can.TRecord fields ext ->
      do
        efields <- traverse (traverse extract) (Can.fieldsToList fields)
        pure (CompilerType.Record efields ext)
    Can.TUnit ->
      pure CompilerType.Unit
    Can.TTuple a b maybeC ->
      CompilerType.Tuple
        <$> extract a
        <*> extract b
        <*> traverse extract (Maybe.maybeToList maybeC)
    Can.TAlias home name args aliasType ->
      do
        addAlias (Opt.Global home name) ()
        _ <- extract (Type.dealias args aliasType)
        CompilerType.Type (toPublicName home name)
          <$> traverse (extract . snd) args

toPublicName :: ModuleName.Canonical -> Name.Name -> Name.Name
toPublicName (ModuleName.Canonical _ home) = Name.sepBy 0x2E {- . -} home

-- TRANSITIVELY AVAILABLE TYPES

newtype Types
  = Types (Map.Map ModuleName.Canonical Types_)
  -- PERF profile Opt.Global representation
  -- current representation needs less allocation
  -- but maybe the lookup is much worse
  deriving (Show)

data Types_ = Types_
  { _union_info :: Map.Map Name.Name Can.Union,
    _alias_info :: Map.Map Name.Name Can.Alias
  }
  deriving (Show)

mergeMany :: [Types] -> Types
mergeMany listOfTypes =
  case listOfTypes of
    [] -> Types Map.empty
    t : ts -> foldr merge t ts

merge :: Types -> Types -> Types
merge (Types types1) (Types types2) =
  Types (Map.union types1 types2)

fromInterface :: ModuleName.Raw -> Interface.Interface -> Types
fromInterface name (Interface.Interface pkg _ unions aliases _) =
  Types . Map.singleton (ModuleName.Canonical pkg name) $ Types_ (Map.map Interface.extractUnion unions) (Map.map Interface.extractAlias aliases)

fromDependencyInterface :: ModuleName.Canonical -> Interface.DependencyInterface -> Types
fromDependencyInterface home di =
  Types . Map.singleton home $
    ( case di of
        Interface.Public (Interface.Interface _ _ unions aliases _) ->
          Types_ (Map.map Interface.extractUnion unions) (Map.map Interface.extractAlias aliases)
        Interface.Private _ unions aliases ->
          Types_ unions aliases
    )

-- EXTRACT MODEL, MSG, AND ANY TRANSITIVE DEPENDENCIES

fromMsg :: Types -> Can.Type -> CompilerType.DebugMetadata
fromMsg types message =
  let (msgDeps, msgType) =
        run (extract message)

      (aliases, unions) =
        extractTransitive types noDeps msgDeps
   in CompilerType.DebugMetadata msgType aliases unions

extractTransitive :: Types -> Deps -> Deps -> ([CompilerType.Alias], [CompilerType.Union])
extractTransitive types (Deps seenAliases seenUnions) (Deps nextAliases nextUnions) =
  let aliases = Set.difference nextAliases seenAliases
      unions = Set.difference nextUnions seenUnions
   in if Set.null aliases && Set.null unions
        then ([], [])
        else
          let (newDeps, result) =
                run $
                  (,)
                    <$> traverse (extractAlias types) (Set.toList aliases)
                    <*> traverse (extractUnion types) (Set.toList unions)

              oldDeps =
                Deps (Set.union seenAliases nextAliases) (Set.union seenUnions nextUnions)

              remainingResult =
                extractTransitive types oldDeps newDeps
           in mappend result remainingResult

extractAlias :: Types -> Opt.Global -> Extractor CompilerType.Alias
extractAlias (Types dict) (Opt.Global home name) =
  let types_ =
        maybe
          (InternalError.report "Canopy.Compiler.Type.Extract.extractAlias"
            ("Module `" <> Text.pack (show home) <> "` missing from types dict with " <> Text.pack (show (Map.size dict)) <> " entries")
            "Every referenced module must be present in the transitively available Types. This indicates a dependency resolution bug.")
          id
          (Map.lookup home dict)
      (Can.Alias args aliasType) =
        maybe
          (InternalError.report "Canopy.Compiler.Type.Extract.extractAlias"
            ("Alias `" <> Text.pack (show name) <> "` missing from module `" <> Text.pack (show home) <> "` types (has " <> Text.pack (show (Map.size (_alias_info types_))) <> " aliases)")
            "Every referenced alias must be present in the module's alias info map. This indicates a dependency resolution bug.")
          id
          (Map.lookup name (_alias_info types_))
   in CompilerType.Alias (toPublicName home name) args <$> extract aliasType

extractUnion :: Types -> Opt.Global -> Extractor CompilerType.Union
extractUnion (Types dict) (Opt.Global home name) =
  if name == Name.list && home == ModuleName.list
    then return $ CompilerType.Union (toPublicName home name) ["a"] []
    else
      let pname = toPublicName home name
          types_ =
            maybe
              (InternalError.report "Canopy.Compiler.Type.Extract.extractUnion"
                ("Module `" <> Text.pack (show home) <> "` missing from types dict with " <> Text.pack (show (Map.size dict)) <> " entries")
                "Every referenced module must be present in the transitively available Types. This indicates a dependency resolution bug.")
              id
              (Map.lookup home dict)
          (Can.Union vars ctors _ _) =
            maybe
              (InternalError.report "Canopy.Compiler.Type.Extract.extractUnion"
                ("Union `" <> Text.pack (show name) <> "` missing from module `" <> Text.pack (show home) <> "` types (has " <> Text.pack (show (Map.size (_union_info types_))) <> " unions)")
                "Every referenced union must be present in the module's union info map. This indicates a dependency resolution bug.")
              id
              (Map.lookup name (_union_info types_))
       in CompilerType.Union pname vars <$> traverse extractCtor ctors

extractCtor :: Can.Ctor -> Extractor (Name.Name, [CompilerType.Type])
extractCtor (Can.Ctor ctor _ _ args) =
  (,) ctor <$> traverse extract args

-- DEPS

data Deps = Deps
  { _aliases :: Set.Set Opt.Global,
    _unions :: Set.Set Opt.Global
  }

{-# NOINLINE noDeps #-}
noDeps :: Deps
noDeps =
  Deps Set.empty Set.empty

-- EXTRACTOR

newtype Extractor a
  = Extractor
      ( forall result.
        Set.Set Opt.Global ->
        Set.Set Opt.Global ->
        (Set.Set Opt.Global -> Set.Set Opt.Global -> a -> result) ->
        result
      )

run :: Extractor a -> (Deps, a)
run (Extractor k) =
  k Set.empty Set.empty $ \aliases unions value ->
    (Deps aliases unions, value)

addAlias :: Opt.Global -> a -> Extractor a
addAlias alias value =
  Extractor $ \aliases unions ok ->
    ok (Set.insert alias aliases) unions value

addUnion :: Opt.Global -> a -> Extractor a
addUnion union value =
  Extractor $ \aliases unions ok ->
    ok aliases (Set.insert union unions) value

instance Functor Extractor where
  fmap func (Extractor k) =
    Extractor $ \aliases unions ok ->
      let ok1 a1 u1 value =
            ok a1 u1 (func value)
       in k aliases unions ok1

instance Applicative Extractor where
  pure value =
    Extractor $ \aliases unions ok ->
      ok aliases unions value

  (<*>) (Extractor kf) (Extractor kv) =
    Extractor $ \aliases unions ok ->
      let ok1 a1 u1 func =
            let ok2 a2 u2 value =
                  ok a2 u2 (func value)
             in kv a1 u1 ok2
       in kf aliases unions ok1

instance Monad Extractor where
  return = pure

  (>>=) (Extractor ka) callback =
    Extractor $ \aliases unions ok ->
      let ok1 a1 u1 value =
            case callback value of
              Extractor kb -> kb a1 u1 ok
       in ka aliases unions ok1
