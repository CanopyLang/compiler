{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Core types for the Canopy compiler pipeline.
--
-- Contains the 'SrcDir' type for specifying source directories and
-- 'ModuleResult' which holds everything needed to build final artifacts
-- from a compiled module.
--
-- @since 0.19.1
module Compiler.Types
  ( -- * Source Directories
    SrcDir (..),
    srcDirToString,

    -- * Module Results
    ModuleResult (..),
    fromDriverResult,
    moduleResultToModule,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Driver
import qualified Generate.JavaScript as JS

-- | Source directory types (pure, no dependencies).
data SrcDir
  = AbsoluteSrcDir FilePath
  | RelativeSrcDir FilePath
  deriving (Show, Eq)

-- | Convert a 'SrcDir' to a plain string path.
srcDirToString :: SrcDir -> String
srcDirToString (AbsoluteSrcDir path) = path
srcDirToString (RelativeSrcDir path) = path

-- | Unified module compilation result.
--
-- Holds everything needed to build final artifacts, whether the module
-- was freshly compiled or loaded from the incremental cache.
data ModuleResult = ModuleResult
  { mrModuleName :: !ModuleName.Raw,
    mrInterface :: !Interface.Interface,
    mrLocalGraph :: !Opt.LocalGraph,
    mrFFIInfo :: !(Map.Map String JS.FFIInfo),
    mrLazyImports :: !(Set.Set ModuleName.Canonical)
  }

-- | Convert a Driver.CompileResult into a ModuleResult.
fromDriverResult :: Driver.CompileResult -> ModuleResult
fromDriverResult result =
  ModuleResult
    { mrModuleName = extractModuleName canMod,
      mrInterface = Driver.compileResultInterface result,
      mrLocalGraph = Driver.compileResultLocalGraph result,
      mrFFIInfo = Driver.compileResultFFIInfo result,
      mrLazyImports = Can._lazyImports canMod
    }
  where
    canMod = Driver.compileResultModule result

-- | Extract the raw module name from a canonical module.
extractModuleName :: Can.Module -> ModuleName.Raw
extractModuleName canModule = ModuleName._module (Can._name canModule)

-- | Convert a 'ModuleResult' to a 'Build.Module' for artifact assembly.
moduleResultToModule :: ModuleResult -> Build.Module
moduleResultToModule mr = Build.Fresh (mrModuleName mr) (mrInterface mr) (mrLocalGraph mr)
