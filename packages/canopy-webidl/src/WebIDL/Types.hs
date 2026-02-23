{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Type-Safe Identifiers for WebIDL
--
-- Provides newtype wrappers for all identifier types to prevent
-- mixing up spec names, interface names, group names, etc.
--
-- @since 0.20.0
module WebIDL.Types
  ( -- * Specification Identifiers
    SpecName(..)
  , mkSpecName
  , specNameToText

    -- * Interface Identifiers
  , InterfaceName(..)
  , mkInterfaceName
  , interfaceNameToText

    -- * Group Identifiers
  , GroupName(..)
  , mkGroupName
  , groupNameToText

    -- * Package Identifiers
  , PackageName(..)
  , mkPackageName
  , packageNameToText

    -- * Module Identifiers
  , ModuleName(..)
  , mkModuleName
  , moduleNameToText

    -- * URL Types
  , SpecUrl(..)
  , mkSpecUrl
  , specUrlToText

    -- * File Paths
  , WebIdlPath(..)
  , mkWebIdlPath
  , webIdlPathToText

    -- * Validation
  , ValidatedName
  , validateName
  , unsafeValidatedName

    -- * Collections
  , SpecSet
  , InterfaceSet
  , emptySpecSet
  , singletonSpec
  , insertSpec
  , memberSpec
  , specSetToList

  , emptyInterfaceSet
  , singletonInterface
  , insertInterface
  , memberInterface
  , interfaceSetToList
  ) where

import Data.Aeson (FromJSON, ToJSON, FromJSONKey, ToJSONKey)
import Data.Char (isAlphaNum, isUpper)
import Data.Hashable (Hashable)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.String (IsString(..))
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)


-- | A WebIDL specification name (e.g., "dom", "fetch", "webaudio")
newtype SpecName = SpecName { unSpecName :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

instance IsString SpecName where
  fromString = SpecName . Text.pack

-- | Create a SpecName from Text
mkSpecName :: Text -> SpecName
mkSpecName = SpecName

-- | Convert SpecName to Text
specNameToText :: SpecName -> Text
specNameToText = unSpecName


-- | A WebIDL interface name (e.g., "Element", "Document", "AudioContext")
newtype InterfaceName = InterfaceName { unInterfaceName :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

instance IsString InterfaceName where
  fromString = InterfaceName . Text.pack

-- | Create an InterfaceName from Text
mkInterfaceName :: Text -> InterfaceName
mkInterfaceName = InterfaceName

-- | Convert InterfaceName to Text
interfaceNameToText :: InterfaceName -> Text
interfaceNameToText = unInterfaceName


-- | An API group name (e.g., "dom", "fetch", "audio")
newtype GroupName = GroupName { unGroupName :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

instance IsString GroupName where
  fromString = GroupName . Text.pack

-- | Create a GroupName from Text
mkGroupName :: Text -> GroupName
mkGroupName = GroupName

-- | Convert GroupName to Text
groupNameToText :: GroupName -> Text
groupNameToText = unGroupName


-- | A Canopy package name (e.g., "canopy/web-dom")
newtype PackageName = PackageName { unPackageName :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON)

instance IsString PackageName where
  fromString = PackageName . Text.pack

-- | Create a PackageName from Text
mkPackageName :: Text -> PackageName
mkPackageName = PackageName

-- | Convert PackageName to Text
packageNameToText :: PackageName -> Text
packageNameToText = unPackageName


-- | A Canopy module name (e.g., "Dom.Element")
newtype ModuleName = ModuleName { unModuleName :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON)

instance IsString ModuleName where
  fromString = ModuleName . Text.pack

-- | Create a ModuleName from Text
mkModuleName :: Text -> ModuleName
mkModuleName = ModuleName

-- | Convert ModuleName to Text
moduleNameToText :: ModuleName -> Text
moduleNameToText = unModuleName


-- | A URL pointing to a WebIDL specification
newtype SpecUrl = SpecUrl { unSpecUrl :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON)

instance IsString SpecUrl where
  fromString = SpecUrl . Text.pack

-- | Create a SpecUrl from Text
mkSpecUrl :: Text -> SpecUrl
mkSpecUrl = SpecUrl

-- | Convert SpecUrl to Text
specUrlToText :: SpecUrl -> Text
specUrlToText = unSpecUrl


-- | A file path for a WebIDL file
newtype WebIdlPath = WebIdlPath { unWebIdlPath :: Text }
  deriving (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, FromJSON, ToJSON)

instance IsString WebIdlPath where
  fromString = WebIdlPath . Text.pack

-- | Create a WebIdlPath from Text
mkWebIdlPath :: Text -> WebIdlPath
mkWebIdlPath = WebIdlPath

-- | Convert WebIdlPath to Text
webIdlPathToText :: WebIdlPath -> Text
webIdlPathToText = unWebIdlPath


-- | A validated identifier (non-empty, valid characters)
newtype ValidatedName = ValidatedName { unValidatedName :: Text }
  deriving (Eq, Ord, Show, Generic)

-- | Validate an identifier name
-- Returns Nothing if the name is invalid (empty or contains invalid chars)
validateName :: Text -> Maybe ValidatedName
validateName txt
  | Text.null txt = Nothing
  | not (isValidFirstChar (Text.head txt)) = Nothing
  | not (Text.all isValidChar txt) = Nothing
  | otherwise = Just (ValidatedName txt)
  where
    isValidFirstChar c = isUpper c || c == '_'
    isValidChar c = isAlphaNum c || c == '_'

-- | Create a ValidatedName without validation (use carefully)
unsafeValidatedName :: Text -> ValidatedName
unsafeValidatedName = ValidatedName


-- | A set of specification names
newtype SpecSet = SpecSet { unSpecSet :: Set SpecName }
  deriving (Eq, Show, Generic)
  deriving newtype (Semigroup, Monoid)

-- | Empty spec set
emptySpecSet :: SpecSet
emptySpecSet = SpecSet Set.empty

-- | Singleton spec set
singletonSpec :: SpecName -> SpecSet
singletonSpec = SpecSet . Set.singleton

-- | Insert a spec into the set
insertSpec :: SpecName -> SpecSet -> SpecSet
insertSpec name (SpecSet s) = SpecSet (Set.insert name s)

-- | Check membership
memberSpec :: SpecName -> SpecSet -> Bool
memberSpec name (SpecSet s) = Set.member name s

-- | Convert to list
specSetToList :: SpecSet -> [SpecName]
specSetToList (SpecSet s) = Set.toList s


-- | A set of interface names
newtype InterfaceSet = InterfaceSet { unInterfaceSet :: Set InterfaceName }
  deriving (Eq, Show, Generic)
  deriving newtype (Semigroup, Monoid)

-- | Empty interface set
emptyInterfaceSet :: InterfaceSet
emptyInterfaceSet = InterfaceSet Set.empty

-- | Singleton interface set
singletonInterface :: InterfaceName -> InterfaceSet
singletonInterface = InterfaceSet . Set.singleton

-- | Insert an interface into the set
insertInterface :: InterfaceName -> InterfaceSet -> InterfaceSet
insertInterface name (InterfaceSet s) = InterfaceSet (Set.insert name s)

-- | Check membership
memberInterface :: InterfaceName -> InterfaceSet -> Bool
memberInterface name (InterfaceSet s) = Set.member name s

-- | Convert to list
interfaceSetToList :: InterfaceSet -> [InterfaceName]
interfaceSetToList (InterfaceSet s) = Set.toList s
