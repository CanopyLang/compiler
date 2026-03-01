{-# LANGUAGE OverloadedStrings #-}

-- | Publish command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Publish
  ( Publish (..),
    publishToReport,
    newPackageOverview,
  )
where

import qualified Exit as BuildExit
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    badOutlineError,
    fixLine,
    mustHaveLatestRegistryError,
    noOutlineError,
    pkgNeedsExposingError,
    structuredError,
    structuredErrorNoFix,
  )

-- | Publish errors.
data Publish
  = PublishNoOutline
  | PublishBadOutline !String
  | PublishMissingTag !String
  | PublishCannotGetTag !String
  | PublishCannotGetTagData !String
  | PublishLocalChanges !String
  | PublishCannotGetZip !String
  | PublishCannotDecodeZip !String
  | PublishCustomRepositoryConfigDataError !String
  | PublishNoExposed
  | PublishNoSummary
  | PublishNoReadme
  | PublishShortReadme
  | PublishNoLicense
  | PublishBadDetails !FilePath
  | PublishApplication
  | PublishBuildProblem !BuildExit.BuildError
  | PublishNotInitialVersion !String
  | PublishAlreadyPublished !String
  | PublishInvalidBump !String
  | PublishCannotGetDocs !String
  | PublishBadBump !String
  | PublishCannotRegister !String
  | PublishMustHaveLatestRegistry
  | PublishNoGit
  | PublishWithNoRepositoryLocalName
  | PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig !String ![String]
  | PublishToStandardCanopyRepositoryUsingCanopy
  deriving (Show)

-- | Convert a 'Publish' error to a structured 'Report'.
publishToReport :: Publish -> Report
publishToReport PublishNoOutline = noOutlineError "canopy publish"
publishToReport (PublishBadOutline msg) = badOutlineError msg
publishToReport (PublishMissingTag tag) = publishMissingTagError tag
publishToReport (PublishCannotGetTag msg) = publishCannotGetTagError msg
publishToReport (PublishCannotGetTagData msg) = publishCannotGetTagDataError msg
publishToReport (PublishLocalChanges msg) = publishLocalChangesError msg
publishToReport (PublishCannotGetZip msg) = publishCannotGetZipError msg
publishToReport (PublishCannotDecodeZip msg) = publishCannotDecodeZipError msg
publishToReport (PublishCustomRepositoryConfigDataError msg) = publishRepoConfigError msg
publishToReport PublishNoExposed = pkgNeedsExposingError
publishToReport PublishNoSummary = publishNoSummaryError
publishToReport PublishNoReadme = publishNoReadmeError
publishToReport PublishShortReadme = publishShortReadmeError
publishToReport PublishNoLicense = publishNoLicenseError
publishToReport (PublishBadDetails path) = badDetailsError path
publishToReport PublishApplication = publishApplicationError
publishToReport (PublishBuildProblem buildErr) = BuildExit.toDoc buildErr
publishToReport (PublishNotInitialVersion msg) = publishNotInitialVersionError msg
publishToReport (PublishAlreadyPublished msg) = publishAlreadyPublishedError msg
publishToReport (PublishInvalidBump msg) = publishInvalidBumpError msg
publishToReport (PublishCannotGetDocs msg) = publishCannotGetDocsError msg
publishToReport (PublishBadBump msg) = publishBadBumpError msg
publishToReport (PublishCannotRegister msg) = publishCannotRegisterError msg
publishToReport PublishMustHaveLatestRegistry = mustHaveLatestRegistryError "publish"
publishToReport PublishNoGit = publishNoGitError
publishToReport PublishWithNoRepositoryLocalName = publishNoRepoNameError
publishToReport (PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig name suggestions) =
  publishRepoNotFoundError name suggestions
publishToReport PublishToStandardCanopyRepositoryUsingCanopy = publishStandardRepoError

-- | Message shown for new package creation guidance.
newPackageOverview :: Doc.Doc
newPackageOverview =
  Doc.vcat
    [ Doc.green "This appears to be a new package!",
      "",
      Doc.reflow "All new Canopy packages start at version 1.0.0 and use semantic",
      Doc.reflow "versioning to communicate changes to users."
    ]

