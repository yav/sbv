----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.SMT.SMTLib2
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Conversion of symbolic programs to SMTLib format, Using v2 of the standard
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Data.SBV.SMT.SMTLib2(cvt, addNonEqConstraints) where

import qualified Data.Foldable as F (toList)
import qualified Data.Map      as M
import Data.List (intercalate)
import Numeric (showHex)

import Data.SBV.BitVectors.Data

addNonEqConstraints :: [(Quantifier, NamedSymVar)] -> [[(String, CW)]] -> SMTLibPgm -> Maybe String
addNonEqConstraints qinps allNonEqConstraints (SMTLibPgm _ (aliasTable, pre, post))
  | null allNonEqConstraints
  = Just $ intercalate "\n" $ pre ++ post
  | null refutedModel
  = Nothing
  | True
  = Just $ intercalate "\n" $ pre
    ++ [ "; --- refuted-models ---" ]
    ++ concatMap nonEqs (map (map intName) nonEqConstraints)
    ++ post
 where refutedModel = concatMap nonEqs (map (map intName) nonEqConstraints)
       intName (s, c)
          | Just sw <- s `lookup` aliasTable = (show sw, c)
          | True                             = (s, c)
       -- with QBVF, we only add top-level existentials to the refuted-models list
       nonEqConstraints = filter (not . null) $ map (filter (\(s, _) -> s `elem` topUnivs)) allNonEqConstraints
       topUnivs = [s | (_, (_, s)) <- takeWhile (\p -> fst p == EX) qinps]

nonEqs :: [(String, CW)] -> [String]
nonEqs []     =  []
nonEqs [sc]   =  ["(assert " ++ nonEq sc ++ ")"]
nonEqs (sc:r) =  ["(assert (or " ++ nonEq sc]
              ++ map (("            " ++) . nonEq) r
              ++ ["        ))"]

nonEq :: (String, CW) -> String
nonEq (s, c) = "(not (= " ++ s ++ " " ++ cvtCW c ++ "))"

tbd :: String -> a
tbd m = error $ "SBV.SMTLib2: Not-yet-supported: " ++ m ++ ". Please report."

cvt :: Bool                                        -- ^ is this a sat problem?
    -> [String]                                    -- ^ extra comments to place on top
    -> [(Quantifier, NamedSymVar)]                 -- ^ inputs
    -> [Either SW (SW, [SW])]                      -- ^ skolemized version inputs
    -> [(SW, CW)]                                  -- ^ constants
    -> [((Int, (Bool, Int), (Bool, Int)), [SW])]   -- ^ auto-generated tables
    -> [(Int, ArrayInfo)]                          -- ^ user specified arrays
    -> [(String, SBVType)]                         -- ^ uninterpreted functions/constants
    -> [(String, [String])]                        -- ^ user given axioms
    -> Pgm                                         -- ^ assignments
    -> SW                                          -- ^ output variable
    -> ([String], [String])
cvt isSat comments _inps skolemInps consts tbls arrs uis axs asgnsSeq out
  | not (null uis)
  = tbd "uninterpreted functions"
  | not (null axs)
  = tbd "axioms"
  | not (null arrs)
  = tbd "user defined arrays"
  | True
  = (pre, [])
  where logic
         | null tbls && null arrs && null uis = "UFBV"
         | True                               = "AUFBV"
        pre  =  [ "; Automatically generated by SBV. Do not edit." ]
             ++ map ("; " ++) comments
             ++ [ "(set-option :produce-models true)"
                , "; (set-logic " ++ logic ++ ") ; let the solver determine the logic automatically"
                ]
             ++ [ "; --- literal constants ---"
                ]
             ++ concatMap declConst consts
             ++ [ "; --- skolem constants ---" ]
             ++ [ "(declare-fun " ++ show s ++ " " ++ smtFunType ss s ++ ")" | Right (s, ss) <- skolemInps]
             ++ [ "; --- tables ---" ]
             ++ concatMap mkTable tbls
             ++ [ "; --- formula ---" ]
             ++ [if null foralls
                 then "(assert "
                 else "(assert (forall (" ++ intercalate "\n                 "
                                             ["(" ++ show s ++ " " ++ smtType s ++ ")" | s <- foralls] ++ ")"]
             ++ map (letAlign . mkLet) asgns
             ++ [ letAlign assertOut ++ replicate ((if null foralls then 1 else 2) + length asgns) ')' ]
        foralls = [s | Left s <- skolemInps]
        letAlign s
          | null foralls = "   " ++ s
          | True         = "            " ++ s
        assertOut | isSat = "(= " ++ show out ++ " #b1)"
                  | True  = "(= " ++ show out ++ " #b0)"
        skolemMap = M.fromList [(s, ss) | Right (s, ss) <- skolemInps, not (null ss)]
        asgns = F.toList asgnsSeq
        mkLet (s, e) = "(let ((" ++ show s ++ " " ++ cvtExp skolemMap e ++ "))" 
        declConst (s, c) = [ "(declare-fun " ++ show s ++ " " ++ smtFunType [] s ++ ")"
                           , "(assert (= " ++ show s ++ " " ++ cvtCW c ++ "))"
                           ]

