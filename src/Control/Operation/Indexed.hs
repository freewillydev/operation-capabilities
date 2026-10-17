{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, KindSignatures, PolyKinds #-}
{-# LANGUAGE RankNTypes, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
module Control.Operation.Indexed
  (IndexedCapability(..), IndexedRequest(..), IndexMatch(..), withMatchingIndex, matchIndex, discoverRequest,
   interpretRequest, interpretIndexed) where

import Control.Operation
import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy(..))
import Data.Type.Equality (type (~~))
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

-- The selected index starts with an independent, possibly unknown kind. The
-- registered class generates its capability list; equality transports the class
-- dictionary and subset evidence, but cannot create an unregistered instance.
data IndexMatch declared (registered :: k1) (selected :: k2) where
  IndexMatch :: (registered ~~ selected, IndexedCapability selected,
    UniqueCapabilities (IndexCaps selected), Subset (IndexCaps selected) declared)
    => IndexMatch declared registered selected

-- Recover type and kind equality before evaluating the continuation. Equality
-- transports dictionaries already in scope; it cannot manufacture any.
withMatchingIndex :: TypeRep (actual :: k1) -> TypeRep (selected :: k2)
  -> ((actual ~~ selected) => result) -> Maybe result
withMatchingIndex actual selected use = case eqTypeRep actual selected of
  Nothing -> Nothing
  Just HRefl -> Just use

matchIndex :: forall declared k1 k2 (registered :: k1) (selected :: k2).
  (IndexedCapability registered, UniqueCapabilities (IndexCaps registered),
   Subset (IndexCaps registered) declared)
  => TypeRep registered -> TypeRep selected -> Maybe (IndexMatch declared registered selected)
matchIndex registered selected = withMatchingIndex registered selected IndexMatch

-- A caller needs no class dictionary for selected. Matching recovers it, then
-- the request can use its generated capabilities through interpretRequest.
discoverRequest :: forall declared k1 k2 (registered :: k1) (selected :: k2).
  (IndexedCapability registered, UniqueCapabilities (IndexCaps registered),
   Subset (IndexCaps registered) declared)
  => TypeRep registered -> TypeRep selected -> IndexInput registered
  -> Maybe (IndexedRequest declared (IndexOutput registered))
discoverRequest registered selected input = do
  IndexMatch <- matchIndex @declared registered selected
  pure (IndexedRequest selected input)

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