publishMissingTagError :: String -> Report
publishMissingTagError tag =
  structuredError
    "MISSING GIT TAG"
    (Doc.reflow ("I cannot find the Git tag " ++ tag ++ " that should correspond to this version."))
    ( Doc.vcat
        [ Doc.reflow "Create and push the tag:",
          "",
          fixLine (Doc.green (Doc.fromChars ("git tag " ++ tag))),
          fixLine (Doc.green (Doc.fromChars ("git push origin " ++ tag)))
        ]
    )

publishCannotGetTagError :: String -> Report
publishCannotGetTagError msg =
  structuredError
    "GIT TAG ERROR"
    (Doc.reflow ("I had trouble reading Git tag information: " ++ msg))
    (Doc.reflow "Make sure you are in a Git repository with the correct tags pushed.")

publishCannotGetTagDataError :: String -> Report
publishCannotGetTagDataError msg =
  structuredErrorNoFix
    "GIT TAG DATA ERROR"
    (Doc.reflow ("I could not read the data for the Git tag: " ++ msg))

publishLocalChangesError :: String -> Report
publishLocalChangesError msg =
  structuredError
    "UNCOMMITTED CHANGES"
    (Doc.reflow ("Your local code has changes that are not committed: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Commit or stash your changes before publishing:",
          "",
          fixLine (Doc.green "git add -A && git commit -m \"prepare for publish\"")
        ]
    )

publishCannotGetZipError :: String -> Report
publishCannotGetZipError msg =
  structuredError
    "DOWNLOAD FAILED"
    (Doc.reflow ("I could not download the source code archive from GitHub: " ++ msg))
    (Doc.reflow "Check that the repository is public and the tag exists on GitHub.")

publishCannotDecodeZipError :: String -> Report
publishCannotDecodeZipError msg =
  structuredError
    "INVALID ARCHIVE"
    (Doc.reflow ("The downloaded source archive could not be decoded: " ++ msg))
    (Doc.reflow "This may indicate a corrupted download. Try publishing again.")

publishRepoConfigError :: String -> Report
publishRepoConfigError msg =
  structuredError
    "REPOSITORY CONFIG ERROR"
    (Doc.reflow ("There is a problem with the repository configuration: " ++ msg))
    (Doc.reflow "Check the repositories section of your canopy.json file.")

publishNoSummaryError :: Report
publishNoSummaryError =
  structuredError
    "MISSING SUMMARY"
    (Doc.reflow "Your package does not have a summary. The summary field is required for published packages.")
    ( Doc.vcat
        [ Doc.reflow "Add a \"summary\" field to your canopy.json:",
          "",
          fixLine (Doc.green "\"summary\": \"A helpful one-line description of your package\"")
        ]
    )

publishNoReadmeError :: Report
publishNoReadmeError =
  structuredError
    "MISSING README"
    (Doc.reflow "I cannot find a README.md file in your project root. A README is required for published packages.")
    ( Doc.vcat
        [ Doc.reflow "Create a README.md file that explains:",
          "",
          fixLine (Doc.fromChars "- What your package does"),
          fixLine (Doc.fromChars "- How to install and use it"),
          fixLine (Doc.fromChars "- A quick example")
        ]
    )

publishShortReadmeError :: Report
publishShortReadmeError =
  structuredError
    "README TOO SHORT"
    (Doc.reflow "Your README.md is too short. A good README helps users understand your package.")
    (Doc.reflow "Add more detail about what your package does and how to use it.")

publishNoLicenseError :: Report
publishNoLicenseError =
  structuredError
    "MISSING LICENSE"
    (Doc.reflow "I cannot find a LICENSE file in your project root. A license is required for published packages.")
    (Doc.reflow "Add a LICENSE file. Common choices are BSD-3-Clause and MIT.")

