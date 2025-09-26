import qualified File.Package as Package
import qualified System.Environment as Env

main :: IO ()
main = do
  args <- Env.getArgs
  case args of
    [packageDir] -> do
      putStrLn ("Collecting files from: " ++ packageDir)
      files <- Package.collectPackageFiles packageDir
      putStrLn ("Found " ++ show (length files) ++ " files:")
      mapM_ putStrLn files
    _ -> putStrLn "Usage: debug_package <package_directory>"