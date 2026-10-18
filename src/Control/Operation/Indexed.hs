{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, KindSignatures, PolyKinds #-}
{-# LANGUAGE RankNTypes, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
{-# LANGUAGE FunctionalDependencies, MultiParamTypeClasses #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
module Control.Operation.Indexed
  (IndexedCapability(..), IndexedRequest(..), IndexMatch(..), matchIndex, discoverRequest,
   interpretRequest, interpretIndexed) where

import Control.Operation
import Data.Kind (Type)
import Data.Proxy (Proxy(..))
import Data.Type.Equality (type (~~))
import Type.Reflection (TypeRep, eqTypeRep, (:~~:)(HRefl))

-- An index selects capability classes, not arbitrary extra dictionaries.
class IndexedCapability (index :: k) (caps :: [capKind]) | index -> caps where
  type IndexInput index :: Type
  type IndexOutput index :: Type
  runIndexed :: Capabilities caps op
    => TypeRep index -> op -> IndexInput index -> IndexOutput index

data IndexedRequest declared result where
  IndexedRequest :: (IndexedCapability index caps, UniqueCapabilities caps,
    Subset caps declared)
    => TypeRep index -> IndexInput index -> IndexedRequest declared (IndexOutput index)

-- The selected index starts with an independent, possibly unknown kind. The
-- registered class generates its capability list; equality transports the class
-- dictionary and subset evidence, but cannot create an unregistered instance.
data IndexMatch declared (registered :: k1) (selected :: k2) where
  IndexMatch :: (registered ~~ selected, IndexedCapability selected caps,
    UniqueCapabilities caps, Subset caps declared)
    => IndexMatch declared registered selected

matchIndex :: forall declared k1 k2 (registered :: k1) (selected :: k2) caps.
  (IndexedCapability registered caps, UniqueCapabilities caps, Subset caps declared)
  => TypeRep registered -> TypeRep selected -> Maybe (IndexMatch declared registered selected)
matchIndex registered selected = case eqTypeRep registered selected of
  Nothing -> Nothing
  Just HRefl -> Just IndexMatch

-- A caller needs no class dictionary for selected. Matching recovers it, then
-- the request can use its generated capabilities through interpretRequest.
discoverRequest :: forall declared k1 k2 (registered :: k1) (selected :: k2) caps.
  (IndexedCapability registered caps, UniqueCapabilities caps, Subset caps declared)
  => TypeRep registered -> TypeRep selected -> IndexInput registered
  -> Maybe (IndexedRequest declared (IndexOutput registered))
discoverRequest registered selected input = case eqTypeRep registered selected of
  Nothing -> Nothing
  Just HRefl -> Just (IndexedRequest selected input)

-- The GADT supplies the selected index's dictionary; the payload supplies only
-- its declared capabilities. Call after the operation's payload Refl.
interpretRequest :: (Operation op caps, Capabilities caps op, Subset caps caps)
  => op -> IndexedRequest caps result -> Maybe result
interpretRequest value (IndexedRequest (actual :: TypeRep selected) input) =
  case pipeline (Restrict (indexCapabilities actual)) (prepare value) of
    Left _ -> Nothing
    Right restricted -> Just (withCapabilities (\op -> runIndexed actual op input) restricted)

indexCapabilities :: IndexedCapability index caps => TypeRep index -> Proxy caps
indexCapabilities _ = Proxy

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
