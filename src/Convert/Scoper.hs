{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Standardized scope traversal utilities
 -
 - This module provides a series of "scopers" which track the scope of blocks,
 - generate loops, tasks, and functions, and provides the ability to insert and
 - lookup elements in a scope-aware way. It also provides the ability to check
 - whether the current node is within a procedural context.
 -
 - The interfaces take in a mappers for each of: Decl, ModuleItem, GenItem, and
 - Stmt. Note that Function, Task, Always, Initial, and Final are NOT passed
 - through the ModuleItem mapper as those constructs only provide Stmts and
 - Decls. For the same reason, Decl ModuleItems are not passed through the
 - ModuleItem mapper.
 -
 - All of the mappers should not recursively traverse any of the items captured
 - by any of the other mappers. Scope resolution enforces data declaration
 - ordering.
 -}

module Convert.Scoper
    ( Scoper
    , ScoperT
    , evalScoper
    , evalScoperT
    , partScoper
    , partScoperT
    , insertElem
    , lookupExpr
    , lookupLHS
    , lookupIdent
    , lookupAccesses
    , lookupExprM
    , lookupLHSM
    , lookupIdentM
    , lookupAccessesM
    , Access(..)
    , Scopes
    , embedScopes
    , withinProcedure
    , withinProcedureM
    ) where

import Control.Monad.State
import Data.Functor.Identity (runIdentity)
import Data.List (inits)
import Data.Maybe (catMaybes)
import qualified Data.Map.Strict as Map

import Convert.Traverse
import Language.SystemVerilog.AST

-- user monad aliases
type Scoper a = State (Scopes a)
type ScoperT a m = StateT (Scopes a) m

-- one tier of scope construction
data Tier = Tier
    { tierName :: Identifier
    , tierIndex :: Identifier
    } deriving (Eq, Show)

-- one layer of scope inspection
data Access = Access
    { accessName :: Identifier
    , accessIndex :: Expr
    } deriving (Eq, Show)

type Mapping a = Map.Map Identifier (Entry a)

data Entry a = Entry
    { eElement :: Maybe a
    , eIndex :: Identifier
    , eMapping :: Mapping a
    } deriving Show

data Scopes a = Scopes
    { sCurrent :: [Tier]
    , sMapping :: Mapping a
    , sProcedure :: Bool
    } deriving Show

embedScopes :: Monad m => (Scopes a -> b -> c) -> b -> ScoperT a m c
embedScopes func x = do
    scopes <- get
    return $ func scopes x

setScope :: [Tier] -> Entry a -> Mapping a -> Mapping a
setScope [] _ = error "setScope invariant violated"
setScope [Tier name _] newEntry =
    Map.insert name newEntry
setScope (Tier name _ : tiers) newEntry =
    Map.adjust adjustment name
    where
        adjustment entry =
            entry { eMapping = setScope tiers newEntry (eMapping entry) }

enterScope :: Monad m => Identifier -> Identifier -> ScoperT a m ()
enterScope name index = do
    current <- gets sCurrent
    let current' = current ++ [Tier name index]
    existingResult <- lookupIdentM name
    let existingElement = fmap thd3 existingResult
    let entry = Entry existingElement index Map.empty
    mapping <- gets sMapping
    let mapping' = setScope current' entry mapping
    procedure <- gets sProcedure
    put $ Scopes current' mapping' procedure
    where thd3 (_, _, c) = c

exitScope :: Monad m => Identifier -> Identifier -> ScoperT a m ()
exitScope name index = do
    let tier = Tier name index
    current <- gets sCurrent
    mapping <- gets sMapping
    procedure <- gets sProcedure
    if null current || last current /= tier
        then error "exitScope invariant violated"
        else do
            let current' = init current
            put $ Scopes current' mapping procedure

enterProcedure :: Monad m => ScoperT a m ()
enterProcedure = do
    current <- gets sCurrent
    mapping <- gets sMapping
    procedure <- gets sProcedure
    if procedure
        then error "enterProcedure invariant failed"
        else put $ Scopes current mapping True

exitProcedure :: Monad m => ScoperT a m ()
exitProcedure = do
    current <- gets sCurrent
    mapping <- gets sMapping
    procedure <- gets sProcedure
    if not procedure
        then error "exitProcedure invariant failed"
        else put $ Scopes current mapping False

tierToAccess :: Tier -> Access
tierToAccess (Tier x "") = Access x Nil
tierToAccess (Tier x y) = Access x (Ident y)

exprToAccesses :: Expr -> Maybe [Access]
exprToAccesses (Ident x) = Just [Access x Nil]
exprToAccesses (Bit (Ident x) y) = Just [Access x y]
exprToAccesses (Bit (Dot e x) y) = do
    accesses <- exprToAccesses e
    Just $ accesses ++ [Access x y]
exprToAccesses (Dot e x) = do
    accesses <- exprToAccesses e
    Just $ accesses ++ [Access x Nil]
