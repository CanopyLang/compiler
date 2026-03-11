-- | Interface hash computation for early-cutoff optimization.
--
-- Most edits don't change a module's public interface (exported values,
-- types, unions). By hashing only the public-facing parts of a module,
-- we can detect when dependents can skip recompilation entirely.
--
-- This is the key optimization in incremental compilation: if module A
-- depends on module B, and B's source changes but its interface hash
-- stays the same, then A does not need to be recompiled.
--
-- @since 0.19.2
module Query.Interface
  ( -- * Interface Hashing
    computeInterfaceHash,
    computeExportHash,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.Package as Pkg
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as TE
import Data.Text (Text)
import qualified Data.Text as Text
import Query.Simple (ContentHash (..))

-- | Compute a hash of a module's public interface.
--
-- This hashes only the exported values, types, unions, and aliases.
-- Internal implementation details (unexported bindings, function bodies)
-- are excluded so that changes to private code don't trigger downstream
-- recompilation.
--
-- @since 0.19.2
computeInterfaceHash :: Interface.Interface -> ContentHash
computeInterfaceHash iface =
  ContentHash (SHA256.hash (BS.concat parts))
  where
    parts =
      [ hashPkg (Interface._home iface),
        hashNames (Map.keys (Interface._values iface)),
        hashNames (Map.keys (Interface._unions iface)),
        hashNames (Map.keys (Interface._aliases iface)),
        hashNames (Map.keys (Interface._binops iface))
      ]

-- | Compute a hash of module exports only (names, not types).
--
-- Even lighter than 'computeInterfaceHash' — only checks whether the
-- set of exported names changed. Useful for quick structural checks.
--
-- @since 0.19.2
computeExportHash :: Interface.Interface -> ContentHash
computeExportHash iface =
  ContentHash (SHA256.hash (hashNames allNames))
  where
    allNames =
      Map.keys (Interface._values iface)
        ++ Map.keys (Interface._unions iface)
        ++ Map.keys (Interface._aliases iface)

-- | Hash a package name.
hashPkg :: Pkg.Name -> BS.ByteString
hashPkg pkg = TE.encodeUtf8 (Text.pack (show pkg))

-- | Hash a list of names into a single bytestring.
hashNames :: [Name.Name] -> BS.ByteString
hashNames names =
  TE.encodeUtf8 (Text.intercalate "," (fmap nameToText names))

-- | Convert a Name to Text for hashing.
nameToText :: Name.Name -> Text
nameToText = Text.pack . Name.toChars
