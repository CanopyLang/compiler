{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# LANGUAGE OverloadedStrings #-}

module File
  ( Time (..),
    getTime,
    zeroTime,
    writeBinary,
    readBinary,
    writeUtf8,
    readUtf8,
    writeBuilder,
    writePackage,
    exists,
    remove,
    removeDir,
    writePackageReturnCanopyJson,
    listAllCanopyFilesRecursively,
  )
where

import Control.Exception (IOException)
import Data.Vector.Internal.Check (HasCallStack)
import GHC.IO.Exception (IOErrorType (InvalidArgument))
import System.FilePath ((</>))
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import qualified Data.Foldable as Foldable
import qualified Data.Traversable as Traversable
import qualified GHC.Exception as Exception
import qualified GHC.Stack as Stack
import qualified System.IO.Error as IOError
import qualified Codec.Archive.Zip as Zip
import qualified Data.Binary as Binary
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Internal as BSInternal
import qualified Data.Int as Int
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Fixed as Fixed
import qualified Data.List as List
import qualified Data.Time.Clock as Time
import qualified Data.Time.Clock.POSIX as Time
import qualified Foreign.ForeignPtr as FPtr
import qualified Logging.Logger as Logger
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO as IO

-- TIME

newtype Time = Time Fixed.Pico
  deriving (Eq, Ord, Show)

getTime :: FilePath -> IO Time
getTime path =
  fmap
    (Time . Time.nominalDiffTimeToSeconds . Time.utcTimeToPOSIXSeconds)
    (Dir.getModificationTime path)

zeroTime :: Time
zeroTime =
  Time 0

instance Binary.Binary Time where
  put (Time time) = Binary.put time
  get = Time <$> Binary.get

-- BINARY

writeBinary :: (HasCallStack, Binary.Binary a) => FilePath -> a -> IO ()
writeBinary path value =
  do
    let dir = FP.dropFileName path
    Dir.createDirectoryIfMissing True dir
    Binary.encodeFile path value

readBinary :: (HasCallStack, Binary.Binary a) => FilePath -> IO (Maybe a)
readBinary path = do
  pathExists <- Dir.doesFileExist path
  if pathExists
    then decodeBinaryFile path
    else pure Nothing

decodeBinaryFile :: Binary.Binary a => FilePath -> IO (Maybe a)
decodeBinaryFile path = do
  result <- Binary.decodeFileOrFail path
  case result of
    Right a -> pure (Just a)
    Left (offset, message) -> do
      reportCorruptFile path offset message
      pure Nothing

reportCorruptFile :: FilePath -> Int.Int64 -> String -> IO ()
reportCorruptFile path offset message =
  IO.hPutStrLn IO.stderr . unlines $
    [ "+-------------------------------------------------------------------------------",
      "|  Corrupt File: " <> path,
      "|   Byte Offset: " <> show offset,
      "|       Message: " <> message,
      "|",
      "| Please report this to https://github.com/canopy/compiler/issues",
      "| Trying to continue anyway.",
      "+-------------------------------------------------------------------------------",
      Exception.prettyCallStack Stack.callStack
    ]

-- WRITE UTF-8

writeUtf8 :: FilePath -> BS.ByteString -> IO ()
writeUtf8 path content =
  withUtf8 path IO.WriteMode $ \handle ->
    BS.hPut handle content

withUtf8 :: FilePath -> IO.IOMode -> (IO.Handle -> IO a) -> IO a
withUtf8 path mode callback =
  IO.withFile path mode $ \handle ->
    do
      IO.hSetEncoding handle IO.utf8
      callback handle

-- READ UTF-8

readUtf8 :: FilePath -> IO BS.ByteString
readUtf8 path =
  withUtf8 path IO.ReadMode $ \handle ->
    IOError.modifyIOError (encodingError path) $ do
      fileSize <- Exception.catch (IO.hFileSize handle) useZeroIfNotRegularFile
      let readSize = max 0 (fromIntegral fileSize) + 1
      hGetContentsSizeHint handle readSize (max 255 readSize)

useZeroIfNotRegularFile :: IOException -> IO Integer
useZeroIfNotRegularFile _ =
  Monad.return 0

hGetContentsSizeHint :: IO.Handle -> Int -> Int -> IO BS.ByteString
hGetContentsSizeHint handle readSize incrementSize =
  readChunks [] readSize incrementSize
  where
    readChunks chunks currentSize increment = do
      fp <- BSInternal.mallocByteString currentSize
      readCount <- FPtr.withForeignPtr fp $ \buf -> IO.hGetBuf handle buf currentSize
      let chunk = BSInternal.PS fp 0 readCount
      if shouldFinishReading readCount currentSize
        then pure $! BS.concat (List.reverse (chunk : chunks))
        else readChunks (chunk : chunks) increment (calculateNextSize currentSize increment)

shouldFinishReading :: Int -> Int -> Bool
shouldFinishReading readCount readSize = readCount < readSize && readSize > 0

calculateNextSize :: Int -> Int -> Int
calculateNextSize readSize incrementSize = min 32752 (readSize + incrementSize)

encodingError :: FilePath -> IOError -> IOError
encodingError path ioErr =
  case IOError.ioeGetErrorType ioErr of
    InvalidArgument ->
      IOError.annotateIOError
        (IOError.userError "Bad encoding; the file must be valid UTF-8")
        ""
        Nothing
        (Just path)
    _ ->
      ioErr

-- WRITE BUILDER

writeBuilder :: FilePath -> Builder.Builder -> IO ()
writeBuilder path builder =
  IO.withBinaryFile path IO.WriteMode $ \handle -> do
    IO.hSetBuffering handle (IO.BlockBuffering Nothing)
    Builder.hPutBuilder handle builder

-- WRITE PACKAGE

writePackage :: FilePath -> Zip.Archive -> IO ()
writePackage destination archive =
  case Zip.zEntries archive of
    [] ->
      Monad.return ()
    entry : entries -> do
      Monad.void (Dir.doesDirectoryExist destination)
      Foldable.traverse_ (writeEntry destination root) entries
      where
        root = List.length (Zip.eRelativePath entry)

writeEntry :: FilePath -> Int -> Zip.Entry -> IO ()
writeEntry destination root entry = do
  Monad.when (isAllowedPath path) $ do
    if isDirectoryPath path
      then createEntryDirectory destination path
      else writeEntryFile destination path entry
  where
    path = extractRelativePath root entry

extractRelativePath :: Int -> Zip.Entry -> FilePath
extractRelativePath root entry = List.drop root (Zip.eRelativePath entry)

isAllowedPath :: FilePath -> Bool
isAllowedPath path =
  List.isPrefixOf "src/" path
    || path == "LICENSE"
    || path == "README.md"
    || path == "canopy.json"

isDirectoryPath :: FilePath -> Bool
isDirectoryPath path = not (List.null path) && List.last path == '/'

createEntryDirectory :: FilePath -> FilePath -> IO ()
createEntryDirectory destination path = do
  Logger.printLog ("writeEntry 0: " <> path)
  Dir.createDirectoryIfMissing True (destination </> path)

writeEntryFile :: FilePath -> FilePath -> Zip.Entry -> IO ()
writeEntryFile destination path entry = do
  Logger.printLog ("writeEntry 1: " <> path)
  LBS.writeFile (destination </> path) (Zip.fromEntry entry)

writePackageReturnCanopyJson :: FilePath -> Zip.Archive -> IO (Maybe BS.ByteString)
writePackageReturnCanopyJson destination archive =
  case Zip.zEntries archive of
    [] -> pure Nothing
    entry : entries -> do
      logPackageWrite destination
      listOfMaybeCanopyJsons <- Traversable.traverse (writeEntryReturnCanopyJson destination root) entries
      pure (Monad.msum listOfMaybeCanopyJsons)
      where
        root = List.length (Zip.eRelativePath entry)

logPackageWrite :: FilePath -> IO ()
logPackageWrite destination = do
  Logger.printLog ("writePackageReturnCanopyJson to " <> destination)
  exists <- Dir.doesDirectoryExist destination
  Logger.printLog ("writePackageReturnCanopyJson destination: " <> (destination <> (" exists: " <> show exists)))

writeEntryReturnCanopyJson :: FilePath -> Int -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryReturnCanopyJson destination root entry = do
  let path = extractRelativePath root entry
  if isAllowedPath path
    then processAllowedEntry destination path entry
    else pure Nothing

processAllowedEntry :: FilePath -> FilePath -> Zip.Entry -> IO (Maybe BS.ByteString)
processAllowedEntry destination path entry =
  if isDirectoryPath path
    then do
      createEntryDirectoryForJson destination path
      pure Nothing
    else writeEntryFileForJson destination path entry

createEntryDirectoryForJson :: FilePath -> FilePath -> IO ()
createEntryDirectoryForJson destination path = do
  Logger.printLog ("writeEntryReturnCanopyJson 0: " <> path)
  Dir.createDirectoryIfMissing True (destination </> path)

writeEntryFileForJson :: FilePath -> FilePath -> Zip.Entry -> IO (Maybe BS.ByteString)
writeEntryFileForJson destination path entry = do
  Logger.printLog ("writeEntryReturnCanopyJson 1: " <> path)
  LBS.writeFile (destination </> path) bytestring
  pure (if path == "canopy.json" then Just (BS.toStrict bytestring) else Nothing)
  where
    bytestring = Zip.fromEntry entry

-- EXISTS

exists :: FilePath -> IO Bool
exists = Dir.doesFileExist

-- REMOVE FILES

remove :: FilePath -> IO ()
remove path = do
  exists_ <- Dir.doesFileExist path
  Monad.when exists_ $ Dir.removeFile path

removeDir :: FilePath -> IO ()
removeDir path = do
  exists_ <- Dir.doesDirectoryExist path
  Monad.when exists_ $ Dir.removeDirectoryRecursive path

-- RECURSIVE OPERATIONS

listAllCanopyFilesRecursively :: FilePath -> IO [FilePath]
listAllCanopyFilesRecursively startPath = do
  names <- Dir.listDirectory startPath
  paths <- Monad.forM names (processDirectoryEntry startPath)
  pure (startPath : List.concat paths)

processDirectoryEntry :: FilePath -> String -> IO [FilePath]
processDirectoryEntry startPath name = do
  let path = startPath </> name
  isDirectory <- Dir.doesDirectoryExist path
  if isDirectory
    then processSubdirectory path
    else processFile path

processSubdirectory :: FilePath -> IO [FilePath]
processSubdirectory path = do
  remainingFiles <- listAllCanopyFilesRecursively path
  -- We want to actually append directories as well because the way
  -- the Canopy compiler decompresses ZIP files requires us to have
  -- directories as well
  pure (path : remainingFiles)

processFile :: FilePath -> IO [FilePath]
processFile path =
  if isCanopyFile ext
    then pure [path]
    else pure []
  where
    (_, ext) = FP.splitExtension path

isCanopyFile :: String -> Bool
isCanopyFile ext = ext == ".can" || ext == ".canopy" || ext == ".elm"
