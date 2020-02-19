{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# LANGUAGE StandaloneDeriving    #-}

-- | A higher-ordered surface language that supports Rank-1 parametric
-- polymorphism.
module Gibbon.L0.Syntax
  ( module Gibbon.L0.Syntax,
    module Gibbon.Language,
  )
where

import           Control.Monad.State ( MonadState )
import           Control.DeepSeq (NFData)
import           Data.List
import qualified Data.Loc as Loc
import           GHC.Generics
import           Text.PrettyPrint.GenericPretty
import           Text.PrettyPrint.HughesPJ as PP
import qualified Data.Set as S
import qualified Data.Map as M

import           Gibbon.Common as C
import           Gibbon.Language hiding (UrTy(..))

--------------------------------------------------------------------------------

type Exp0     = PreExp E0Ext Ty0 Ty0
type DDefs0   = DDefs Ty0
type DDef0    = DDef Ty0
type FunDef0  = FunDef Exp0
type FunDefs0 = FunDefs Exp0
type Prog0    = Prog Exp0

--------------------------------------------------------------------------------

-- | The extension point for L0.
data E0Ext loc dec =
   LambdaE [(Var,dec)] -- Variable tagged with type
           (PreExp E0Ext loc dec)
 | PolyAppE (PreExp E0Ext loc dec) -- Operator
            (PreExp E0Ext loc dec) -- Operand
 | FunRefE [loc] Var -- Reference to a function (toplevel or lambda),
                     -- along with its tyapps.
 | BenchE Var [loc] [(PreExp E0Ext loc dec)] Bool
 | ParE0 [(PreExp E0Ext loc dec)]
 | L Loc.Loc (PreExp E0Ext loc dec)
 deriving (Show, Ord, Eq, Read, Generic, NFData)

--------------------------------------------------------------------------------
-- Helper methods to integrate the Data.Loc with Gibbon

deriving instance Generic Loc.Loc
deriving instance Generic Loc.Pos
deriving instance Ord     Loc.Loc
deriving instance NFData  Loc.Pos
deriving instance NFData  Loc.Loc

-- | Orphaned instance: read without source locations.
instance Read t => Read (Loc.L t) where
  readsPrec n str = [ (Loc.L Loc.NoLoc a,s) | (a,s) <- readsPrec n str ]

instance Out Loc.Loc where
  docPrec _ loc = doc loc

  doc loc =
    case loc of
      Loc.Loc start _end -> doc start
      Loc.NoLoc -> PP.empty

instance Out Loc.Pos where
  docPrec _ pos = doc pos
  doc (Loc.Pos path line col _) = hcat [doc path, colon, doc line, colon, doc col]

instance FreeVars (E0Ext l d) where
  gFreeVars e =
    case e of
      LambdaE args bod -> foldr S.delete (gFreeVars bod) (map fst args)
      PolyAppE f d     -> gFreeVars f `S.union` gFreeVars d
      FunRefE _ f      -> S.singleton f
      BenchE _ _ args _-> S.unions (map gFreeVars args)
      ParE0 ls         -> S.unions (map gFreeVars ls)
      L _ e1           -> gFreeVars e1

instance (Out l, Out d, Show l, Show d) => Expression (E0Ext l d) where
  type LocOf (E0Ext l d) = l
  type TyOf (E0Ext l d)  = d
  isTrivial _ = False

instance (Show l, Out l) => Flattenable (E0Ext l Ty0) where
    gFlattenGatherBinds _ddfs _env ex = return ([], ex)
    gFlattenExp _ddfs _env ex = return ex

instance HasSubstitutableExt E0Ext l d => SubstitutableExt (PreExp E0Ext l d) (E0Ext l d) where
  gSubstExt old new ext =
    case ext of
      LambdaE args bod -> LambdaE args (gSubst old new bod)
      PolyAppE a b     -> PolyAppE (gSubst old new a) (gSubst old new b)
      FunRefE{}        -> ext
      BenchE fn tyapps args b -> BenchE fn tyapps (map (gSubst old new) args) b
      ParE0 ls -> ParE0 $ map (gSubst old new) ls
      L p e1   -> L p (gSubst old new e1)

  gSubstEExt old new ext =
    case ext of
      LambdaE args bod -> LambdaE args (gSubstE old new bod)
      PolyAppE a b     -> PolyAppE (gSubstE old new a) (gSubstE old new b)
      FunRefE{}        -> ext
      BenchE fn tyapps args b -> BenchE fn tyapps (map (gSubstE old new) args) b
      ParE0 ls -> ParE0 $ map (gSubstE old new) ls
      L p e    -> L p $ (gSubstE old new e)

instance HasRenamable E0Ext l d => Renamable (E0Ext l d) where
  gRename env ext =
    case ext of
      LambdaE args bod -> LambdaE (map (\(a,b) -> (go a, go b)) args) (go bod)
      PolyAppE a b     -> PolyAppE (go a) (go b)
      FunRefE tyapps a -> FunRefE (map go tyapps) (go a)
      BenchE fn tyapps args b -> BenchE fn (map go tyapps) (map go args) b
      ParE0 ls -> ParE0 $ map (gRename env) ls
      L p e    -> L p (gRename env e)
    where
      go :: forall a. Renamable a => a -> a
      go = gRename env

instance (Out l, Out d) => Out (E0Ext l d)
instance Out Ty0
instance Out TyScheme

--------------------------------------------------------------------------------

data MetaTv = Meta Int
  deriving (Read, Show, Eq, Ord, Generic, NFData)

instance Out MetaTv where
  doc (Meta i) = text "$" PP.<> doc i
  docPrec _ v = doc v

newMetaTv :: MonadState Int m => m MetaTv
newMetaTv = Meta <$> newUniq

newMetaTy :: MonadState Int m => m Ty0
newMetaTy = MetaTv <$> newMetaTv

newTyVar :: MonadState Int m => m TyVar
newTyVar = BoundTv <$> genLetter

data Ty0
 = IntTy
 | SymTy0
 | BoolTy
 | TyVar TyVar   -- Rigid/skolem type variables
 | MetaTv MetaTv -- Unification variables
 | ProdTy [Ty0]
 | SymDictTy (Maybe Var) Ty0
 | SymSetTy
 | SymHashTy
 | IntHashTy
 | ArrowTy [Ty0] Ty0
 | PackedTy TyCon [Ty0] -- Type arguments to the type constructor
 | ListTy Ty0
 | ArenaTy
  deriving (Show, Read, Eq, Ord, Generic, NFData)

instance FunctionTy Ty0 where
  type ArrowTy Ty0 = TyScheme
  inTys  = arrIns
  outTy  = arrOut

instance Renamable TyVar where
  gRename env tv =
    case tv of
      BoundTv v  -> BoundTv (gRename env v)
      SkolemTv{} -> tv
      UserTv v   -> UserTv (gRename env v)

instance Renamable Ty0 where
  gRename env ty =
    case ty of
      IntTy  -> IntTy
      SymTy0 -> SymTy0
      BoolTy -> BoolTy
      TyVar tv  -> TyVar (go tv)
      MetaTv{}  -> ty
      ProdTy ls -> ProdTy (map go ls)
      SymDictTy a t     -> SymDictTy a t
      ArrowTy args ret  -> ArrowTy (map go args) ret
      PackedTy tycon ls -> PackedTy tycon (map go ls)
      ListTy a          -> ListTy (go a)
      ArenaTy           -> ArenaTy
      SymSetTy          -> SymSetTy
      SymHashTy         -> SymHashTy
      IntHashTy         -> IntHashTy
    where
      go :: forall a. Renamable a => a -> a
      go = gRename env

-- | Straightforward parametric polymorphism.
data TyScheme = ForAll [TyVar] Ty0
 deriving (Show, Read, Eq, Ord, Generic, NFData)

-- instance FreeVars TyScheme where
--   gFreeVars (ForAll tvs ty) = gFreeVars ty `S.difference` (S.fromList tvs)

arrIns :: TyScheme -> [Ty0]
arrIns (ForAll _ (ArrowTy i _)) = i
arrIns err = error $ "arrIns: Not an arrow type: " ++ show err

arrOut :: TyScheme -> Ty0
arrOut (ForAll _ (ArrowTy _ o)) = o
arrOut err = error $ "arrOut: Not an arrow type: " ++ show err

arrIns' :: Ty0 -> [Ty0]
arrIns' (ArrowTy i _) = i
arrIns' err = error $ "arrIns': Not an arrow type: " ++ show err

tyFromScheme :: TyScheme -> Ty0
tyFromScheme (ForAll _ a) = a

tyVarsFromScheme :: TyScheme -> [TyVar]
tyVarsFromScheme (ForAll a _) = a

isFunTy :: Ty0 -> Bool
isFunTy ArrowTy{} = True
isFunTy _ = False

isCallUnsaturated :: TyScheme -> [Exp0] -> Bool
isCallUnsaturated sigma args = length args < length (arrIns sigma)

saturateCall :: MonadState Int m => TyScheme -> Exp0 -> m Exp0
saturateCall sigma ex =
  case ex of
    AppE f [] args -> do
      -- # args needed to saturate this call-site.
      let args_wanted = length (arrIns sigma) - length args
      new_args <- mapM (\_ -> gensym "sat_arg_") [0..(args_wanted-1)]
      new_tys  <- mapM (\_ -> newMetaTy) new_args
      pure $
        Ext (LambdaE (zip new_args new_tys)
               (AppE f [] (args ++ (map VarE new_args))))

    AppE _ tyapps _ ->
      error $ "unCurryCall: Expected tyapps to be [], got: " ++ sdoc tyapps
    _ -> error $ "unCurryCall: " ++ sdoc ex ++ " is not a call-site."

-- | Get the free TyVars from types; no duplicates in result.
tyVarsInTy :: Ty0 -> [TyVar]
tyVarsInTy ty = tyVarsInTys [ty]

-- | Like 'tyVarsInTy'.
tyVarsInTys :: [Ty0] -> [TyVar]
tyVarsInTys tys = foldr (go []) [] tys
  where
    go :: [TyVar] -> Ty0 -> [TyVar] -> [TyVar]
    go bound ty acc =
      case ty of
        IntTy  -> acc
        SymTy0 -> acc
        BoolTy -> acc
        TyVar tv -> if (tv `elem` bound) || (tv `elem` acc)
                    then acc
                    else tv : acc
        MetaTv _ -> acc
        ProdTy tys1     -> foldr (go bound) acc tys1
        SymDictTy _ ty1   -> go bound ty1 acc
        ArrowTy tys1 b  -> foldr (go bound) (go bound b acc) tys1
        PackedTy _ tys1 -> foldr (go bound) acc tys1
        ListTy ty1      -> go bound ty1 acc
        ArenaTy -> acc
        SymSetTy -> acc
        SymHashTy -> acc
        IntHashTy -> acc

-- | Get the MetaTvs from a type; no duplicates in result.
metaTvsInTy :: Ty0 -> [MetaTv]
metaTvsInTy ty = metaTvsInTys [ty]

-- | Like 'metaTvsInTy'.
metaTvsInTys :: [Ty0] -> [MetaTv]
metaTvsInTys tys = foldr go [] tys
  where
    go :: Ty0 -> [MetaTv] -> [MetaTv]
    go ty acc =
      case ty of
        MetaTv tv -> if tv `elem` acc
                     then acc
                     else tv : acc
        IntTy   -> acc
        SymTy0  -> acc
        BoolTy  -> acc
        TyVar{} -> acc
        ProdTy tys1     -> foldr go acc tys1
        SymDictTy _ ty1   -> go ty1 acc
        ArrowTy tys1 b  -> go b (foldr go acc tys1)
        PackedTy _ tys1 -> foldr go acc tys1
        ListTy ty1      -> go ty1 acc
        ArenaTy -> acc
        SymSetTy -> acc
        SymHashTy -> acc
        IntHashTy -> acc

-- | Like 'tyVarsInTy'.
tyVarsInTyScheme :: TyScheme -> [TyVar]
tyVarsInTyScheme (ForAll tyvars ty) = tyVarsInTy ty \\ tyvars

-- | Like 'metaTvsInTy'.
metaTvsInTyScheme :: TyScheme -> [MetaTv]
metaTvsInTyScheme (ForAll _ ty) = metaTvsInTy ty -- ForAll binds TyVars only

-- | Like 'metaTvsInTys'.
metaTvsInTySchemes :: [TyScheme] -> [MetaTv]
metaTvsInTySchemes tys = concatMap metaTvsInTyScheme tys

arrowTysInTy :: Ty0 -> [Ty0]
arrowTysInTy = go []
  where
    go acc ty =
      case ty of
        IntTy    -> acc
        SymTy0   -> acc
        BoolTy   -> acc
        ArenaTy  -> acc
        TyVar{}  -> acc
        MetaTv{} -> acc
        ProdTy tys    -> foldl go acc tys
        SymDictTy _ a   -> go acc a
        ArrowTy tys b -> go (foldl go acc tys) b ++ [ty]
        PackedTy _ vs -> foldl go acc vs
        ListTy a -> go acc a
        SymSetTy  -> acc
        SymHashTy -> acc
        IntHashTy -> acc

-- | Replace the specified quantified type variables by
-- given meta type variables.
substTyVar :: M.Map TyVar Ty0 -> Ty0 -> Ty0
substTyVar mp ty =
  case ty of
    IntTy    -> ty
    SymTy0   -> ty
    BoolTy   -> ty
    TyVar v  -> M.findWithDefault ty v mp
    MetaTv{} -> ty
    ProdTy tys  -> ProdTy (map go tys)
    SymDictTy v t -> SymDictTy v (go t)
    ArrowTy tys b  -> ArrowTy (map go tys) (go b)
    PackedTy t tys -> PackedTy t (map go tys)
    ListTy t -> ListTy (go t)
    ArenaTy -> ty
    SymSetTy -> ty
    SymHashTy -> ty
    IntHashTy -> ty
  where
    go = substTyVar mp


-- Hack. In the specializer, we'd like to know the type of the scrutinee.
-- However, we cannot derive Typeable for L0.
--
-- Typeable uses the type 'UrTy' which is shared by the IR's L1, L2 and L3, but not L0.
-- L0 uses it's own type Ty0, which is not an instance of 'UrTy'.
-- Can we merge 'Ty0' and 'UrTy' ? Well we can, but we would end up polluting 'UrTy'
-- with type variables and function types, which should be unused after L0.
-- Or, we can have a special (Typeable L0), which is what recoverType is.
-- ¯\_(ツ)_/¯
--
recoverType :: DDefs0 -> Env2 Ty0 -> Exp0 -> Ty0
recoverType ddfs env2 ex =
  case ex of
    VarE v       -> M.findWithDefault (error $ "recoverType: Unbound variable " ++ show v) v (vEnv env2)
    LitE _       -> IntTy
    LitSymE _    -> IntTy
    AppE v tyapps _ -> let (ForAll tyvars (ArrowTy _ retty)) = fEnv env2 # v
                       in substTyVar (M.fromList (fragileZip tyvars tyapps)) retty
    -- PrimAppE (DictInsertP ty) ((L _ (VarE v)):_) -> SymDictTy (Just v) ty
    -- PrimAppE (DictEmptyP  ty) ((L _ (VarE v)):_) -> SymDictTy (Just v) ty
    PrimAppE p exs -> dbgTraceIt ("recovertype/primapp: " ++ show p ++ " " ++ show exs) $ primRetTy1 p
    LetE (v,_,t,_) e -> recoverType ddfs (extendVEnv v t env2) e
    IfE _ e _        -> recoverType ddfs env2 e
    MkProdE es       -> ProdTy $ map (recoverType ddfs env2) es
    DataConE (ProdTy locs) c _ -> PackedTy (getTyOfDataCon ddfs c) locs
    DataConE loc c _ -> PackedTy (getTyOfDataCon ddfs c) [loc]
    TimeIt e _ _     -> recoverType ddfs env2 e
    MapE _ e         -> recoverType ddfs env2 e
    FoldE _ _ e      -> recoverType ddfs env2 e
    ProjE i e ->
      case recoverType ddfs env2 e of
        (ProdTy tys) -> tys !! i
        oth -> error$ "typeExp: Cannot project fields from this type: "++show oth
                      ++"\nExpression:\n  "++ sdoc ex
                      ++"\nEnvironment:\n  "++sdoc (vEnv env2)
    SpawnE v tyapps _ -> let (ForAll tyvars (ArrowTy _ retty)) = fEnv env2 # v
                         in substTyVar (M.fromList (fragileZip tyvars tyapps)) retty
    SyncE -> ProdTy []
    IsBigE _ -> BoolTy
    CaseE _ mp ->
      let (c,args,e) = head mp
          args' = map fst args
      in recoverType ddfs (extendsVEnv (M.fromList (zip args' (lookupDataCon ddfs c))) env2) e
    WithArenaE{} -> error "recoverType: WithArenaE not handled."
    Ext ext ->
      case ext of
        LambdaE args bod ->
          recoverType ddfs (extendsVEnv (M.fromList args) env2) bod
        FunRefE _ f ->
          case (M.lookup f (vEnv env2), M.lookup f (fEnv env2)) of
            (Nothing, Nothing) -> error $ "recoverType: Unbound function " ++ show f
            (Just ty, _) -> ty
            (_, Just ty) -> tyFromScheme ty -- CSK: Not sure if this is what we want?
        PolyAppE{}  -> error "recoverTypeep: TODO PolyAppE"
        BenchE fn _ _ _ -> outTy $ fEnv env2 # fn
        ParE0 ls -> ProdTy $ map (recoverType ddfs env2) ls
        L _ e    -> recoverType ddfs env2 e
  where
    -- Return type for a primitive operation.
    primRetTy1 :: Prim Ty0 -> Ty0
    primRetTy1 p =
      case p of
        AddP -> IntTy
        SubP -> IntTy
        MulP -> IntTy
        DivP -> IntTy
        ModP -> IntTy
        ExpP -> IntTy
        RandP-> IntTy
        EqSymP  -> BoolTy
        EqIntP  -> BoolTy
        LtP  -> BoolTy
        GtP  -> BoolTy
        OrP  -> BoolTy
        LtEqP-> BoolTy
        GtEqP-> BoolTy
        AndP -> BoolTy
        MkTrue  -> BoolTy
        MkFalse -> BoolTy
        Gensym  -> SymTy0
        SymAppend      -> IntTy
        SizeParam      -> IntTy
        DictHasKeyP _  -> BoolTy
        DictEmptyP ty  -> SymDictTy Nothing ty
        DictInsertP ty -> SymDictTy Nothing ty
        DictLookupP ty -> ty
        VEmptyP ty     -> ListTy ty
        VNthP ty       -> ty
        VLengthP _ty   -> IntTy
        VUpdateP ty    -> ListTy ty
        VSnocP ty      -> ListTy ty
        VSortP ty      -> ListTy ty
        (ErrorP _ ty)  -> ty
        ReadPackedFile _ _ _ ty -> ty
        RequestEndOf -> error "primRetTy1: RequestEndOf not handled yet"
        PrintInt     -> error "primRetTy1: PrintInt not handled yet"
        PrintSym     -> error "primRetTy1: PrintSym not handled yet"
        ReadInt      -> error "primRetTy1: ReadInt not handled yet"
        SymSetEmpty  -> error "primRetTy1: SymSetEmpty not handled yet"
        SymSetContains-> error "primRetTy1: SymSetContains not handled yet"
        SymSetInsert -> error "primRetTy1: SymSetInsert not handled yet"
        SymHashEmpty -> error "primRetTy1: SymHashEmpty not handled yet"
        SymHashInsert-> error "primRetTy1: SymHashInsert not handled yet"
        SymHashLookup-> error "primRetTy1: SymHashLookup not handled yet"
        IntHashEmpty -> error "primRetTy1: IntHashEmpty not handled yet"
        IntHashInsert-> error "primRetTy1: IntHashInsert not handled yet"
        IntHashLookup-> error "primRetTy1: IntHashLookup not handled yet"


{-

-- | Variable definitions

-- ^ Monomorphic version
data VarDef a ex = VarDef { varName :: Var
                          , varTy   :: a
                          , varBody :: ex }
  deriving (Show, Eq, Ord, Generic, NFData)

type VarDefs a ex = M.Map Var (VarDef a ex)

type FunDefs0 = M.Map Var FunDef0

type FunDef0 = FunDef (L Exp0)

instance FunctionTy Ty0 where
  type ArrowTy Ty0 = (Ty0 , Ty0)
  inTy = fst
  outTy = snd

-- ^ Polymorphic version

data PVDef a ex = PVDef { vName :: Var
                        , vTy   :: Scheme a
                        , vBody :: ex }
  deriving (Show, Read, Eq, Ord, Generic, NFData)

type PVDefs a ex = M.Map Var (PVDef a ex)

-- | for now, using a specialized DDef for L0
-- this enables the DDefs to have type variables
type PDDefs a = M.Map Var (PDDef a)

data PDDef a = PDDef { dName :: Var
                     , dCons :: [(DataCon,[(IsBoxed,Scheme a)])] } -- ^ Polymorphic data constructors
  deriving (Read,Show,Eq,Ord, Generic)


-- | for now, using a specialized FunDef for L0
-- theoretically these should disappear after monomorphization
-- this enables the FunDefs to have type schemes
type PFDefs a ex = M.Map Var (PFDef a ex)

data PFDef a ex  = PFDef { fName :: Var
                         , fArg  :: Var
                         , fTy   :: Scheme a -- ^ the type will be a ForAll
                         , fBody :: ex }
  deriving (Read,Show,Eq,Ord, Functor, Generic)

-- ^ Polymorphic program
data PProg = PProg { pddefs    :: PDDefs Ty0
                   , pfundefs  :: PFDefs Ty0 (L Exp0)
                   , pvardefs  :: PVDefs Ty0 (L Exp0)
                   , pmainExp  :: Maybe (L Exp0)
                   }
  deriving (Show, Eq, Ord, Generic)

-- ^ Monomorphic program
data MProg = MProg { ddefs    :: DDefs Ty0
                   , fundefs  :: FunDefs0
                   , vardefs  :: VarDefs Ty0 (L Exp0)
                   , mainExp  :: Maybe (L Exp0)
                   }
  deriving (Show, Eq, Ord, Generic)

-- | some type defns to make things look cleaner
type Exp = (L Exp0)

-- | we now have curried functions and curried calls
-- curried functions are these variable defns
-- but curried calls vs function calls are PolyAppE vs AppE
type CurFun  = VarDef Ty0 Exp
type CCall = Exp

-- | Monomorphized functions
type L0Fun = FunDef0
type FCall = Exp

arrIn :: Ty0 -> Ty0
arrIn (ArrowTy i _) = i
arrIn err = error $ "arrIn: Not an arrow type: " ++ show err

arrOut :: Ty0 -> Ty0
arrOut (ArrowTy _ o) = o
arrOut err = error $ "arrOut: Not an arrow type: " ++ show err

typeFromScheme :: Scheme a -> a
typeFromScheme (ForAll _ a) = a

initFunEnv :: PFDefs Ty0 Exp -> FunEnv Ty0
initFunEnv fds = M.foldr (\fn acc -> let fnTy = typeFromScheme (fTy fn)
                                         fntyin  = arrIn fnTy
                                         fntyout = arrOut fnTy
                                     in M.insert (fName fn) (fntyin, fntyout) acc)
                 M.empty fds

initVarEnv :: PVDefs Ty0 Exp -> M.Map Var Ty0
initVarEnv vds = M.foldr (\v acc -> M.insert (vName v) (typeFromScheme (vTy v)) acc)
                 M.empty vds
-}
