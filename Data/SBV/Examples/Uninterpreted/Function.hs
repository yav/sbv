-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Examples.Uninterpreted.Function
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Demonstrates function counter-examples
-----------------------------------------------------------------------------

module Data.SBV.Examples.Uninterpreted.Function where

import Data.SBV

-- | An uninterpreted function
f :: SWord8 -> SWord8 -> SWord16
f = uninterpret "f"

-- | Asserts that @f x z == f (y+2) z@ whenever @x == y+2@. Naturally correct.
thmGood :: SWord8 -> SWord8 -> SWord8 -> SBool
thmGood x y z = x .== y+2 ==> f x z .== f (y + 2) z

-- | Asserts that @f@ is commutative; which is not necessarily true!
-- Indeed, the SMT solver (Yices in this case) returns a counter-example
-- function that is not commutative. We have:
--
-- @
-- ghci> prove thmBad
--   s0 = 0 :: SWord8
--   s1 = 128 :: SWord8
--   -- uninterpreted: f
--        128 0 -> 32768
--        default: 0
-- @
--
-- Note how the counterexample function @f@ returned by Yices violates commutativity;
-- thus providing evidence that the asserted theorem is not valid.
thmBad :: SWord8 -> SWord8 -> SBool
thmBad x y = f x y .== f y x