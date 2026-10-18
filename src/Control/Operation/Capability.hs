{-# LANGUAGE ConstraintKinds, DataKinds, GADTs, PolyKinds, RankNTypes, ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures, TypeApplications, TypeFamilies, TypeOperators, UndecidableInstances #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Curried capability applications. Argument kinds and arity remain explicit
-- until a fully applied constraint supplies its existing dictionary.
module Control.Operation.Capability
  ( Capability(..), Evaluate, CapabilityConstraint, Application(..), withCapability, applicationArity ) where

import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy)
import Data.Type.Equality (type (~~))

-- | A homogeneous list may contain classes with different argument kinds and
-- arities. OnPayload inserts the existential operation at any argument position.
data Capability where
  Class :: k -> Capability
  Apply :: Capability -> argument -> Capability
  OnPayload :: Capability -> Capability

type Evaluate :: forall k. Capability -> Type -> k
type family Evaluate cap op where
  Evaluate ('Class capability) op = capability
  Evaluate @k ('Apply capability (argument :: a)) op = Evaluate @(a -> k) capability op argument
  Evaluate @k ('OnPayload capability) op = Evaluate @(Type -> k) capability op op

-- | Existing unary capability lists remain the short form.
type CapabilityConstraint :: forall k. k -> Type -> Constraint
type family CapabilityConstraint cap op where
  CapabilityConstraint @(Type -> Constraint) cap op = cap op
  CapabilityConstraint @Capability cap op = Evaluate @Constraint cap op

data Application (cap :: k) (constraint :: Constraint) where
  Resolved :: (cap ~~ constraint, constraint) => Application cap constraint
  Argument :: (cap ~~ (function :: argument -> result))
    => Proxy (value :: argument) -> Application (function value) constraint
    -> Application cap constraint

-- | A dictionary must already exist at Resolved. Equality cannot create it.
withCapability :: Application cap constraint -> (constraint => result) -> result
withCapability Resolved use = use
withCapability (Argument _ remaining) use = withCapability remaining use

applicationArity :: Application cap constraint -> Int
applicationArity Resolved = 0
applicationArity (Argument _ remaining) = 1 + applicationArity remaining
