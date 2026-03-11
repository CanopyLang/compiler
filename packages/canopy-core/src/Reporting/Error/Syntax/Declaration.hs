{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for declarations.
--
-- This module handles rendering of parse errors for top-level declarations,
-- including type aliases, custom types, value definitions, ports, and the
-- declaration-level dispatching logic.
--
-- Sub-modules:
--   * "Reporting.Error.Syntax.Declaration.DeclStart" - declaration start and port errors
--   * "Reporting.Error.Syntax.Declaration.DeclBody"  - type and definition body errors
--
-- @since 0.19.1
module Reporting.Error.Syntax.Declaration
  ( toDeclarationsReport,
    toDeclStartReport,
    toPortReport,
    toDeclTypeReport,
    toTypeAliasReport,
    toCustomTypeReport,
    toDeclDefReport,
  )
where

import Reporting.Error.Syntax.Declaration.DeclBody
  ( toCustomTypeReport,
    toDeclDefReport,
    toDeclTypeReport,
    toTypeAliasReport,
  )
import Reporting.Error.Syntax.Declaration.DeclStart
  ( toDeclStartReport,
    toPortReport,
  )
import Reporting.Error.Syntax.Helpers
  ( toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Types
  ( Decl (..),
  )
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report

-- | Render a declaration-level parse error.
toDeclarationsReport :: Code.Source -> Decl -> Report.Report
toDeclarationsReport source decl =
  case decl of
    DeclStart row col ->
      toDeclStartReport source row col
    DeclSpace space row col ->
      toSpaceReport source space row col
    Port port_ row col ->
      toPortReport source port_ row col
    DeclType declType row col ->
      toDeclTypeReport source declType row col
    DeclDef name declDef row col ->
      toDeclDefReport source name declDef row col
    DeclFreshLineAfterDocComment row col ->
      let region = toRegion row col
       in Report.Report "EXPECTING DECLARATION" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I just saw a doc comment, but then I got stuck here:",
                Doc.reflow $
                  "I was expecting to see the corresponding declaration next, starting on a fresh\
                  \ line with no indentation."
              )
    DeclImplMethodAlignment _ row col ->
      let region = toRegion row col
       in Report.Report "UNFINISHED IMPL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I am partway through parsing an impl declaration, but I got stuck here:",
                Doc.reflow $
                  "I was expecting to see another method definition aligned with the others."
              )
