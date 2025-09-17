{-# LANGUAGE OverloadedStrings #-}
import qualified Generate.JavaScript.Functions as Functions
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8

main :: IO ()
main = do
  let functionsOutput = Functions.functions
      result = BB.toLazyByteString functionsOutput
  putStrLn "Functions.hs generates:"
  putStrLn $ BL8.unpack result
  putStrLn "Length:" 
  putStrLn $ show $ BL8.length result
