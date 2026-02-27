# Plan 22 — Fix canopy.json Silent Parse Failures

**Priority:** Tier 4 (DX)
**Effort:** 4 hours
**Risk:** Low
**Files:** `packages/canopy-core/src/Canopy/Outline.hs`, `packages/canopy-core/src/Canopy/Licenses.hs`

---

## Problem

1. `Outline.read` (line 125) returns `Maybe Outline`, swallowing all decode errors. When `canopy.json` is malformed, the caller sees `Nothing` with no indication of what field is wrong.

2. The license field deserializer (Outline.hs:72) deserializes any license value as `Licenses.bsd3`, silently ignoring whatever was written. This is data loss.

3. No JSON Schema or field validation — typos in field names are silently ignored.

## Implementation

### Fix 1: Return decode errors from Outline.read

```haskell
-- Before:
read :: FilePath -> IO (Maybe Outline)
read path = do
  content <- BS.readFile path
  pure (Json.decode content)

-- After:
data OutlineError
  = OutlineNotFound
  | OutlineParseError !Text        -- JSON syntax error
  | OutlineFieldError !Text !Text  -- field name, error description
  deriving (Show)

read :: FilePath -> IO (Either OutlineError Outline)
read path = do
  exists <- Dir.doesFileExist path
  if not exists
    then pure (Left OutlineNotFound)
    else do
      content <- BS.readFile path
      case Json.decodeEither content of
        Left err -> pure (Left (OutlineParseError (Text.pack err)))
        Right outline -> pure (Right outline)
```

Update all callers of `Outline.read` to handle `Left` with a user-friendly error message.

### Fix 2: Fix license deserialization

```haskell
-- Before (silent data loss):
instance Json.FromJSON Licenses.License where
  parseJSON _ = pure Licenses.bsd3

-- After (validate the value):
instance Json.FromJSON Licenses.License where
  parseJSON = Aeson.withText "License" $ \t ->
    case Licenses.fromText t of
      Just license -> pure license
      Nothing -> fail ("Unknown license: " <> Text.unpack t
        <> ". Valid licenses: " <> intercalate ", " (map Licenses.toText Licenses.allLicenses))
```

This requires adding `Licenses.fromText` and `Licenses.allLicenses` if they don't exist.

### Fix 3: Warn on unknown fields

Add a post-decode validation that checks for unrecognized fields:

```haskell
validateOutline :: Aeson.Object -> Either OutlineError ()
validateOutline obj =
  let knownFields = Set.fromList ["type", "source-directories", "elm-version",
        "dependencies", "test-dependencies", "name", "summary", "license",
        "version", "exposed-modules"]
      actualFields = Set.fromList (Map.keys obj)
      unknown = Set.difference actualFields knownFields
  in if Set.null unknown
    then Right ()
    else Left (OutlineFieldError "canopy.json"
      ("Unknown fields: " <> Text.intercalate ", " (Set.toList unknown)
       <> ". These will be ignored."))
```

This surfaces typos like `"dependancies"` or `"source-directory"` immediately.

## Validation

```bash
make build && make test

# Manual tests:
echo '{"type": "application", "bad-field": true}' > test-canopy.json
canopy check  # Should warn about unknown field "bad-field"

echo '{invalid json' > test-canopy.json
canopy check  # Should show parse error with position

echo '{"type": "application", "license": "INVALID"}' > test-canopy.json
canopy check  # Should show "Unknown license: INVALID"
```

## Acceptance Criteria

- Malformed `canopy.json` produces a specific error message, not silent failure
- Invalid license values produce an error listing valid licenses
- Unknown fields produce a warning
- `make build && make test` passes
