{-# LANGUAGE DeriveAnyClass #-}

-- | Generic operations that are supported by the various intermediate
-- representations inside the compiler.

module Packed.FirstOrder.GenericOps
    (
       Interp(..)

     -- * Free Variables, generic interface
     , FreeVars(..)

     -- * Genereric interface for expressions and select passes
     , Expression(..), NoExt
     , Flattenable(..)
     , Simplifiable(..)
    )
    where

import Control.DeepSeq (NFData)
import GHC.Generics
import qualified Data.Set as S
import qualified Data.Map as M
import Packed.FirstOrder.Common
import Text.PrettyPrint.GenericPretty 
    
--------------------------------------------------------------------------------
-- Things which can be interpreted to yield a final, printed value. 
--------------------------------------------------------------------------------

-- | Pure Gibbon programs, at any stage of compilation, should always
-- be evaluatable to a unique value.  The only side effects are timing.
class Interp a where
  -- | Interpret while ignoring timing constructs, and dropping the
  -- corresponding output to stdout.
  interpNoLogs     :: RunConfig -> a -> String

  -- | Interpret and produce a "log" of output lines, as well as a
  -- final, printed result.  The output lines include timing information.
  interpWithStdout :: RunConfig -> a -> IO (String,[String])

----------------------------------------------------------------------------------------------------
-- Free Variables 
----------------------------------------------------------------------------------------------------

-- | Expression and program types which support a notion of free variables.
class FreeVars a where
    gFreeVars :: a -> S.Set Var

instance FreeVars (NoExt l d) where
  gFreeVars _ = S.empty 


----------------------------------------------------------------------------------------------------
-- Compiler passes used in multiple phases
----------------------------------------------------------------------------------------------------

-- | A generic interface to expressions found in different phases of
-- the compiler.
class (Show e, Out e) => Expression e where
  type TyOf e
  type LocOf e
      
-- | IRs amenable to flattening
class Expression e => Flattenable e where
  -- | Process an expression into a fully-flattened expression which typically includes a
  -- larger number of temporary, local variable bindings.
  gFlattenExp :: DDefs (TyOf e) -> Env2 (TyOf e) -> e -> SyM e

  -- | A private method.  Gather the bindings from a subexpression,
  -- but do not "discharge" them by creating a let expression.  They
  -- are in order, so later may depend on earlier.
  gFlattenGatherBinds :: DDefs (TyOf e) -> Env2 (TyOf e) -> e -> SyM ([Binds e],e)

type Binds e = (Var,[LocOf e],TyOf e, e)
    
-- | IRs amenable to simplification/inlineTrivs
class Expression e => Simplifiable e where
  gInlineTrivExp :: DDefs (TyOf e) -> e -> e

-- | An uninhabidited type indicating that the base grammar is not extended with any
-- additional constructs.
data NoExt l d   deriving (Generic, NFData)

instance Show (NoExt l d) where
  show _ = error "<NoExt: This should be impossible to print>"
instance Out (NoExt l d) where
  doc _ = error "<NoExt: This should be impossible to print>"
  docPrec _ x = doc x
instance Read (NoExt l d) where
  readsPrec _ = error "<NoExt: This should be impossible to read>"
instance Eq (NoExt l d) where
  _ == _ = True
instance Ord (NoExt l d) where
  compare _ _ = EQ

             
-- | A dummy instance for "no-extension" extension point.
instance Expression (NoExt l d) where
  type TyOf  (NoExt l d) = d
  type LocOf (NoExt l d) = l
      
-- | A dummy instance for "no-extension" extension point.
instance Flattenable (NoExt l d) where
  gFlattenExp _ _ impossible = return impossible

-- | A dummy instance for "no-extension" extension point.
instance Simplifiable (NoExt l d) where
  gInlineTrivExp _ impossible = impossible
