{-# LANGUAGE OverloadedStrings #-}

-- | Editor integration configuration and discovery.
--
-- Provides information about the Canopy language server and editor
-- integration points.  This module is used by the CLI to help users
-- set up their development environment.
--
-- == Supported Editors
--
-- * VS Code -- via the @canopy-language@ extension
-- * Neovim -- via nvim-lspconfig with the @canopy@ server
-- * Emacs -- via lsp-mode with the @canopy-ls@ client
-- * Sublime Text -- via the LSP package
--
-- @since 0.19.2
module Editor.Integration
  ( -- * LSP Configuration
    LspConfig (..),
    defaultLspConfig,

    -- * File Associations
    canopyFileExtensions,
    canopyLanguageId,

    -- * Editor Detection
    EditorInfo (..),
    supportedEditors,
  )
where

import qualified Data.Text as Text

-- | Language server configuration for editor integrations.
--
-- @since 0.19.2
data LspConfig = LspConfig
  { -- | Command to start the language server.
    _lspCommand :: ![Text.Text],
    -- | File types handled by the server.
    _lspFileTypes :: ![Text.Text],
    -- | Root directory markers for project detection.
    _lspRootMarkers :: ![Text.Text],
    -- | Language identifier for the LSP protocol.
    _lspLanguageId :: !Text.Text
  }
  deriving (Eq, Show)

-- | Default LSP configuration for the Canopy language server.
--
-- Uses @canopy-lsp --stdio@ as the server command and recognizes
-- both @.can@ and @.canopy@ file extensions.
--
-- @since 0.19.2
defaultLspConfig :: LspConfig
defaultLspConfig =
  LspConfig
    { _lspCommand = ["canopy-lsp", "--stdio"],
      _lspFileTypes = canopyFileExtensions,
      _lspRootMarkers = ["canopy.json", "elm.json"],
      _lspLanguageId = canopyLanguageId
    }

-- | File extensions associated with Canopy source files.
--
-- @since 0.19.2
canopyFileExtensions :: [Text.Text]
canopyFileExtensions = [".can", ".canopy"]

-- | The LSP language identifier for Canopy.
--
-- @since 0.19.2
canopyLanguageId :: Text.Text
canopyLanguageId = "canopy"

-- | Information about a supported editor.
--
-- @since 0.19.2
data EditorInfo = EditorInfo
  { -- | Human-readable editor name.
    _editorName :: !Text.Text,
    -- | Integration mechanism (extension, plugin, config).
    _editorMechanism :: !Text.Text,
    -- | Installation instructions summary.
    _editorInstallHint :: !Text.Text
  }
  deriving (Eq, Show)

-- | List of editors with Canopy support.
--
-- @since 0.19.2
supportedEditors :: [EditorInfo]
supportedEditors =
  [ EditorInfo
      { _editorName = "VS Code",
        _editorMechanism = "Extension",
        _editorInstallHint =
          "Install the 'canopy-language' extension from the VS Code marketplace."
      },
    EditorInfo
      { _editorName = "Neovim",
        _editorMechanism = "nvim-lspconfig",
        _editorInstallHint =
          "Add require('canopy').setup() to your init.lua with nvim-lspconfig installed."
      },
    EditorInfo
      { _editorName = "Emacs",
        _editorMechanism = "lsp-mode",
        _editorInstallHint =
          "Configure lsp-mode with (lsp-register-client (make-lsp-client :new-connection ...))."
      },
    EditorInfo
      { _editorName = "Sublime Text",
        _editorMechanism = "LSP package",
        _editorInstallHint =
          "Install the LSP package and add a canopy-ls client configuration."
      }
  ]
