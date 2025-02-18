{-# LANGUAGE TupleSections #-}
{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Conversion for flattening variables with multiple packed dimensions
 -
 - This removes one packed dimension per identifier per pass. This works fine
 - because all conversions are repeatedly applied.
 -
 - We previously had a very complex conversion which used `generate` to make
 - flattened and unflattened versions of the array as necessary. This has now
 - been "simplified" to always flatten the array, and then rewrite all usages of
 - the array as appropriate.
 -
 - A previous iteration of this conversion aggressively flattened all dimensions
 - (even if unpacked) in any multidimensional data declaration. This had the
 - unfortunate side effect of packing memories, which could hinder efficient
 - synthesis. Now this conversion only flattens packed dimensions and leaves the
 - (only potentially necessary) movement of dimensions from unpacked to packed
 - to the separate UnpackedArray conversion.
 -
 - Note that the ranges being combined may not be of the form [hi:lo], and need
 - not even be the same direction! Because of this, we have to flip around the
 - indices of certain accesses.
 -}

module Convert.MultiplePacked (convert) where

import Convert.ExprUtils
import Control.Monad ((>=>))
import Data.Tuple (swap)
import Data.Maybe (isJust)
import qualified Data.Map.Strict as Map

import Convert.Scoper
import Convert.Traverse
import Language.SystemVerilog.AST

type TypeInfo = (Type, [Range])

convert :: [AST] -> [AST]
convert = map $ traverseDescriptions convertDescription

convertDescription :: Description -> Description
convertDescription (description @ (Part _ _ Module _ _ _ _)) =
    partScoper traverseDeclM traverseModuleItemM traverseGenItemM traverseStmtM
    description
convertDescription other = other

-- collects and converts declarations with multiple packed dimensions
traverseDeclM :: Decl -> Scoper TypeInfo Decl
traverseDeclM (Variable dir t ident a e) = do
    t' <- traverseTypeM t a ident
    traverseDeclExprsM traverseExprM $ Variable dir t' ident a e
traverseDeclM net @ Net{} =
    traverseNetAsVarM traverseDeclM net
traverseDeclM (Param s t ident e) = do
    t' <- traverseTypeM t [] ident
    traverseDeclExprsM traverseExprM $ Param s t' ident e
traverseDeclM other = traverseDeclExprsM traverseExprM other

traverseTypeM :: Type -> [Range] -> Identifier -> Scoper TypeInfo Type
traverseTypeM t a ident = do
    tScoped <- scopeType t
    insertElem ident (tScoped, a)
    t' <- case t of
        Struct pk fields rs -> do
            fields' <- flattenFields fields
            return $ Struct pk fields' rs
        Union  pk fields rs -> do
            fields' <- flattenFields fields
            return $ Union  pk fields' rs
        _ -> return t
    let (tf, rs) = typeRanges t'
    if length rs <= 1
        then return t'
        else do
            let r1 : r2 : rest = rs
            let rs' = (combineRanges r1 r2) : rest
            return $ tf rs'
    where
        flattenFields fields = do
            let (fieldTypes, fieldNames) = unzip fields
            fieldTypes' <- mapM (\x -> traverseTypeM x [] "") fieldTypes
            return $ zip fieldTypes' fieldNames

traverseModuleItemM :: ModuleItem -> Scoper TypeInfo ModuleItem
traverseModuleItemM (Instance m p x rs l) = do
    -- converts multi-dimensional instances
    rs' <- if length rs <= 1
        then return rs
        else do
            let t = Implicit Unspecified rs
            tScoped <- scopeType t
            insertElem x (tScoped, [])
            let r1 : r2 : rest = rs
            return $ (combineRanges r1 r2) : rest
    traverseExprsM traverseExprM $ Instance m p x rs' l
traverseModuleItemM item =
    traverseLHSsM  traverseLHSM  item >>=
    traverseExprsM traverseExprM

-- combines two ranges into one flattened range
combineRanges :: Range -> Range -> Range
combineRanges r1 r2 = r
    where
        rYY = combine r1 r2
        rYN = combine r1 (swap r2)
        rNY = combine (swap r1) r2
        rNN = combine (swap r1) (swap r2)
        rY = endianCondRange r2 rYY rYN
        rN = endianCondRange r2 rNY rNN
        r = endianCondRange r1 rY rN

        combine :: Range -> Range -> Range
        combine (s1, e1) (s2, e2) =
            (simplify upper, simplify lower)
            where
                size1 = rangeSizeHiLo (s1, e1)
                size2 = rangeSizeHiLo (s2, e2)
                lower = BinOp Add e2 (BinOp Mul e1 size2)
                upper = BinOp Add (BinOp Mul size1 size2)
                            (BinOp Sub lower (RawNum 1))

traverseStmtM :: Stmt -> Scoper TypeInfo Stmt
traverseStmtM =
    traverseStmtLHSsM  traverseLHSM  >=>
    traverseStmtExprsM traverseExprM

traverseExprM :: Expr -> Scoper TypeInfo Expr
traverseExprM = traverseNestedExprsM convertExprM

traverseGenItemM :: GenItem -> Scoper TypeInfo GenItem
traverseGenItemM = traverseGenItemExprsM traverseExprM

-- LHSs need to be converted too. Rather than duplicating the procedures, we
-- turn LHSs into expressions temporarily and use the expression conversion.
traverseLHSM :: LHS -> Scoper TypeInfo LHS
traverseLHSM = traverseNestedLHSsM traverseLHSSingleM
    where
        -- We can't use traverseExprM directly because that would cause Exprs
        -- inside of LHSs to be converted twice in a single cycle!
        traverseLHSSingleM :: LHS -> Scoper TypeInfo LHS
        traverseLHSSingleM lhs = do
            let expr = lhsToExpr lhs
            expr' <- convertExprM expr
            case exprToLHS expr' of
                Just lhs' -> return lhs'
                Nothing -> error $ "multi-packed conversion created non-LHS from "
                    ++ (show expr) ++ " to " ++ (show expr')

convertExprM :: Expr -> Scoper TypeInfo Expr
convertExprM = embedScopes convertExpr

convertExpr :: Scopes TypeInfo -> Expr -> Expr
convertExpr scopes =
    rewriteExpr
    where
        -- removes the innermost dimensions of the given type information, and
        -- applies the given transformation to the expression
        dropLevel :: (Expr -> Expr) -> (TypeInfo, Expr) -> (TypeInfo, Expr)
        dropLevel nest ((t, a), expr) =
            ((tf rs', a'), nest expr)
            where
                (tf, rs) = typeRanges t
                (rs', a') = case (rs, a) of
                    ([], []) -> ([], [])
                    (packed, []) -> (tail packed, [])
                    (packed, unpacked) -> (packed, tail unpacked)

        -- given an expression, returns its type information and a tagged
        -- version of the expression, if possible
        levels :: Expr -> Maybe (TypeInfo, Expr)
        levels (Bit expr a) =
            case levels expr of
                Just info -> Just $ dropLevel (\expr' -> Bit expr' a) info
                Nothing -> fallbackLevels $ Bit expr a
        levels (Range expr a b) =
            fmap (dropLevel $ \expr' -> Range expr' a b) (levels expr)
        levels (Dot expr x) =
            case levels expr of
                Just ((Struct _ fields [], []), expr') -> dropDot fields expr'
                Just ((Union  _ fields [], []), expr') -> dropDot fields expr'
                _ -> fallbackLevels $ Dot expr x
            where
                dropDot :: [Field] -> Expr -> Maybe (TypeInfo, Expr)
                dropDot fields expr' =
                    if Map.member x fieldMap
                        then Just ((fieldType, []), Dot expr' x)
                        else Nothing
                    where
                        fieldMap = Map.fromList $ map swap fields
                        fieldType = fieldMap Map.! x
        levels expr = fallbackLevels expr

        fallbackLevels :: Expr -> Maybe (TypeInfo, Expr)
        fallbackLevels expr =
            fmap ((, expr) . thd3) res
            where
                res = lookupElem scopes expr
                thd3 (_, _, c) = c

        -- given an expression, returns the two most significant (innermost,
        -- leftmost) packed dimensions and a tagged version of the expression,
        -- if possible
        dims :: Expr -> Maybe (Range, Range, Expr)
        dims expr =
            case levels expr of
                Just ((t, []), expr') ->
                    case snd $ typeRanges t of
                        dimInner : dimOuter : _ ->
                            Just (dimInner, dimOuter, expr')
                        _ -> Nothing
                _ -> Nothing

        -- if the given range is flipped, the result will flip around the given
        -- indexing expression
        orientIdx :: Range -> Expr -> Expr
        orientIdx r e =
            endianCondExpr r e eSwapped
            where
                eSwapped = BinOp Sub (snd r) (BinOp Sub e (fst r))

        -- Converted idents are prefixed with an invalid character to ensure
        -- that are not converted twice when the traversal steps downward. When
        -- the prefixed identifier is encountered at the lowest level, it is
        -- removed.

        tag = ':'

        rewriteExpr :: Expr -> Expr
        rewriteExpr (Ident x) =
            if head x == tag
                then Ident $ tail x
                else Ident x
        rewriteExpr (orig @ (Bit (Bit expr idxInner) idxOuter)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then Bit expr' idx'
                else rewriteExprLowPrec orig
            where
                maybeDims = dims expr
                Just (dimInner, dimOuter, expr') = maybeDims
                idxInner' = orientIdx dimInner idxInner
                idxOuter' = orientIdx dimOuter idxOuter
                base = BinOp Mul idxInner' (rangeSize dimOuter)
                idx' = simplify $ BinOp Add base idxOuter'
        rewriteExpr (orig @ (Range (Bit expr idxInner) NonIndexed rangeOuter)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then rewriteExpr $ Range exprOuter IndexedMinus range
                else rewriteExprLowPrec orig
            where
                maybeDims = dims expr
                exprOuter = Bit expr idxInner
                baseDec = fst rangeOuter
                baseInc = BinOp Sub (BinOp Add baseDec len) (RawNum 1)
                base = endianCondExpr rangeOuter baseDec baseInc
                len = rangeSize rangeOuter
                range = (base, len)
        rewriteExpr (orig @ (Range (Bit expr idxInner) modeOuter rangeOuter)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then Range expr' modeOuter range'
                else rewriteExprLowPrec orig
            where
                maybeDims = dims expr
                Just (dimInner, dimOuter, expr') = maybeDims
                idxInner' = orientIdx dimInner idxInner
                (baseOuter, lenOuter) = rangeOuter
                baseOuter' = orientIdx dimOuter baseOuter
                start = BinOp Mul idxInner' (rangeSize dimOuter)
                baseDec = BinOp Add start baseOuter'
                baseInc = if modeOuter == IndexedPlus
                    then BinOp Add (BinOp Sub baseDec len) one
                    else BinOp Sub (BinOp Add baseDec len) one
                base = endianCondExpr dimOuter baseDec baseInc
                len = lenOuter
                range' = (base, len)
                one = RawNum 1
        rewriteExpr other =
            rewriteExprLowPrec other

        rewriteExprLowPrec :: Expr -> Expr
        rewriteExprLowPrec (orig @ (Bit expr idx)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then Range expr' mode' range'
                else orig
            where
                maybeDims = dims expr
                Just (dimInner, dimOuter, expr') = maybeDims
                mode' = IndexedPlus
                idx' = orientIdx dimInner idx
                len = rangeSize dimOuter
                base = BinOp Add (endianCondExpr dimOuter (snd dimOuter) (fst dimOuter)) (BinOp Mul idx' len)
                range' = (simplify base, simplify len)
        rewriteExprLowPrec (orig @ (Range expr NonIndexed range)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then rewriteExpr $ Range expr IndexedMinus range'
                else orig
            where
                maybeDims = dims expr
                baseDec = fst range
                baseInc = BinOp Sub (BinOp Add baseDec len) (RawNum 1)
                base = endianCondExpr range baseDec baseInc
                len = rangeSize range
                range' = (base, len)
        rewriteExprLowPrec (orig @ (Range expr mode range)) =
            if isJust maybeDims && expr == rewriteExpr expr
                then Range expr' mode' range'
                else orig
            where
                maybeDims = dims expr
                Just (dimInner, dimOuter, expr') = maybeDims
                sizeOuter = rangeSize dimOuter
                offsetOuter = uncurry (endianCondExpr dimOuter) $ swap dimOuter
                (baseOrig, lenOrig) = range
                lenOrigMinusOne = BinOp Sub lenOrig (RawNum 1)
                baseSwapped =
                    orientIdx dimInner $
                    if mode == IndexedPlus
                        then
                            endianCondExpr dimInner
                            baseOrig
                            (BinOp Add baseOrig lenOrigMinusOne)
                        else
                            endianCondExpr dimInner
                            (BinOp Sub baseOrig lenOrigMinusOne)
                            baseOrig
                base = BinOp Add offsetOuter (BinOp Mul sizeOuter baseSwapped)
                mode' = IndexedPlus
                len = BinOp Mul sizeOuter lenOrig
                range' = (base, len)
        rewriteExprLowPrec other = other