mkTable :: ((Int, (Bool, Int), (Bool, Int)), [SW]) -> [String]
mkTable ((i, (sa, at), (_, rt)), elts) = decl : zipWith mkElt elts [(0::Int)..]
  where t         = "table" ++ show i
        bv sz     = "(_ BitVec " ++ show sz ++ ")"
        decl      = "(declare-const " ++ t ++ " (Array " ++ bv at ++ " " ++ bv rt ++ "))"
        mkElt x k = "(assert (= (select " ++ t ++ " " ++ idx ++ ") " ++ show x ++ "))"
          where idx = cvtCW (mkConstCW (sa, at) k)

smtType :: SW -> String
smtType s = "(_ BitVec " ++ show (sizeOf s) ++ ")"

smtFunType :: [SW] -> SW -> String
smtFunType ss s = "(" ++ intercalate " " (map smtType ss) ++ ") " ++ smtType s

type SkolemMap = M.Map SW [SW]

cvtSW :: SkolemMap -> SW -> String
cvtSW skolemMap s
  | Just ss <- s `M.lookup` skolemMap
  = "(" ++ show s ++ concatMap ((" " ++) . show) ss ++ ")"
  | True
  = show s

-- NB. The following works with SMTLib2 since all sizes are multiples of 4 (or just 1, which is specially handled)
hex :: Int -> Integer -> String
hex 1  v = "#b" ++ show v
hex sz v = "#x" ++ pad (sz `div` 4) (showHex v "")
  where pad n s = take (n - length s) (repeat '0') ++ s

