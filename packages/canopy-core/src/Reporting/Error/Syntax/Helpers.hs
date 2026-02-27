{-# LANGUAGE OverloadedStrings #-}

-- | Shared helper utilities for syntax error rendering.
--
-- This module provides region construction helpers and shared documentation
-- fragments used across all syntax error rendering sub-modules.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Helpers
  ( -- * Region construction
    toRegion,
    toWiderRegion,
    toKeywordRegion,
    -- * Context types
    Context (..),
    Node (..),
    -- * Context helpers
    getDefName,
    isWithin,
    -- * Diagnostic wrapping
    wrapReport,
    -- * Space error rendering
    toSpaceReport,
    -- * Shared documentation
    noteForCaseError,
    noteForCaseIndentError,
    noteForPortsInPackage,
  )
where

import qualified Data.Char as Char
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import Data.Word (Word16)
import Parse.Primitives (Col, Row)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Types (Space (..))
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Construct a zero-width region at the given position.
toRegion :: Row -> Col -> Ann.Region
toRegion row col =
  let pos = Ann.Position row col
   in Ann.Region pos pos

-- | Construct a region that extends @extra@ columns to the right.
toWiderRegion :: Row -> Col -> Word16 -> Ann.Region
toWiderRegion row col extra =
  Ann.Region
    (Ann.Position row col)
    (Ann.Position row (col + extra))

-- | Construct a region that covers a keyword starting at the given position.
toKeywordRegion :: Row -> Col -> [Char.Char] -> Ann.Region
toKeywordRegion row col keyword =
  Ann.Region
    (Ann.Position row col)
    (Ann.Position row (col + fromIntegral (length keyword)))

-- | Context type for expression reporting.
data Context
  = InNode Node Row Col Context
  | InDef Name.Name Row Col
  | InDestruct Row Col

-- | Node type for context tracking.
data Node
  = NRecord
  | NParens
  | NList
  | NFunc
  | NCond
  | NThen
  | NElse
  | NCase
  | NBranch
  deriving (Eq)

-- | Extract the definition name from a context, if any.
getDefName :: Context -> Maybe Name.Name
getDefName context =
  case context of
    InDestruct _ _ -> Nothing
    InDef name _ _ -> Just name
    InNode _ _ _ c -> getDefName c

-- | Check whether the current context is within a given node type.
isWithin :: Node -> Context -> Bool
isWithin desiredNode context =
  case context of
    InDestruct _ _ -> False
    InDef _ _ _ -> False
    InNode actualNode _ _ _ -> desiredNode == actualNode

-- | Wrap a 'Report.Report' into a 'Diag.Diagnostic' with structured metadata.
wrapReport :: Diag.ErrorCode -> Ann.Region -> Report.Report -> Diag.Diagnostic
wrapReport code _region report =
  Diag.makeDiagnostic
    code
    Diag.SError
    Diag.PhaseParse
    (Text.pack (Report._title report))
    (Text.pack ("Parse error: " <> Report._title report))
    (Diag.LabeledSpan (Report._region report) "error here" Diag.SpanPrimary)
    (Report._message report)

-- | Render a whitespace or comment error.
--
-- This function handles tab and endless multi-line comment errors.
-- It is shared across all syntax error rendering modules.
toSpaceReport :: Code.Source -> Space -> Row -> Col -> Report.Report
toSpaceReport source space row col =
  case space of
    HasTab ->
      let region = toRegion row col
       in Report.Report "NO TABS" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "I ran into a tab, but tabs are not allowed in Canopy files.",
                Doc.reflow $
                  "Replace the tab with spaces."
              )
    EndlessMultiComment ->
      let region = toWiderRegion row col 2
       in Report.Report "ENDLESS COMMENT" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "I cannot find the end of this multi-line comment:",
                Doc.stack
                  [ Doc.reflow "Add a -} somewhere after this to end the comment.",
                    Doc.toSimpleHint
                      "Multi-line comments can be nested in Canopy, so {- {- -} -} is a comment\
                      \ that happens to contain another comment. Like parentheses and curly braces,\
                      \ the start and end markers must always be balanced. Maybe that is the problem?"
                  ]
              )

-- | Documentation note for case expression errors.
noteForCaseError :: Doc.Doc
noteForCaseError =
  Doc.stack
    [ Doc.toSimpleNote $
        "Here is an example of a valid `case` expression for reference.",
      Doc.vcat $
        [ Doc.indent 4 $ Doc.fillSep [Doc.cyan "case", "maybeWidth", Doc.cyan "of"],
          Doc.indent 6 $ Doc.fillSep [Doc.blue "Just", "width", "->"],
          Doc.indent 8 $ Doc.fillSep ["width", "+", Doc.dullyellow "200"],
          "",
          Doc.indent 6 $ Doc.fillSep [Doc.blue "Nothing", "->"],
          Doc.indent 8 $ Doc.fillSep [Doc.dullyellow "400"]
        ],
      Doc.reflow $
        "Notice the indentation. Each pattern is aligned, and each branch is indented\
        \ a bit more than the corresponding pattern. That is important!"
    ]

-- | Documentation note for case expression indentation errors.
noteForCaseIndentError :: Doc.Doc
noteForCaseIndentError =
  Doc.stack
    [ Doc.toSimpleNote $
        "Sometimes I get confused by indentation, so try to make your `case` look\
        \ something like this:",
      Doc.vcat $
        [ Doc.indent 4 $ Doc.fillSep [Doc.cyan "case", "maybeWidth", Doc.cyan "of"],
          Doc.indent 6 $ Doc.fillSep [Doc.blue "Just", "width", "->"],
          Doc.indent 8 $ Doc.fillSep ["width", "+", Doc.dullyellow "200"],
          "",
          Doc.indent 6 $ Doc.fillSep [Doc.blue "Nothing", "->"],
          Doc.indent 8 $ Doc.fillSep [Doc.dullyellow "400"]
        ],
      Doc.reflow $
        "Notice the indentation! Patterns are aligned with each other. Same indentation.\
        \ The expressions after each arrow are all indented a bit more than the patterns.\
        \ That is important!"
    ]

-- | Documentation note explaining why packages cannot have ports.
noteForPortsInPackage :: Doc.Doc
noteForPortsInPackage =
  Doc.stack
    [ Doc.toSimpleNote $
        "One of the major goals of the package ecosystem is to be completely written\
        \ in Canopy. This means when you install a Canopy package, you can be sure you are safe\
        \ from security issues on install and that you are not going to get any runtime\
        \ exceptions coming from your new dependency. This design also sets the ecosystem\
        \ up to target other platforms more easily (like mobile phones, WebAssembly, etc.)\
        \ since no community code explicitly depends on JavaScript even existing.",
      Doc.reflow $
        "Given that overall goal, allowing ports in packages would lead to some pretty\
        \ surprising behavior. If ports were allowed in packages, you could install a\
        \ package but not realize that it brings in an indirect dependency that defines a\
        \ port. Now you have a program that does not work and the fix is to realize that\
        \ some JavaScript needs to be added for a dependency you did not even know about.\
        \ That would be extremely frustrating! \"So why not allow the package author to\
        \ include the necessary JS code as well?\" Now we are back in conflict with our\
        \ overall goal to keep all community packages free from runtime exceptions."
    ]
