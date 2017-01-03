{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Interpreter for the source language (L1) 
--
-- UNFINISHED / PLACEHOLDER

module Packed.FirstOrder.SourceInterp
    ( execAndPrint, interpProg
    , Value(..)
    , main
    ) where

import           Blaze.ByteString.Builder (Builder, toLazyByteString)
import           Blaze.ByteString.Builder.Char.Utf8 (fromString)
import           Control.DeepSeq
import           Control.Monad
import           Control.Monad.Writer
import           Control.Monad.State
import qualified Data.ByteString.Lazy.Char8 as B
import           Data.List as L 
import           Data.Map as M
import           Data.IntMap as IM
import           Data.Word
import           GHC.Generics    
import           Packed.FirstOrder.Common
import           Packed.FirstOrder.L1_Source
import qualified Packed.FirstOrder.L2_Traverse as L2
import           System.Clock
import           System.IO.Unsafe (unsafePerformIO)
import           Text.PrettyPrint.GenericPretty


import           Data.Sequence (Seq, ViewL ((:<)), (|>))
import qualified Data.Sequence as S 
import qualified Data.Foldable as F
import           Packed.FirstOrder.Passes.InlinePacked(pattern NamedVal)
import           Packed.FirstOrder.L2_Traverse ( pattern WriteInt, pattern ReadInt, pattern NewBuffer
                                               , pattern CursorTy, pattern ScopedBuffer, pattern AddCursor)
    
-- TODO:
-- It's a SUPERSET, but use the Value type from TargetInterp anyway:
-- Actually, we should merge these into one type with a simple extension story.
-- import Packed.FirstOrder.TargetInterp (Val(..), applyPrim)

interpChatter :: Int
interpChatter = 7 

------------------------------------------------------------

instance Interp Prog where    
  interpNoLogs rc p = unsafePerformIO $ show . fst <$> interpProg rc p
  interpWithStdout rc p = do
   (v,logs) <- interpProg rc p
   return (show v, lines (B.unpack logs))

-- | HACK: we don't have a type-level distinction for when cursors are
-- allowed in the AST.  We use L2 as a proxy for this, allowing
-- cursors whenver executing L2, even though this is a bit premature
-- in the compiler pipeline.
instance Interp L2.Prog where
  interpNoLogs rc p2     = interpNoLogs     rc{rcCursors=True} (L2.revertToL1 p2)
  interpWithStdout rc p2 = interpWithStdout rc{rcCursors=True} (L2.revertToL1 p2)

-- Stores and buffers:
------------------------------------------------------------

-- | A store is an address space full of buffers.  
data Store = Store (IntMap Buffer)
  deriving (Read,Eq,Ord,Generic, Show)

instance Out Store
  
instance Out a => Out (IntMap a) where
  doc im       = doc       (IM.toList im)
  docPrec n im = docPrec n (IM.toList im)

data Buffer = Buffer (Seq SerializedVal)
  deriving (Read,Eq,Ord,Generic, Show)

instance Out Buffer
           
data SerializedVal = SerTag Word8 | SerInt Int
  deriving (Read,Eq,Ord,Generic, Show)

byteSize :: SerializedVal -> Int
byteSize (SerInt _) = 8 -- FIXME: get this constant from elsewhere.
byteSize (SerTag _) = 1
           
instance Out SerializedVal
instance NFData SerializedVal

instance Out Word8 where
  doc w       = doc       (fromIntegral w :: Int)
  docPrec n w = docPrec n (fromIntegral w :: Int)

instance Out a => Out (Seq a) where
  doc s       = doc       (F.toList s)
  docPrec n s = docPrec n (F.toList s)

-- Values                
-------------------------------------------------------------
                
-- | It's a first order language with simple values.
data Value = VInt Int
           | VBool Bool
           | VDict (M.Map Value Value)
-- FINISH:       | VList
           | VProd [Value]
           | VPacked Constr [Value]

           | VCursor { bufID :: Int, offset :: Int }
             -- ^ Cursor are a pointer into the Store plus an offset into the Buffer.

  deriving (Read,Eq,Ord,Generic)

instance Out Value
instance NFData Value    
           
instance Show Value where                      
 show v =
  case v of
   VInt n   -> show n
   VBool b  -> if b then truePrinted else falsePrinted
   VProd ls -> "("++ concat(intersperse ", " (L.map show ls)) ++")"
   VPacked k ls -> k ++ show (VProd ls)
   VDict m      -> show (M.toList m)
                   
   VCursor idx off -> "<cursor "++show idx++", "++show off++">"
                
type ValEnv = Map Var Value

------------------------------------------------------------
{-    
-- | Promote a value to a term that evaluates to it.
l1FromValue :: Value -> Exp
l1FromValue x =
  case x of
    (VInt y) -> __
    (VProd ls) -> __
    (VPacked y1 y2) -> __
-}

execAndPrint :: RunConfig -> Prog -> IO ()
execAndPrint rc prg = do
  (val,logs) <- interpProg rc prg
  B.putStr logs
  case val of
    -- Special case: don't print void return:
    VProd [] -> return () -- FIXME: remove this.
    _ -> print val   

type Log = Builder

-- TODO: add a flag for whether we support cursors:
    
-- | Interpret a program, including printing timings to the screen.
interpProg :: RunConfig -> Prog -> IO (Value, B.ByteString)
-- Print nothing, return "void"              :
interpProg _ Prog {mainExp=Nothing} = return $ (VProd [], B.empty)
interpProg rc Prog {ddefs,fundefs, mainExp=Just e} =
    do (x,logs) <- evalStateT (runWriterT (interp e)) (Store IM.empty)
       return (x, toLazyByteString logs)

 where
  applyPrim :: Prim -> [Value] -> Value
  applyPrim p ls =
   case (p,ls) of
     (MkTrue,[])             -> VBool True
     (MkFalse,[])            -> VBool False
     (AddP,[VInt x, VInt y]) -> VInt (x+y)                                
     (SubP,[VInt x, VInt y]) -> VInt (x-y)
     (MulP,[VInt x, VInt y]) -> VInt (x*y)
     (EqSymP,[VInt x, VInt y]) -> VBool (x==y)
     (EqIntP,[VInt x, VInt y]) -> VBool (x==y)
     ((DictInsertP _ty),[VDict mp, key, val]) -> VDict (M.insert key val mp)
     ((DictLookupP _),[VDict mp, key])        -> mp # key
     ((DictEmptyP _),[])                      -> VDict M.empty
     ((ErrorP msg _ty),[]) -> error msg
     (SizeParam,[]) -> VInt (rcSize rc)
     (ReadPackedFile file ty,[]) ->
         error $ "SourceInterp: unfinished, need to read a packed file: "++show (file,ty)
     oth -> error $ "unhandled prim or wrong number of arguments: "++show oth

  interp :: Exp -> WriterT Log (StateT Store IO) Value
  interp = go M.empty 
    where
      {-# NOINLINE goWrapper #-}
      goWrapper !_ix env ex = go env ex
      
      go :: ValEnv -> Exp -> WriterT Log (StateT Store IO) Value
      go env x0 =
          case x0 of
            LitE c         -> return $ VInt c

            -- In L2.5 witnesses are really justs casts:
            -- FIXME: We need some way to mediate between symbolic
            -- values and Cursors... or this won't work.
            VarE v -- | Just v' <- L2.fromWitnessVar v -> return $ env # v'
                   | otherwise                      -> return $ env # v
            PrimAppE p ls  -> do args <- mapM (go env) ls
                                 return $ applyPrim p args
            ProjE ix ex -> do VProd ls <- go env ex
                              return $ ls !! ix

            AddCursor vr bytesadd -> do
                Store store <- get
                -- Note: the added offset is always in BYTES:
                let VCursor idx off = env # vr
                    Buffer sq = store IM.! idx
                    dropped = lp bytesadd (S.viewl (S.drop off sq))
                    lp 0 _ = 0
                    lp n (hd :< tl) | n >= byteSize hd = 1 + lp (n - byteSize hd) (S.viewl tl)
                                    | otherwise = error $ errHeader ++ "Cannot skip "++
                                                      show n++" bytes, next value in buffer is: "++ show hd
                                                      ++" of size "++show (byteSize hd) ++".\n"++moreContext
                    lp n S.EmptyL = error $ errHeader ++ "Cannot skip ahead "
                                    ++show n++" bytes.  Buffer is empty.\n"++moreContext

                    errHeader = "Pointer arithmetic error in AddCursor of "++show (vr,bytesadd)++".  "
                    moreContext = " Starting cursor, "++show (VCursor idx off)
                                  ++" in Buffer: "++ndoc sq
                liftIO $ dbgPrintLn interpChatter ("\n [AddP Ptr, "++ show (vr,bytesadd)
                                                   ++"] scroll "++show bytesadd++" bytes, "
                                                   ++"dropping" ++show dropped++" elems,\n     "
                                                   ++moreContext)
                return $ VCursor idx (off+dropped)
                                     
            --- Pattern synonyms specific to post-cursorize ASTs:
            NewBuffer    -> do Store store0 <- get
                               let idx = IM.size store0
                                   store1 = IM.insert idx (Buffer S.empty) store0
                               put (Store store1)
                               return $ VCursor idx 0
            ScopedBuffer -> go env NewBuffer -- ^ No operational difference.
            WriteInt v ex -> do let VCursor idx off = env # v
                                VInt num <- go env ex
                                Store store0 <- get
                                let store1 = IM.alter (\(Just (Buffer s1)) -> Just (Buffer $ s1 |> SerInt num)) idx store0
                                put (Store store1)
                                return $ VCursor idx (off+1)
            ReadInt v -> do
              Store store <- get
              liftIO$ dbgPrint interpChatter $ " [ReadInt "++v++"] from store: "++ndoc store
              let VCursor idx off = env # v
                  Buffer buf = store IM.! idx
              liftIO$ dbgPrintLn interpChatter $ " [ReadInt "++v++"] from that store at pos: "
                                                 ++show (VCursor idx off)
              case S.viewl (S.drop off buf) of
                SerInt n :< _ -> return $ VProd [VInt n, VCursor idx (off+1)]
                S.EmptyL      -> error "SourceInterp: ReadInt on empty cursor/buffer."
                oth :< _      ->
                 error $"SourceInterp: ReadInt expected Int in buffer, found: "++show oth
                                     
            AppE f b -> do rand <- go env b
                           let FunDef{funArg=(vr,_),funBody}  = fundefs # f
                           go (M.insert vr rand env) funBody

            (CaseE x1 ls1) -> do
                   v <- go env x1
                   case v of
                     VCursor idx off | rcCursors rc ->
                        do Store store <- get
                           let Buffer seq1 = store IM.! idx
                           case S.viewl (S.drop off seq1) of
                             S.EmptyL -> error "SourceInterp: case scrutinize on empty/out-of-bounds cursor."
                             SerTag tg :< _rst -> do
                               -- ASSUMPTION: Id is just an ordered index.  We could explicitly map back
                               -- to the datacon instead...

                               let (tagsym,[curname],rhs) = ls1 !! fromIntegral tg
                                   -- At this ^ point, we assume that a pattern match against a cursor binds ONE value.
                                   _fields = lookupDataCon ddefs tagsym

                               let env' = M.insert curname (VCursor idx (off+1)) env
                               go env' rhs
                             oth :< _ -> error $ "SourceInterp: expected to read tag from scrutinee cursor, found: "++show oth

                     VPacked k ls2 ->
                         let (_,vs,rhs) = lookup3 k ls1
                             env' = M.union (M.fromList (zip vs ls2)) env
                         in go env' rhs
                     _ -> error$ "SourceInterp: type error, expected data constructor, got: "++ndoc v++
                                 "\nWhen evaluating scrutinee of case expression: "++ndoc x1

            NamedVal _ _ bd -> go env bd

            (LetE (v,_ty,rhs) bod) -> do
              rhs' <- go env rhs
              let env' = M.insert v rhs' env
              go env' bod

            (MkProdE ls) -> VProd <$> mapM (go env) ls
            -- TODO: Should check this against the ddefs.
            (MkPackedE k ls) -> do
                args <- mapM (go env) ls
                case args of
                -- Constructors are overloaded.  They have different behavior depending on
                -- whether we are AFTER Cursorize or not.
                  [ VCursor idx off ] | rcCursors rc ->
                      do Store store <- get
                         let tag       = SerTag (getTagOfDataCon ddefs k)
                             store'    = IM.alter (\(Just (Buffer s1)) -> Just (Buffer $ s1 |> tag)) idx store
                         put (Store store')
                         return $ VCursor idx (off+1)
                  _ -> return $ VPacked k args


            TimeIt bod _ isIter -> do
                let iters = if isIter then rcIters rc else 1
                !_ <- return $! force env
                st <- liftIO $ getTime clk          
                val <- foldM (\ _ i -> goWrapper i env bod)
                              (error "Internal error: this should be unused.")
                           [1..iters]
                en <- liftIO $ getTime clk
                let tm = fromIntegral (toNanoSecs $ diffTimeSpec en st)
                          / 10e9 :: Double         
                if isIter
                 then do tell$ fromString $ "ITERS: "++show iters       ++"\n"
                         tell$ fromString $ "SIZE: " ++show (rcSize rc) ++"\n"
                         tell$ fromString $ "BATCHTIME: "++show tm      ++"\n"
                 else tell$ fromString $ "SELFTIMED: "++show tm ++"\n"
                return $! val
              
                                
            IfE a b c -> do v <- go env a
                            case v of
                             VBool flg -> if flg
                                          then go env b
                                          else go env c
                             oth -> error$ "interp: expected bool, got: "++show oth

            MapE _ _bod    -> error "SourceInterp: finish MapE"
            FoldE _ _ _bod -> error "SourceInterp: finish FoldE"

                              

clk :: Clock
clk = Monotonic

                                               
-- Misc Helpers
--------------------------------------------------------------------------------

lookup3 :: (Eq k, Show k, Show a, Show b) =>
           k -> [(k,a,b)] -> (k,a,b)
lookup3 k ls = go ls
  where
   go [] = error$ "lookup3: key "++show k++" not found in list:\n  "++take 80 (show ls)
   go ((k1,a1,b1):r)
      | k1 == k   = (k1,a1,b1)
      | otherwise = go r
                    
--------------------------------------------------------------------------------

p1 :: Prog
p1 = Prog emptyDD  M.empty
          (Just (LetE ("x", IntTy, LitE 3) (VarE "x")))
         -- IntTy

main :: IO ()
main = execAndPrint (RunConfig 1 1 dbgLvl False) p1



       
