# Plan 18 — Replace String-Based HashValue

**Priority:** Tier 3 (Performance)
**Effort:** 4 hours
**Risk:** Low
**Files:** `packages/canopy-builder/src/Builder/Hash.hs`, `packages/canopy-builder/src/Builder/Incremental.hs`

---

## Problem

`type HashValue = String` (Hash.hs:48) represents a 64-character hex SHA-256 digest as a Haskell `String` — a linked list of 64 `Char` heap cells. For 1,000 modules with two hashes each, that's 128,000 `Char` allocations just for hash storage.

Additionally, `hashDependencies` builds intermediate `String` values per dependency via `show moduleName ++ ":" ++ hashValue` and then concatenates them with `unlines`.

## Implementation

### Step 1: Replace type alias with newtype over ShortByteString

```haskell
-- Before:
type HashValue = String

-- After:
import qualified Data.ByteString.Short as SBS

-- | SHA-256 digest stored as raw bytes (32 bytes, not 64-char hex).
newtype HashValue = HashValue { unHashValue :: SBS.ShortByteString }
  deriving (Eq, Ord, Show)

-- | Create a HashValue from a strict ByteString hash output.
fromDigest :: BS.ByteString -> HashValue
fromDigest = HashValue . SBS.toShort

-- | Convert to hex string for JSON serialization.
toHexText :: HashValue -> Text
toHexText (HashValue sbs) = Text.pack (BS.unpack (SBS.fromShort sbs) >>= toHex)
  where
    toHex b = [hexDigit (b `shiftR` 4), hexDigit (b .&. 0x0F)]
    hexDigit n | n < 10 = chr (ord '0' + fromIntegral n)
               | otherwise = chr (ord 'a' + fromIntegral n - 10)

-- | Parse from hex string (JSON deserialization).
fromHexText :: Text -> Maybe HashValue
fromHexText hex = ...
```

`ShortByteString` is 32 bytes (raw digest) instead of 64 `Char` cells (~1KB on 64-bit GHC). This is a 30x reduction in hash storage.

### Step 2: Update hashFile and hashDependencies

```haskell
-- hashFile: compute SHA-256, return raw bytes
hashFile :: FilePath -> IO HashValue
hashFile path = do
  content <- BS.readFile path
  pure (fromDigest (SHA256.hash content))

-- hashDependencies: compute SHA-256 of concatenated dependency info
hashDependencies :: Map ModuleName.Raw HashValue -> HashValue
hashDependencies deps =
  fromDigest (SHA256.hash (BS.concat depBytes))
  where
    depBytes = Map.foldlWithKey' (\acc name hash ->
      acc ++ [encodeModuleName name, SBS.fromShort (unHashValue hash)]
      ) [] deps
```

### Step 3: Update JSON serialization in Incremental.hs

The build cache is serialized as JSON. Update the `ToJSON`/`FromJSON` instances:

```haskell
instance Aeson.ToJSON HashValue where
  toJSON = Aeson.String . Hash.toHexText

instance Aeson.FromJSON HashValue where
  parseJSON = Aeson.withText "HashValue" $ \t ->
    case Hash.fromHexText t of
      Just h -> pure h
      Nothing -> fail "Invalid hex hash"
```

### Step 4: Fix ModuleName.Raw serialization

Replace `show moduleName` with a proper serialization:

```haskell
-- Before:
let moduleStr = show moduleName

-- After:
let moduleStr = Name.toChars moduleName
```

## Validation

```bash
# Clear cache to force rebuild with new format
rm -rf canopy-stuff
make build && make test
```

## Acceptance Criteria

- `HashValue` is a `newtype` over `ShortByteString`, not a `String` type alias
- Zero `String` intermediates in hash computation
- JSON serialization uses hex encoding
- `make build && make test` passes