publishApplicationError :: Report
publishApplicationError =
  structuredError
    "CANNOT PUBLISH APPLICATION"
    (Doc.reflow "You are trying to publish an application, but only packages can be published.")
    (Doc.reflow "If you meant to create a package, change the \"type\" field in canopy.json from \"application\" to \"package\".")

publishNotInitialVersionError :: String -> Report
publishNotInitialVersionError vsn =
  structuredError
    "WRONG INITIAL VERSION"
    (Doc.reflow ("The version in canopy.json is " ++ vsn ++ ", but new packages must start at version 1.0.0."))
    ( Doc.vcat
        [ Doc.reflow "Set the version to 1.0.0 in canopy.json:",
          "",
          fixLine (Doc.green "\"version\": \"1.0.0\"")
        ]
    )

publishAlreadyPublishedError :: String -> Report
publishAlreadyPublishedError vsn =
  structuredError
    "ALREADY PUBLISHED"
    (Doc.reflow ("Version " ++ vsn ++ " has already been published. You cannot publish the same version twice."))
    ( Doc.vcat
        [ Doc.reflow "To publish changes, bump the version:",
          "",
          fixLine (Doc.green "canopy bump")
        ]
    )

publishInvalidBumpError :: String -> Report
publishInvalidBumpError msg =
  structuredError
    "INVALID VERSION BUMP"
    (Doc.reflow ("The version bump is not valid: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Use canopy bump to calculate the correct version:",
          "",
          fixLine (Doc.green "canopy bump")
        ]
    )

publishCannotGetDocsError :: String -> Report
publishCannotGetDocsError msg =
  structuredError
    "DOCUMENTATION ERROR"
    (Doc.reflow ("I could not generate documentation for your package: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Make sure your project builds cleanly:",
          "",
          fixLine (Doc.green "canopy make")
        ]
    )

publishBadBumpError :: String -> Report
publishBadBumpError msg =
  structuredError
    "BAD VERSION BUMP"
    (Doc.reflow ("The version bump does not follow semantic versioning rules: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Use canopy bump to calculate the correct version:",
          "",
          fixLine (Doc.green "canopy bump")
        ]
    )

publishCannotRegisterError :: String -> Report
publishCannotRegisterError msg =
  structuredError
    "REGISTRATION FAILED"
    (Doc.reflow ("I could not register your package with the repository: " ++ msg))
    (Doc.reflow "Check your internet connection and try again.")

publishNoGitError :: Report
publishNoGitError =
  structuredError
    "NO GIT REPOSITORY"
    (Doc.reflow "I cannot find a Git repository in this directory. Publishing requires Git for version tracking.")
    ( Doc.vcat
        [ Doc.reflow "Initialize a Git repository:",
          "",
          fixLine (Doc.green "git init"),
          fixLine (Doc.green "git add -A"),
          fixLine (Doc.green "git commit -m \"initial commit\"")
        ]
    )

publishNoRepoNameError :: Report
publishNoRepoNameError =
  structuredError
    "MISSING REPOSITORY NAME"
    (Doc.reflow "You must specify which repository to publish to.")
    ( Doc.vcat
        [ Doc.reflow "Specify the repository name:",
          "",
          fixLine (Doc.green "canopy publish <repository-name>")
        ]
    )

publishRepoNotFoundError :: String -> [String] -> Report
publishRepoNotFoundError name suggestions =
  structuredError
    "REPOSITORY NOT FOUND"
    (Doc.reflow ("I cannot find a repository named \"" ++ name ++ "\" in your configuration."))
    (availableReposBlock suggestions)

availableReposBlock :: [String] -> Doc.Doc
availableReposBlock [] =
  Doc.reflow "No repositories are configured. Add a repositories section to canopy.json."
availableReposBlock repos =
  Doc.vcat
    [ Doc.reflow "Available repositories:",
      "",
      Doc.vcat (fmap (\r -> fixLine (Doc.green (Doc.fromChars r))) repos)
    ]

publishStandardRepoError :: Report
publishStandardRepoError =
  structuredErrorNoFix
    "CANNOT PUBLISH HERE"
    (Doc.reflow "Cannot publish to the standard Canopy repository from this tool.")
