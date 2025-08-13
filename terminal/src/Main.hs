{-# LANGUAGE OverloadedStrings #-}

module Main
  ( main,
  )
where

import qualified Bump
import qualified Canopy.Version as V
import qualified Data.List as List
import qualified Develop
import qualified Diff
import qualified Init
import qualified Install
import qualified Make
import qualified Publish
import qualified Repl
import Terminal (Command, Parser, (|--))
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import Text.PrettyPrint.ANSI.Leijen (Doc)
import qualified Text.PrettyPrint.ANSI.Leijen as P
import Text.Read (readMaybe)
import Prelude hiding (init)

-- MAIN

main :: IO ()
main =
  Terminal.app
    intro
    outro
    [ repl,
      init,
      reactor,
      make,
      install,
      bump,
      diff,
      publish
    ]

intro :: Doc
intro =
  P.vcat
    [ P.fillSep
        [ "Hi,",
          "thank",
          "you",
          "for",
          "trying",
          "out",
          P.green "Canopy",
          P.green (P.text (V.toChars V.compiler)) <> ".",
          "I hope you like it!"
        ],
      "",
      P.black "-------------------------------------------------------------------------------",
      P.black "I highly recommend working through <https://guide.canopy-lang.org> to get started.",
      P.black "It teaches many important concepts, including how to use `canopy` in the terminal.",
      P.black "-------------------------------------------------------------------------------"
    ]

outro :: Doc
outro =
  P.fillSep . fmap P.text $
    words
      "Be sure to ask on the Canopy slack if you run into trouble! Folks are friendly and\
      \ happy to help out. They hang out there because it is fun, so be kind to get the\
      \ best results!"

-- INIT

init :: Terminal.Command
init =
  let summary =
        "Start an Canopy project. It creates a starter canopy.json file and\
        \ provides a link explaining what to do from there."

      details =
        "The `init` command helps start Canopy projects:"

      example =
        reflow
          "It will ask permission to create an canopy.json file, the one thing common\
          \ to all Canopy projects. It also provides a link explaining what to do from there."
   in Terminal.Command "init" (Terminal.Common summary) details example Terminal.noArgs Terminal.noFlags Init.run

-- REPL

repl :: Command
repl =
  let summary =
        "Open up an interactive programming session. Type in Canopy expressions\
        \ like (2 + 2) or (String.length \"test\") and see if they equal four!"

      details =
        "The `repl` command opens up an interactive programming session:"

      example =
        reflow
          "Start working through <https://guide.canopy-lang.org> to learn how to use this!\
          \ It has a whole chapter that uses the REPL for everything, so that is probably\
          \ the quickest way to get started."

      replFlags =
        Terminal.flags Repl.Flags
          |-- Terminal.flag "interpreter" interpreter "Path to a alternate JS interpreter, like node or nodejs."
          |-- Terminal.onOff "no-colors" "Turn off the colors in the REPL. This can help if you are having trouble reading the values. Some terminals use a custom color scheme that diverges significantly from the standard ANSI colors, so another path may be to pick a more standard color scheme."
   in Terminal.Command "repl" (Terminal.Common summary) details example Terminal.noArgs replFlags Repl.run

interpreter :: Parser String
interpreter =
  Terminal.Parser
    { _singular = "interpreter",
      _plural = "interpreters",
      _parser = Just,
      _suggest = \_ -> return [],
      _examples = \_ -> return ["node", "nodejs"]
    }

-- REACTOR

reactor :: Command
reactor =
  let summary =
        "Compile code with a click. It opens a file viewer in your browser, and\
        \ when you click on an Canopy file, it compiles and you see the result."

      details =
        "The `reactor` command starts a local server on your computer:"

      example =
        reflow
          "After running that command, you would have a server at <http://localhost:8000>\
          \ that helps with development. It shows your files like a file viewer. If you\
          \ click on an Canopy file, it will compile it for you! And you can just press\
          \ the refresh button in the browser to recompile things."

      reactorFlags =
        Terminal.flags Develop.Flags
          |-- Terminal.flag "port" port_ "The port of the server (default: 8000)"
   in Terminal.Command "reactor" (Terminal.Common summary) details example Terminal.noArgs reactorFlags Develop.run

port_ :: Parser Int
port_ =
  Terminal.Parser
    { _singular = "port",
      _plural = "ports",
      _parser = readMaybe,
      _suggest = \_ -> return [],
      _examples = \_ -> return ["3000", "8000"]
    }

-- MAKE

make :: Command
make =
  let details =
        "The `make` command compiles Canopy code into JS or HTML:"

      example =
        stack
          [ reflow
              "For example:",
            P.indent 4 $ P.green "canopy make src/Main.can",
            reflow
              "This tries to compile a Canopy file named src/Main.can (also accepts .canopy), generating an index.html file if possible."
          ]

      makeFlags =
        Terminal.flags Make.Flags
          |-- Terminal.onOff "debug" "Turn on the time-travelling debugger. It allows you to rewind and replay events. The events can be imported/exported into a file, which makes for very precise bug reports!"
          |-- Terminal.onOff "optimize" "Turn on optimizations to make code smaller and faster. For example, the compiler renames record fields to be as short as possible and unboxes values to reduce allocation."
          |-- Terminal.onOff "watch" "Turn on file watcher"
          |-- Terminal.flag "output" Make.output "Specify the name of the resulting JS file. For example --output=assets/canopy.js to generate the JS at assets/canopy.js or --output=/dev/null to generate no output at all!"
          |-- Terminal.flag "report" Make.reportType "You can say --report=json to get error messages as JSON. This is only really useful if you are an editor plugin. Humans should avoid it!"
          |-- Terminal.flag "docs" Make.docsFile "Generate a JSON file of documentation for a package. Eventually it will be possible to preview docs with `reactor` because it is quite hard to deal with these JSON files directly."
          |-- Terminal.onOff "verbose" "Turn on verbose logging when compiling. Useful for debugging errors in the Zokka compiler itself."
   in Terminal.Command "make" Terminal.Uncommon details example (Terminal.zeroOrMore Terminal.canopyFile) makeFlags Make.run

-- INSTALL

install :: Command
install =
  let details =
        "The `install` command fetches packages from <https://package.canopy-lang.org> for\
        \ use in your project:"

      example =
        stack
          [ reflow
              "For example, if you want to get packages for HTTP and JSON, you would say:",
            P.indent 4 . P.green $
              P.vcat
                [ "canopy install canopy/http",
                  "canopy install canopy/json"
                ],
            reflow
              "Notice that you must say the AUTHOR name and PROJECT name! After running those\
              \ commands, you could say `import Http` or `import Json.Decode` in your code.",
            reflow
              "What if two projects use different versions of the same package? No problem!\
              \ Each project is independent, so there cannot be conflicts like that!"
          ]

      installArgs =
        Terminal.oneOf
          [ Terminal.require0 Install.NoArgs,
            Terminal.require1 Install.Install Terminal.package
          ]
   in Terminal.Command "install" Terminal.Uncommon details example installArgs Terminal.noFlags Install.run

-- PUBLISH

publish :: Command
publish =
  let details =
        "The `publish` command publishes your package to a custom repository\
        \ so that anyone with access to the repository can use it."

      example =
        stack
          [ reflow
              "For example, if you have a custom repository located at https://www.example.com/my-custom-repo you can run the following command",
            P.indent 4 . P.green $
              P.vcat
                [ "zokka publish https://www.example.com/my-custom-repo"
                ]
          ]

      publishArgs =
        Terminal.oneOf
          [ Terminal.require0 Publish.NoArgs,
            Terminal.require1 id (Publish.PublishToRepository <$> Terminal.repositoryLocalName)
          ]
   in Terminal.Command "publish" Terminal.Uncommon details example publishArgs Terminal.noFlags Publish.run

-- BUMP

bump :: Command
bump =
  let details =
        "The `bump` command figures out the next version number based on API changes:"

      example =
        reflow
          "Say you just published version 1.0.0, but then decided to remove a function.\
          \ I will compare the published API to what you have locally, figure out that\
          \ it is a MAJOR change, and bump your version number to 2.0.0. I do this with\
          \ all packages, so there cannot be MAJOR changes hiding in PATCH releases in Canopy!"
   in Terminal.Command "bump" Terminal.Uncommon details example Terminal.noArgs Terminal.noFlags Bump.run

-- DIFF

diff :: Command
diff =
  let details =
        "The `diff` command detects API changes:"

      example =
        stack
          [ reflow
              "For example, to see what changed in the HTML package between\
              \ versions 1.0.0 and 2.0.0, you can say:",
            P.indent 4 (P.green "canopy diff canopy/html 1.0.0 2.0.0"),
            reflow
              "Sometimes a MAJOR change is not actually very big, so\
              \ this can help you plan your upgrade timelines."
          ]

      diffArgs =
        Terminal.oneOf
          [ Terminal.require0 Diff.CodeVsLatest,
            Terminal.require1 Diff.CodeVsExactly Terminal.version,
            Terminal.require2 Diff.LocalInquiry Terminal.version Terminal.version,
            Terminal.require3 Diff.GlobalInquiry Terminal.package Terminal.version Terminal.version
          ]
   in Terminal.Command "diff" Terminal.Uncommon details example diffArgs Terminal.noFlags Diff.run

-- HELPERS

stack :: [Doc] -> Doc
stack docs =
  P.vcat $ List.intersperse "" docs

reflow :: String -> Doc
reflow string =
  P.fillSep . fmap P.text $ words string
