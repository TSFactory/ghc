{-# OPTIONS -fglasgow-exts #-}
-- test the representation of unboxed literals

module Main
where

import GHC.Base
import GHC.Float
import Language.Haskell.TH
import Text.PrettyPrint
import System.IO

main :: IO ()
main = do putStrLn $ show $ $( do e <- [| I# 20# |]
                                  return e )
          putStrLn $ show $ $( do e <- [| F# 12.3# |]
                                  return e )
          putStrLn $ show $ $( do e <- [| D# 24.6## |]
                                  return e )


