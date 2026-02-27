{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | HTML help page generation for the Canopy development server.
--
-- This module generates dynamic help and documentation pages served
-- by the development server. It provides runtime help information
-- about modules, compilation errors, and debugging tools.
--
-- == Key Features
--
-- * Dynamic HTML page generation with embedded JavaScript
-- * Module-specific help content and documentation
-- * Error reporting and debugging interface generation
-- * Interactive development tool integration
--
-- @since 0.19.1
module Develop.Generate.Help
  ( -- * Page Generation
    makePageHtml,
    makeCodeHtml,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.Name as Name
import qualified Json.Encode as Encode
import Text.RawString.QQ (r)

-- PAGES

makePageHtml :: Name.Name -> Maybe Encode.Value -> Builder
makePageHtml moduleName maybeFlags =
  [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <link type="text/css" rel="stylesheet" href="/_canopy/styles.css">
  <script src="/_canopy/canopy.js"></script>
</head>
<body>
<script>
Canopy.|]
    <> Name.toBuilder moduleName
    <> [r|.init({ flags: |]
    <> maybe "undefined" Encode.encode maybeFlags
    <> [r| });
</script>
</body>
</html>
|]

-- CODE

makeCodeHtml :: FilePath -> Builder -> Builder
makeCodeHtml title code =
  [r|<!DOCTYPE HTML>
<html>
<head>
  <meta charset="UTF-8">
  <title>|]
    <> B.stringUtf8 title
    <> [r|</title>
  <style type="text/css">
    @import url(/_canopy/source-code-pro.ttf);
    html, head, body, pre { margin: 0; height: 100%; }
    body { font-family: "Source Code Pro", monospace; }
  </style>
  <link type="text/css" rel="stylesheet" href="//cdnjs.cloudflare.com/ajax/libs/highlight.js/9.3.0/styles/default.min.css">
  <script src="//cdnjs.cloudflare.com/ajax/libs/highlight.js/9.3.0/highlight.min.js"></script>
  <script>if (hljs) { hljs.initHighlightingOnLoad(); }</script>
</head>
<body style="background-color: #F0F0F0;">
<pre><code>|]
    <> code
    <> [r|</code></pre>
</body>
</html>
|]
