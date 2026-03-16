{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | CLI command definition for the @convert@ command.
--
-- Converts a pure Elm package to Canopy format by renaming @.elm@ files
-- to @.can@ and transforming @elm.json@ to @canopy.json@ with dependency
-- remapping. Unlike @migrate@ (which transforms source syntax), @convert@
-- targets complete packages for registry consumption.
--
-- == Usage
--
-- @
-- canopy convert path\/to\/elm-package                  -- convert in-place
-- canopy convert path\/to\/elm-package --output \/tmp\/out -- output to separate dir
-- canopy convert path\/to\/elm-package --dry-run         -- preview changes
-- canopy convert path\/to\/elm-package --report          -- show detailed report
-- @
--
-- @since 0.19.2
module CLI.Commands.Convert
  ( createConvertCommand,
  )
where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Types (Command, (|--))
import Control.Lens ((^.))
import qualified Convert
import Convert.Types (ConvertError (..), ConvertOptions (..), ConvertResult, convertErrors, convertFilesRenamed, convertProjectConverted)
import qualified Data.Text as Text
import qualified System.Directory as Dir
import qualified Terminal
import qualified Terminal.Output as Output
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP
import Reporting.Doc.ColorQQ (c)

-- | Intermediate flags record parsed from the command line.
data ConvertFlags = ConvertFlags
  { _cfDryRun :: !Bool,
    _cfOutput :: !(Maybe String),
    _cfReport :: !Bool
  }
  deriving (Eq, Show)

-- | Create the @convert@ command for transforming Elm packages to Canopy.
--
-- Accepts a required directory argument plus optional @--dry-run@,
-- @--output@, and @--report@ flags.
--
-- @since 0.19.2
createConvertCommand :: Command
createConvertCommand =
  Terminal.Command "convert" (Terminal.Common summary) details example args convertFlags runConvert
  where
    summary = "Convert an Elm package to Canopy format."
    details = "The `convert` command transforms Elm packages for the Canopy registry:"
    example = convertExample
    args = Terminal.required (Terminal.fileParser [])

-- | Help-text example block for the @convert@ command.
convertExample :: PP.Doc
convertExample =
  stackDocuments
    [ reflowText "For example:"
    , PP.indent 4 (PP.green "canopy convert path/to/elm-package")
    , reflowText "This renames .elm files to .can and converts elm.json to canopy.json with dependency remapping."
    , PP.indent 4 (PP.green "canopy convert path/to/elm-package --output /tmp/converted")
    , reflowText "Write the converted package to a separate output directory."
    , PP.indent 4 (PP.green "canopy convert path/to/elm-package --dry-run")
    , reflowText "Preview all changes without writing any files."
    ]

-- | Flag configuration for the @convert@ command.
convertFlags :: Terminal.Flags ConvertFlags
convertFlags =
  Terminal.flags ConvertFlags
    |-- Terminal.onOff "dry-run" "Show what would change without writing any files."
    |-- Terminal.flag "output" (Terminal.stringParser "DIR" "output directory") "Write the converted package to this directory instead of in-place."
    |-- Terminal.onOff "report" "Show a detailed conversion report."

-- | Command handler: translate CLI flags to 'ConvertOptions' and run conversion.
runConvert :: String -> ConvertFlags -> IO ()
runConvert dir (ConvertFlags dryRun outputDir showReport) = do
  absDir <- Dir.makeAbsolute dir
  absOutput <- mapM Dir.makeAbsolute outputDir
  let opts = ConvertOptions
        { _convertSourceDir = absDir
        , _convertOutputDir = absOutput
        , _convertDryRun = dryRun
        }
  result <- Convert.convertPackage opts
  reportResult showReport result

-- | Report the conversion result to the user.
reportResult :: Bool -> ConvertResult -> IO ()
reportResult showReport result
  | not (null (result ^. convertErrors)) = reportErrors result
  | otherwise = reportSuccess showReport result

-- | Report conversion errors.
reportErrors :: ConvertResult -> IO ()
reportErrors result =
  mapM_ printError (result ^. convertErrors)
  where
    printError = \case
      SourceDirNotFound path ->
        Print.println [c|{red|Error:} Source directory not found: #{path}|]
      NoElmJson path ->
        Print.println [c|{red|Error:} No elm.json found in: #{path}|]
      UnsupportedFeature path msg ->
        let msgStr = Text.unpack msg
        in Print.println [c|{red|Error:} Unsupported feature in #{path}: #{msgStr}|]
      FileError path msg ->
        let msgStr = Text.unpack msg
        in Print.println [c|{red|Error:} File error at #{path}: #{msgStr}|]

-- | Report a successful conversion.
reportSuccess :: Bool -> ConvertResult -> IO ()
reportSuccess showReport result = do
  let fileLabel = Output.showCount (result ^. convertFilesRenamed) "file"
  Print.println [c|{green|Conversion complete.} Renamed #{fileLabel} from .elm to .can.|]
  if result ^. convertProjectConverted
    then Print.println [c|  Converted elm.json -> canopy.json|]
    else pure ()
  if showReport
    then printDetailedReport result
    else pure ()

-- | Print a detailed conversion report.
printDetailedReport :: ConvertResult -> IO ()
printDetailedReport result = do
  Print.newline
  Print.println [c|{bold|Conversion Report}|]
  let fileCountStr = show (result ^. convertFilesRenamed)
  Print.println [c|  Files renamed:          #{fileCountStr}|]
  let projStatus = if result ^. convertProjectConverted then "yes" :: String else "no"
  Print.println [c|  Project file converted: #{projStatus}|]
