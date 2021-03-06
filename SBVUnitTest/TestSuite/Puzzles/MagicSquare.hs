-----------------------------------------------------------------------------
-- |
-- Module      :  TestSuite.Puzzles.MagicSquare
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Test suite for Data.SBV.Examples.Puzzles.MagicSquare
-----------------------------------------------------------------------------

module TestSuite.Puzzles.MagicSquare(testSuite) where

import Data.SBV
import Data.SBV.Examples.Puzzles.MagicSquare

import SBVTest

-- Test suite
testSuite :: SBVTestSuite
testSuite = mkTestSuite $ \_ -> test [
   "magic 2" ~: assert . not =<< isSat (mkMagic 2)
 , "magic 3" ~: assert       =<< isSat (mkMagic 3)
 ]
 where mkMagic n = (isMagic . chunk n) `fmap` mkExistVars (n*n)
