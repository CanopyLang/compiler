{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Generate.Html
  ( sandwich,
    sandwichWithPrefetch,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Canopy.Data.Name as Name
import Text.RawString.QQ (r)

-- SANDWICH

sandwich :: Name.Name -> Builder -> Builder
sandwich moduleName javascript =
  let name = Name.toBuilder moduleName
   in [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <title>|]
        <> name
        <> [r|</title>
  <style>body { padding: 0; margin: 0; }</style>
</head>

<body>

<pre id="canopy"></pre>

<script>
try {
|]
        <> javascript
        <> [r|

  // Create Canopy alias for backward compatibility
  window.Canopy = window.Elm;

  var app = Canopy.|]
        <> name
        <> [r|.init({ node: document.getElementById("canopy") });
}
catch (e)
{
  // display initialization errors (e.g. bad flags, infinite recursion)
  var header = document.createElement("h1");
  header.style.fontFamily = "monospace";
  header.innerText = "Initialization Error";
  var pre = document.getElementById("canopy");
  document.body.insertBefore(header, pre);
  pre.innerText = e;
  throw e;
}
</script>

</body>
</html>|]

-- | Generate HTML with prefetch hints for lazy-loaded chunks.
--
-- Like 'sandwich', but injects @\<link rel=\"prefetch\"\>@ tags in the
-- @\<head\>@ section for each provided chunk filename. This allows the
-- browser to speculatively fetch lazy chunks during idle time, reducing
-- latency when they are eventually needed.
--
-- When the chunk filename list is empty, this produces identical output
-- to 'sandwich'.
--
-- @since 0.19.2
sandwichWithPrefetch :: Name.Name -> Builder -> [FilePath] -> Builder
sandwichWithPrefetch moduleName javascript chunkFilenames =
  let name = Name.toBuilder moduleName
   in [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <title>|]
        <> name
        <> [r|</title>
  <style>body { padding: 0; margin: 0; }</style>
|]
        <> prefetchTags chunkFilenames
        <> [r|</head>

<body>

<pre id="canopy"></pre>

<script>
try {
|]
        <> javascript
        <> [r|

  // Create Canopy alias for backward compatibility
  window.Canopy = window.Elm;

  var app = Canopy.|]
        <> name
        <> [r|.init({ node: document.getElementById("canopy") });
}
catch (e)
{
  // display initialization errors (e.g. bad flags, infinite recursion)
  var header = document.createElement("h1");
  header.style.fontFamily = "monospace";
  header.innerText = "Initialization Error";
  var pre = document.getElementById("canopy");
  document.body.insertBefore(header, pre);
  pre.innerText = e;
  throw e;
}
</script>

</body>
</html>|]

-- | Generate @\<link rel=\"prefetch\"\>@ tags for a list of chunk filenames.
--
-- Each filename becomes a hint that the browser can fetch during idle time.
--
-- @since 0.19.2
prefetchTags :: [FilePath] -> Builder
prefetchTags = mconcat . map prefetchTag

-- | Generate a single @\<link rel=\"prefetch\"\>@ tag.
prefetchTag :: FilePath -> Builder
prefetchTag filename =
  BB.stringUtf8 "  <link rel=\"prefetch\" href=\""
    <> BB.stringUtf8 filename
    <> BB.stringUtf8 "\">\n"
