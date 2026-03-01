{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | HTML page generation for the Canopy compiler.
--
-- Generates complete HTML pages that embed compiled JavaScript. Used by
-- @canopy make --output=index.html@ and the development server.
--
-- == Security
--
-- Generated pages include a Content-Security-Policy meta tag that restricts
-- script sources to inline scripts only (required for the embedded JS) and
-- prevents loading scripts from external origins. All HTML attribute values
-- are escaped to prevent injection.
--
-- @since 0.19.1
module Generate.Html
  ( sandwich,
    sandwichWithPrefetch,
    escapeHtmlAttr,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Canopy.Data.Name as Name
import Text.RawString.QQ (r)

-- SANDWICH

-- | Wrap compiled JavaScript in a complete HTML page.
--
-- Generates an HTML5 document with the compiled JavaScript embedded in a
-- @\<script\>@ tag. The page initializes the Canopy application on a
-- @\<pre\>@ element.
--
-- Includes a Content-Security-Policy meta tag to restrict script sources.
--
-- @since 0.19.1
sandwich :: Name.Name -> Builder -> Builder
sandwich moduleName javascript =
  let name = Name.toBuilder moduleName
   in [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'unsafe-inline'">
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

  // Create Elm alias for backward compatibility
  window.Elm = window.Canopy;

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
-- Includes a Content-Security-Policy meta tag to restrict script sources.
--
-- @since 0.19.2
sandwichWithPrefetch :: Name.Name -> Builder -> [FilePath] -> Builder
sandwichWithPrefetch moduleName javascript chunkFilenames =
  let name = Name.toBuilder moduleName
   in [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'unsafe-inline'">
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

  // Create Elm alias for backward compatibility
  window.Elm = window.Canopy;

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
--
-- The filename is escaped for safe inclusion in an HTML attribute value,
-- preventing attribute injection via crafted filenames.
--
-- @since 0.19.2
prefetchTag :: FilePath -> Builder
prefetchTag filename =
  BB.stringUtf8 "  <link rel=\"prefetch\" href=\""
    <> BB.stringUtf8 (escapeHtmlAttr filename)
    <> BB.stringUtf8 "\">\n"

-- | Escape a string for safe inclusion in an HTML attribute value.
--
-- Replaces @&@, @\"@, @'@, @\<@, and @>@ with their HTML entity
-- equivalents. This prevents attribute breakout and HTML injection
-- when inserting user-controlled values (e.g., chunk filenames) into
-- HTML attributes.
--
-- @since 0.19.2
escapeHtmlAttr :: String -> String
escapeHtmlAttr = concatMap escapeChar
  where
    escapeChar '&' = "&amp;"
    escapeChar '"' = "&quot;"
    escapeChar '\'' = "&#39;"
    escapeChar '<' = "&lt;"
    escapeChar '>' = "&gt;"
    escapeChar c = [c]