exprToAccesses _ = Nothing

lhsToAccesses :: LHS -> Maybe [Access]
lhsToAccesses = exprToAccesses . lhsToExpr

insertElem :: Monad m => Identifier -> a -> ScoperT a m ()
insertElem name element = do
    current <- gets sCurrent
    mapping <- gets sMapping
    procedure <- gets sProcedure
    let entry = Entry (Just element) "" Map.empty
    let mapping' = setScope (current ++ [Tier name ""]) entry mapping
    put $ Scopes current mapping' procedure

type Replacements = Map.Map Identifier Expr

attemptResolve :: Mapping a -> [Access] -> Maybe (Replacements, a)
attemptResolve _ [] = Nothing
attemptResolve mapping (Access x e : rest) = do
    Entry maybeElement index subMapping <- Map.lookup x mapping
    if null rest && e == Nil then
        fmap (Map.empty, ) maybeElement
    else do
        (replacements, element) <- attemptResolve subMapping rest
        if e /= Nil && not (null index) then do
            let replacements' = Map.insert index e replacements
            Just (replacements', element)
        else if e == Nil && null index then
            Just (replacements, element)
        else
            Nothing

type LookupResult a = Maybe ([Access], Replacements, a)

lookupExprM :: Monad m => Expr -> ScoperT a m (LookupResult a)
lookupExprM = embedScopes lookupExpr

lookupLHSM :: Monad m => LHS -> ScoperT a m (LookupResult a)
lookupLHSM = embedScopes lookupLHS

lookupIdentM :: Monad m => Identifier -> ScoperT a m (LookupResult a)
lookupIdentM = embedScopes lookupIdent

lookupAccessesM :: Monad m => [Access] -> ScoperT a m (LookupResult a)
lookupAccessesM = embedScopes lookupAccesses

lookupExpr :: Scopes a -> Expr -> LookupResult a
lookupExpr scopes = join . fmap (lookupAccesses scopes) . exprToAccesses

lookupLHS :: Scopes a -> LHS -> LookupResult a
lookupLHS scopes = join . fmap (lookupAccesses scopes) . lhsToAccesses

lookupIdent :: Scopes a -> Identifier -> LookupResult a
lookupIdent scopes ident = lookupAccesses scopes [Access ident Nil]

lookupAccesses :: Scopes a -> [Access] -> LookupResult a
lookupAccesses scopes accesses = do
    if null results
        then Nothing
        else Just $ last results
    where
        options = inits $ map tierToAccess (sCurrent scopes)
        try option =
            fmap toResult $ attemptResolve (sMapping scopes) full
            where
                full = option ++ accesses
                toResult (a, b) = (full, a, b)
        results = catMaybes $ map try options

withinProcedureM :: Monad m => ScoperT a m Bool
withinProcedureM = gets sProcedure

withinProcedure :: Scopes a -> Bool
withinProcedure = sProcedure

evalScoper
    :: MapperM (Scoper a) Decl
    -> MapperM (Scoper a) ModuleItem
    -> MapperM (Scoper a) GenItem
    -> MapperM (Scoper a) Stmt
    -> Identifier
    -> [ModuleItem]
    -> [ModuleItem]
evalScoper declMapper moduleItemMapper genItemMapper stmtMapper topName items =
    runIdentity $ evalScoperT
    declMapper moduleItemMapper genItemMapper stmtMapper topName items

evalScoperT
    :: forall a m. Monad m
    => MapperM (ScoperT a m) Decl
    -> MapperM (ScoperT a m) ModuleItem
    -> MapperM (ScoperT a m) GenItem
    -> MapperM (ScoperT a m) Stmt
    -> Identifier
    -> [ModuleItem]
    -> m [ModuleItem]
evalScoperT declMapper moduleItemMapper genItemMapper stmtMapper topName items =
    evalStateT operation initialState
    where
        operation :: ScoperT a m [ModuleItem]
        operation = do
            enterScope topName ""
            items' <- mapM fullModuleItemMapper items
            exitScope topName ""
            return items'
        initialState = Scopes [] Map.empty False

        fullStmtMapper :: Stmt -> ScoperT a m Stmt
        fullStmtMapper (Block kw name decls stmts) = do
            enterScope name ""
            decls' <- mapM declMapper decls
            stmts' <- mapM fullStmtMapper stmts
            exitScope name ""
            return $ Block kw name decls' stmts'
        -- TODO: Do we need to support the various procedural loops?
        fullStmtMapper stmt =
            stmtMapper stmt >>= traverseSinglyNestedStmtsM fullStmtMapper

        mapTFDecls :: [Decl] -> ScoperT a m [Decl]
        mapTFDecls = mapTFDecls' 0
            where
                mapTFDecls' :: Int -> [Decl] -> ScoperT a m [Decl]
                mapTFDecls' _ [] = return []
                mapTFDecls' idx (decl : decls) =
                    case argIdxDecl decl of
                        Nothing -> do
                            decl' <- declMapper decl
                            decls' <- mapTFDecls' idx decls
                            return $ decl' : decls'
                        Just declFunc -> do
                            _ <- declMapper $ declFunc idx
                            decl' <- declMapper decl
                            decls' <- mapTFDecls' (idx + 1) decls
                            return $ decl' : decls'

                argIdxDecl :: Decl -> Maybe (Int -> Decl)
                argIdxDecl (Variable d t _ a e) =
                    if d == Local
                        then Nothing
                        else Just $ \i -> Variable d t (show i) a e
                argIdxDecl Param{} = Nothing
                argIdxDecl ParamType{} = Nothing
                argIdxDecl CommentDecl{} = Nothing

        fullModuleItemMapper :: ModuleItem -> ScoperT a m ModuleItem
        fullModuleItemMapper (MIPackageItem (Function ml t x decls stmts)) = do
            enterProcedure
            t' <- do
                res <- declMapper $ Variable Local t x [] Nil
                case res of
                    Variable Local newType _ [] Nil -> return newType
                    _ -> error $ "redirected func ret traverse failed: " ++ show res
            enterScope x ""
            decls' <- mapTFDecls decls
            stmts' <- mapM fullStmtMapper stmts
            exitScope x ""
            exitProcedure
            return $ MIPackageItem $ Function ml t' x decls' stmts'
        fullModuleItemMapper (MIPackageItem (Task     ml   x decls stmts)) = do
            enterProcedure
            enterScope x ""
            decls' <- mapTFDecls decls
            stmts' <- mapM fullStmtMapper stmts
            exitScope x ""
            exitProcedure
            return $ MIPackageItem $ Task     ml    x decls' stmts'
        fullModuleItemMapper (MIPackageItem (Decl decl)) =
            declMapper decl >>= return . MIPackageItem . Decl
        fullModuleItemMapper (AlwaysC kw stmt) = do
            enterProcedure
            stmt' <- fullStmtMapper stmt
            exitProcedure
            return $ AlwaysC kw stmt'
        fullModuleItemMapper (Initial stmt) = do
            enterProcedure
            stmt' <- fullStmtMapper stmt
            exitProcedure
            return $ Initial stmt'
        fullModuleItemMapper (Final stmt) = do
            enterProcedure
            stmt' <- fullStmtMapper stmt
            exitProcedure
            return $ Final stmt'
        fullModuleItemMapper (Generate genItems) =
            mapM fullGenItemMapper genItems >>= return . Generate
        fullModuleItemMapper (MIAttr attr item) =
            fullModuleItemMapper item >>= return . MIAttr attr
        fullModuleItemMapper item = moduleItemMapper item

        -- TODO: This doesn't yet support implicit naming of generate blocks as
        -- blocks as described in Section 27.6.
        fullGenItemMapper :: GenItem -> ScoperT a m GenItem
        fullGenItemMapper = genItemMapper >=> scopeGenItemMapper
        scopeGenItemMapper :: GenItem -> ScoperT a m GenItem
        scopeGenItemMapper (GenFor (index, a) b c (GenBlock name genItems)) = do
            enterScope name index
            genItems' <- mapM fullGenItemMapper genItems
            exitScope name index
            return $ GenFor (index, a) b c (GenBlock name genItems')
        scopeGenItemMapper (GenBlock name genItems) = do
            enterScope name ""
            genItems' <- mapM fullGenItemMapper genItems
            exitScope name ""
            return $ GenBlock name genItems'
        scopeGenItemMapper (GenModuleItem moduleItem) =
            fullModuleItemMapper moduleItem >>= return . GenModuleItem
        scopeGenItemMapper genItem =
            traverseSinglyNestedGenItemsM fullGenItemMapper genItem

partScoper
    :: MapperM (Scoper a) Decl
    -> MapperM (Scoper a) ModuleItem
    -> MapperM (Scoper a) GenItem
    -> MapperM (Scoper a) Stmt
    -> Description
    -> Description
partScoper declMapper moduleItemMapper genItemMapper stmtMapper part =
    runIdentity $ partScoperT
        declMapper moduleItemMapper genItemMapper stmtMapper part

partScoperT
    :: Monad m
    => MapperM (ScoperT a m) Decl
    -> MapperM (ScoperT a m) ModuleItem
    -> MapperM (ScoperT a m) GenItem
    -> MapperM (ScoperT a m) Stmt
    -> Description
    -> m Description
partScoperT declMapper moduleItemMapper genItemMapper stmtMapper =
    mapper
    where
        operation = evalScoperT
            declMapper moduleItemMapper genItemMapper stmtMapper
        mapper (Part attrs extern kw liftetime name ports items) = do
            items' <- operation name items
            return $ Part attrs extern kw liftetime name ports items'
        mapper description = return description
