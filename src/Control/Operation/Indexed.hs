{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, KindSignatures, PolyKinds #-}
{-# LANGUAGE RankNTypes, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
module Control.Operation.Indexed
  (IndexedCapability(..), IndexedRequest(..), interpretRequest, interpretIndexed) where

import Control.Operation
import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy(..))
import Type.Reflection (TypeRep, eqTypeRep, (:~~:)(HRefl))

-- An index selects capability classes, not arbitrary extra dictionaries.
class IndexedCapability (index :: k) where
  type IndexCaps index :: [Type -> Constraint]
  type IndexInput index :: Type
  type IndexOutput index :: Type
  runIndexed :: Capabilities (IndexCaps index) op
    => TypeRep index -> op -> IndexInput index -> IndexOutput index

data IndexedRequest declared result where
  IndexedRequest :: (IndexedCapability index, UniqueCapabilities (IndexCaps index),
    Subset (IndexCaps index) declared)
    => TypeRep index -> IndexInput index -> IndexedRequest declared (IndexOutput index)

-- The GADT supplies the selected index's dictionary; the payload supplies only
-- its declared capabilities. Call after the operation's payload Refl.
interpretRequest :: (Operation op caps, Capabilities caps op, Subset caps caps)
  => op -> IndexedRequest caps result -> Maybe result
interpretRequest value (IndexedRequest (actual :: TypeRep selected) input) =
  case pipeline (Restrict (Proxy @(IndexCaps selected))) (prepare value) of
    Left _ -> Nothing
    Right restricted -> Just (withCapabilities (\op -> runIndexed actual op input) restricted)

-- Use when the caller also requires a particular schema/index. A mismatch does
-- not force the input or invoke its capability methods.
interpretIndexed :: forall k (index :: k) op caps.
  (Operation op caps, Capabilities caps op, Subset caps caps)
  => TypeRep index -> op -> IndexedRequest caps (IndexOutput index)
  -> Maybe (IndexOutput index)
interpretIndexed expected value request@(IndexedRequest actual _) =
  case eqTypeRep expected actual of
    Nothing -> Nothing
    Just HRefl -> interpretRequest value request
