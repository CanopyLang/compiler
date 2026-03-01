{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for package management.
--
-- Contains install, publish, bump, and diff commands for working
-- with Canopy packages.
--
-- @since 0.19.1
module CLI.Commands.Package
  ( createInstallCommand,
    createPublishCommand,
    createBumpCommand,
    createDiffCommand,
  )
where

import qualified Bump
import CLI.Documentation (reflowText, stackDocuments)
import CLI.Types (Command, (|--))
import qualified Diff
import qualified Install
import qualified Publish
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the install command for package management.
--
-- @since 0.19.1
createInstallCommand :: Command
createInstallCommand =
  Terminal.Command "install" Terminal.Uncommon details example args flags Install.run
  where
    details =
      "The `install` command fetches packages from <https://package.canopy-lang.org> for\
      \ use in your project:"
    example =
      stackDocuments
        [ reflowText
            "For example, if you want to get packages for HTTP and JSON, you would say:",
          PP.indent 4 . PP.green $
            PP.vcat
              [ "canopy install canopy/http",
                "canopy install canopy/json"
              ],
          reflowText
            "Notice that you must say the AUTHOR name and PROJECT name! After running those\
            \ commands, you could say `import Http` or `import Json.Decode` in your code.",
          reflowText
            "What if two projects use different versions of the same package? No problem!\
            \ Each project is independent, so there cannot be conflicts like that!"
        ]
    args = createInstallArgs
    flags = createInstallFlags

-- | Create the publish command for package distribution.
--
-- @since 0.19.1
createPublishCommand :: Command
createPublishCommand =
  Terminal.Command "publish" Terminal.Uncommon details example args Terminal.noFlags Publish.run
  where
    details =
      "The `publish` command publishes your package to a custom repository\
      \ so that anyone with access to the repository can use it."
    example =
      stackDocuments
        [ reflowText
            "For example, if you have a custom repository located at https://www.example.com/my-custom-repo you can run the following command",
          PP.indent 4 . PP.green $
            PP.vcat
              [ "Canopy publish https://www.example.com/my-custom-repo"
              ]
        ]
    args = createPublishArgs

-- | Create the bump command for version management.
--
-- @since 0.19.1
createBumpCommand :: Command
createBumpCommand =
  Terminal.Command "bump" Terminal.Uncommon details example Terminal.noArgs Terminal.noFlags Bump.run
  where
    details = "The `bump` command figures out the next version number based on API changes:"
    example =
      reflowText
        "Say you just published version 1.0.0, but then decided to remove a function.\
        \ I will compare the published API to what you have locally, figure out that\
        \ it is a MAJOR change, and bump your version number to 2.0.0. I do this with\
        \ all packages, so there cannot be MAJOR changes hiding in PATCH releases in Canopy!"

-- | Create the diff command for API change analysis.
--
-- @since 0.19.1
createDiffCommand :: Command
createDiffCommand =
  Terminal.Command "diff" Terminal.Uncommon details example args Terminal.noFlags Diff.run
  where
    details = "The `diff` command detects API changes:"
    example =
      stackDocuments
        [ reflowText
            "For example, to see what changed in the HTML package between\
            \ versions 1.0.0 and 2.0.0, you can say:",
          PP.indent 4 (PP.green "canopy diff canopy/html 1.0.0 2.0.0"),
          reflowText
            "Sometimes a MAJOR change is not actually very big, so\
            \ this can help you plan your upgrade timelines."
        ]
    args = createDiffArgs

-- ARGS AND FLAGS

createInstallArgs :: Terminal.Args Install.Args
createInstallArgs =
  Terminal.oneOf
    [ Terminal.require0 Install.NoArgs,
      Terminal.require1 Install.Install Terminal.package
    ]

createInstallFlags :: Terminal.Flags Install.Flags
createInstallFlags =
  Terminal.flags Install.Flags
    |-- Terminal.onOff "no-fallback" "Do not fall back to elm-lang.org when canopy-lang.org is unreachable. Use this to ensure packages are fetched only from the Canopy registry."

createPublishArgs :: Terminal.Args Publish.Args
createPublishArgs =
  Terminal.oneOf
    [ Terminal.require0 Publish.NoArgs,
      Terminal.require1 id (Publish.PublishToRepository <$> Terminal.repositoryLocalName)
    ]

createDiffArgs :: Terminal.Args Diff.Args
createDiffArgs =
  Terminal.oneOf
    [ Terminal.require0 Diff.CodeVsLatest,
      Terminal.require1 Diff.CodeVsExactly Terminal.version,
      Terminal.require2 Diff.LocalInquiry Terminal.version Terminal.version,
      Terminal.require3 Diff.GlobalInquiry Terminal.package Terminal.version Terminal.version
    ]
