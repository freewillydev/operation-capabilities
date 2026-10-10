module Main where

import Demo (renderNote)
import System.Exit (die)

main :: IO ()
main = case renderNote "  hello    capabilities  " of
  Right (Just text) -> putStrLn text
  Right Nothing -> die "unexpected operation type mismatch"
  Left message -> die message
