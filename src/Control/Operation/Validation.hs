{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, MultiParamTypeClasses, ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances, TypeApplications, TypeFamilies, UndecidableInstances #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | An optional generic interpreter for validation rules. Other domains should
-- define their own classes and Operation instances rather than expand this class.
module Control.Operation.Validation (Validation(..), Check(..), DSL(Validate)) where

import Data.Typeable (Typeable, eqT, (:~:)(Refl))
import Control.Operation

-- | A reusable validation capability with a domain-specific result type.
class Validation rule where
  type ValidationResult rule
  validate :: rule -> ValidationResult rule

-- | Adapt any 'Validation' instance to a capability-constrained operation.
newtype Check rule = Check rule
instance Validation rule => Validation (Check rule) where
  type ValidationResult (Check rule) = ValidationResult rule
  validate (Check rule) = validate rule

-- Operation declares capabilities; the existential supplies their dictionaries.
instance Typeable rule => Operation (Check rule) '[Validation] where
  type Context (Check rule) = Validation rule
  type Outcome (Check rule) = ValidationResult rule
  data DSL (Check rule) where
    Validate :: Context (Check rule) => DSL (Check rule)
  interpret (SomeOperation (value :: actual)) Validate =
    case eqT @actual @(Check rule) of
      Just Refl -> Just (validate value)
      Nothing -> Nothing
