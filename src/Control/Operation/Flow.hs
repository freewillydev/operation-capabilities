{-# LANGUAGE DataKinds, GADTs, KindSignatures, RankNTypes, TypeOperators #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Deferred, value-dependent programs over heterogeneous state. The instruction
-- GADT supplies capability dictionaries; Flow itself grants no capabilities.
module Control.Operation.Flow
  (Values(..), Flow(..), runFlow, step, pure, return, (>>=), (>>), ifThenElse) where

import Prelude hiding (pure, return, (>>=), (>>))
import qualified Prelude as P
import Data.Kind (Type)

data Values (xs :: [Type]) where
  VNil :: Values '[]
  (:&) :: x -> Values xs -> Values (x ': xs)
infixr 5 :&

-- | 'Bind' builds its continuation only when its preceding program returns.
-- Instructions can refine state indices and return a separate runtime value.
data Flow (instruction :: [Type] -> [Type] -> Type -> Type) xs ys a where
  Pure :: a -> Flow instruction xs xs a
  Step :: instruction xs ys a -> Flow instruction xs ys a
  Bind :: Flow instruction xs ys a -> (a -> Flow instruction ys zs b)
       -> Flow instruction xs zs b
  Branch :: (Values xs -> Bool) -> Flow instruction xs ys a
         -> Flow instruction xs ys a -> Flow instruction xs ys a

step :: instruction xs ys a -> Flow instruction xs ys a
step = Step

pure, return :: a -> Flow instruction xs xs a
pure = Pure
return = Pure

(>>=) :: Flow instruction xs ys a -> (a -> Flow instruction ys zs b)
      -> Flow instruction xs zs b
(>>=) = Bind

(>>) :: Flow instruction xs ys a -> Flow instruction ys zs b -> Flow instruction xs zs b
first >> rest = Bind first (const rest)
infixl 1 >>=, >>

-- | For RebindableSyntax: inspect current runtime state, not construction-time
-- state. Both branches must agree on their output indices and result type.
ifThenElse :: (Values xs -> Bool) -> Flow instruction xs ys a
           -> Flow instruction xs ys a -> Flow instruction xs ys a
ifThenElse = Branch

-- | Interpret only demanded instructions, threading values in order. Failure
-- and effect semantics come from the chosen monad (for example Either or IO).
-- Does not imply rollback, linear resource usage, or stack-safe unbounded binds.
runFlow :: Monad m
        => (forall xs ys a. instruction xs ys a -> Values xs -> m (a, Values ys))
        -> Flow instruction before after result -> Values before
        -> m (result, Values after)
runFlow execute program values = case program of
  Pure result -> P.pure (result, values)
  Step instruction -> execute instruction values
  Bind first next -> runFlow execute first values P.>>= \(result, intermediate) ->
    runFlow execute (next result) intermediate
  Branch choose yes no ->
    runFlow execute (if choose values then yes else no) values
