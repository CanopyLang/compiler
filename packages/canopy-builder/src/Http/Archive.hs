{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Http.Archive - ZIP archive download and parsing helpers
--
-- This module provides the internal streaming-download-and-parse machinery
-- used by the archive-related operations in "Http".  It is kept in a separate
-- module to prevent "Http" from exceeding the 1000-line limit while still
-- exposing only a minimal public surface area.
--
-- Callers should import "Http" and use 'Http.getArchive' \/
-- 'Http.getArchiveWithHeaders' rather than this module directly.
module Http.Archive
  ( -- * Archive state
    ArchiveState,

    -- * Streaming download
    readArchive,
    readLocalArchive,
  )
where

import Control.Lens (makeLenses, (&), (.~), (^.))
import qualified Data.Binary as Binary
import qualified Data.Binary.Get as Binary
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Codec.Archive.Zip as Zip
import qualified System.Directory as Directory
import Network.HTTP.Client
  ( BodyReader,
    brRead,
  )
import Prelude hiding (zip)

-- | Internal mutable state accumulated while streaming a ZIP download.
--
-- Tracks the byte count, an incremental SHA-256 decoder, and an incremental
-- ZIP decoder so that hash computation and archive parsing can run in a
-- single streaming pass.
data ArchiveState = AS
  { _len :: !Int,
    _sha :: !(Binary.Decoder SHA.SHA256State),
    _zip :: !(Binary.Decoder Zip.Archive)
  }

makeLenses ''ArchiveState

-- | Stream a ZIP archive body, computing its SHA-256 hash and parsing the
-- archive concurrently.
--
-- Returns 'Nothing' if the ZIP data is malformed; otherwise returns the
-- completed digest and parsed 'Zip.Archive'.
readArchive :: BodyReader -> IO (Maybe (SHA.Digest SHA.SHA256State, Zip.Archive))
readArchive body =
  readArchiveHelp body $
    AS
      { _len = 0,
        _sha = SHA.sha256Incremental,
        _zip = Binary.runGetIncremental Binary.get
      }

readArchiveHelp :: BodyReader -> ArchiveState -> IO (Maybe (SHA.Digest SHA.SHA256State, Zip.Archive))
readArchiveHelp body archiveState =
  case archiveState ^. zip of
    Binary.Fail {} ->
      return Nothing
    Binary.Partial k -> do
      chunk <- brRead body
      let currentLen = archiveState ^. len
          currentSha = archiveState ^. sha
      readArchiveHelp body $
        archiveState
          & len .~ (currentLen + BS.length chunk)
          & sha .~ Binary.pushChunk currentSha chunk
          & zip .~ k (if BS.null chunk then Nothing else Just chunk)
    Binary.Done _ _ archive ->
      return $ Just
        ( SHA.completeSha256Incremental (archiveState ^. sha) (archiveState ^. len)
        , archive
        )

-- | Read a local ZIP file from disk and compute its SHA-256 hash.
--
-- Returns 'Nothing' if the file does not exist or cannot be decoded as a
-- valid ZIP archive.
readLocalArchive :: FilePath -> IO (Maybe (SHA.Digest SHA.SHA256State, Zip.Archive))
readLocalArchive filePath = do
  fileExists <- Directory.doesFileExist filePath
  if fileExists
    then do
      content <- LBS.readFile filePath
      let fileHash = SHA.sha256 content
      case Binary.decodeOrFail content of
        Right (_, _, archive) -> return $ Just (fileHash, archive)
        Left _ -> return Nothing
    else return Nothing
