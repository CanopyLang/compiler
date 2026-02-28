# Plan 02: Timing-Safe Hash Comparison

## Priority: HIGH
## Effort: Small (1-2 hours)
## Risk: Low — straightforward replacement

## Problem

All hash comparisons in `Builder/LockFile.hs` use standard `==` which is vulnerable to timing attacks. An attacker observing response times could potentially determine hash values byte-by-byte.

### Current Code (packages/canopy-builder/src/Builder/LockFile.hs)

```haskell
-- Line 181: Root hash comparison
pure (currentHex == _lockRootHash lf)

-- Line 401: Package hash skip check
| _lpHash lp == "sha256:not-cached" = pure (Right pkg)

-- Line 405: Package hash verification
pure (if actualHash == _lpHash lp ...)
```

## Implementation Plan

### Step 1: Create constant-time comparison utility

**File**: `packages/canopy-builder/src/Crypto/ConstantTime.hs` (NEW)

```haskell
module Crypto.ConstantTime (secureCompare) where

import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import Data.Bits (xor)
import Data.Word (Word8)

-- | Constant-time comparison of two Text values.
-- Returns True iff both texts are identical, without
-- leaking information about where they differ via timing.
secureCompare :: Text -> Text -> Bool
secureCompare a b =
  let ba = TE.encodeUtf8 a
      bb = TE.encodeUtf8 b
  in BS.length ba == BS.length bb
     && BS.foldl' (\acc (x, y) -> acc .|. (x `xor` y)) 0 (BS.zip ba bb) == 0
```

### Step 2: Replace all hash comparisons

**File**: `packages/canopy-builder/src/Builder/LockFile.hs`

- Line 181: Replace `currentHex == _lockRootHash lf` with `Crypto.secureCompare currentHex (_lockRootHash lf)`
- Line 405: Replace `actualHash == _lpHash lp` with `Crypto.secureCompare actualHash (_lpHash lp)`
- Line 401: Keep `==` for `"sha256:not-cached"` literal check (not security-sensitive)

### Step 3: Tests

**File**: `test/Unit/Crypto/ConstantTimeTest.hs` (NEW)

- Equal strings return True
- Different strings return False
- Different lengths return False
- Empty strings return True

## Dependencies
- None
