{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

-- | Tests for RouteEnds2
--
module InferEffects2 where

import Data.Set as S
import Data.Map as M

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.TH

import Packed.FirstOrder.Common hiding (FunDef)
import Packed.FirstOrder.L2.Syntax as L2
import Packed.FirstOrder.L2.Examples
import Packed.FirstOrder.Passes.InferEffects2
import qualified Packed.FirstOrder.L1.Syntax as L1


assertInferEffects :: Prog -> Var -> Set Effect -> Assertion
assertInferEffects prg fnName expected = expected @=? eff
  where -- run inferEffects and get the effect from it's type
        Prog{fundefs} = fst $ runSyM 0 $ inferEffects prg
        eff = arrEffs $ funty (fundefs ! fnName)


-- | Add1 function has a traversal effect [Traverse "lin2"]
--
case_add1 :: Assertion
case_add1 = assertInferEffects add1Prog "add1" (S.singleton $ Traverse "lin2")

-- | Identity fn doesn't have any traversal effect
case_id1 :: Assertion
case_id1 = assertInferEffects id1Prog "id1" S.empty

-- | Copying has a traversal effect
case_copyTree :: Assertion
case_copyTree =  assertInferEffects copyTreeProg "copyTree" (S.singleton $ Traverse "lin23")

-- | Call copy on the body of id1
case_call_copy_on_id1 :: Assertion
case_call_copy_on_id1 = assertInferEffects copyOnId1Prog "id1WithCopy" (S.singleton $ Traverse "lin19")


inferEffects2Tests :: TestTree
inferEffects2Tests = $(testGroupGenerator)
