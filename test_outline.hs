import qualified Canopy.Outline as Outline

main = do
  result <- Outline.read "/home/quinten/.canopy/0.19.1/canopy-cache-0.191.0/elm/core/1.0.5/canopy/core/1.0.0/"
  case result of
    Left err -> putStrLn ("Error: " ++ show err)
    Right outline -> putStrLn ("Success: " ++ show outline)