cvtCW :: CW -> String
cvtCW x | not (hasSign x) = hex (sizeOf x) (cwVal x)
-- signed numbers (with 2's complement representation) is problematic
-- since there's no way to put a bvneg over a positive number to get minBound..
-- Hence, we punt and use binary notation in that particular case
cvtCW x | cwVal x == least = mkMinBound (sizeOf x)
  where least = negate (2 ^ sizeOf x)
cvtCW x = negIf (w < 0) $ hex (sizeOf x) (abs w)
  where w = cwVal x

negIf :: Bool -> String -> String
negIf True  a = "(bvneg " ++ a ++ ")"
negIf False a = a

-- anamoly at the 2's complement min value! Have to use binary notation here
-- as there is no positive value we can provide to make the bvneg work.. (see above)
mkMinBound :: Int -> String
mkMinBound i = "#b1" ++ take (i-1) (repeat '0')

cvtExp :: SkolemMap -> SBVExpr -> String
cvtExp skolemMap expr = sh expr
  where ssw = cvtSW skolemMap
        sh (SBVApp Ite [a, b, c]) = "(ite (= #b1 " ++ ssw a ++ ") " ++ ssw b ++ " " ++ ssw c ++ ")"
        sh (SBVApp (Rol i) [a])   = rot ssw "rotate_left"  i a
        sh (SBVApp (Ror i) [a])   = rot ssw "rotate_right" i a
        sh (SBVApp (Shl i) [a])   = shft ssw "bvshl"  "bvshl"  i a
        sh (SBVApp (Shr i) [a])   = shft ssw "bvlshr" "bvashr" i a
        sh (SBVApp (LkUp (t, (_, at), _, l) i e) [])
          | needsCheck = "(ite " ++ cond ++ ssw e ++ " " ++ lkUp ++ ")"
          | True       = lkUp
          where needsCheck = (2::Integer)^(at) > (fromIntegral l)
                lkUp = "(select table" ++ show t ++ " " ++ show i ++ ")"
                cond
                 | hasSign i = "(or " ++ le0 ++ " " ++ gtl ++ ") "
                 | True      = gtl ++ " "
                (less, leq) = if hasSign i then ("bvslt", "bvsle") else ("bvult", "bvule")
                mkCnst = cvtCW . mkConstCW (hasSign i, sizeOf i)
                le0  = "(" ++ less ++ " " ++ ssw i ++ " " ++ mkCnst 0 ++ ")"
                gtl  = "(" ++ leq  ++ " " ++ mkCnst l ++ " " ++ ssw i ++ ")"
        sh (SBVApp (Extract i j) [a]) = "(extract[" ++ show i ++ ":" ++ show j ++ "] " ++ ssw a ++ ")"
        sh (SBVApp (ArrEq i j) []) = "(ite (= array_" ++ show i ++ " array_" ++ show j ++") #b1 #b0)"
        sh (SBVApp (ArrRead i) [a]) = "(select array_" ++ show i ++ " " ++ ssw a ++ ")"
        sh (SBVApp (Uninterpreted nm) [])   = "uninterpreted_" ++ nm
        sh (SBVApp (Uninterpreted nm) args) = "(uninterpreted_" ++ nm ++ " " ++ intercalate " " (map ssw args) ++ ")"
        sh inp@(SBVApp op args)
          | Just f <- lookup op smtOpTable
          = f (any hasSign args) (map ssw args)
          | True
          = error $ "SBV.SMT.SMTLib2.sh: impossible happened; can't translate: " ++ show inp
          where lift2  o _ [x, y] = "(" ++ o ++ " " ++ x ++ " " ++ y ++ ")"
                lift2  o _ sbvs   = error $ "SBV.SMTLib2.sh.lift2: Unexpected arguments: "   ++ show (o, sbvs)
                lift2B oU oS sgn sbvs
                  | sgn
                  = "(ite " ++ lift2 oS sgn sbvs ++ " #b1 #b0)"
                  | True
                  = "(ite " ++ lift2 oU sgn sbvs ++ " #b1 #b0)"
                lift2N o sgn sbvs = "(bvnot " ++ lift2 o sgn sbvs ++ ")"
                lift1  o _ [x]    = "(" ++ o ++ " " ++ x ++ ")"
                lift1  o _ sbvs   = error $ "SBV.SMT.SMTLib2.sh.lift1: Unexpected arguments: "   ++ show (o, sbvs)
                smtOpTable = [ (Plus,          lift2   "bvadd")
                             , (Minus,         lift2   "bvsub")
                             , (Times,         lift2   "bvmul")
                             , (Quot,          lift2   "bvudiv")
                             , (Rem,           lift2   "bvurem")
                             , (Equal,         lift2   "bvcomp")
                             , (NotEqual,      lift2N  "bvcomp")
                             , (LessThan,      lift2B  "bvult" "bvslt")
                             , (GreaterThan,   lift2B  "bvugt" "bvsgt")
                             , (LessEq,        lift2B  "bvule" "bvsle")
                             , (GreaterEq,     lift2B  "bvuge" "bvsge")
                             , (And,           lift2   "bvand")
                             , (Or,            lift2   "bvor")
                             , (XOr,           lift2   "bvxor")
                             , (Not,           lift1   "bvnot")
                             , (Join,          lift2   "concat")
                             ]

rot :: (SW -> String) -> String -> Int -> SW -> String
rot ssw o c x = "(" ++ o ++ "[" ++ show c ++ "] " ++ ssw x ++ ")"

shft :: (SW -> String) -> String -> String -> Int -> SW -> String
shft ssw oW oS c x = "(" ++ o ++ " " ++ ssw x ++ " " ++ cvtCW c' ++ ")"
   where s  = hasSign x
         c' = mkConstCW (s, sizeOf x) c
         o  = if hasSign x then oS else oW