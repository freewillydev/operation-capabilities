-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Optional prelude for dedicated RebindableSyntax workflow modules. Ordinary
-- effects belong in instruction handlers. Use explicit case for refutable binds;
-- this module intentionally supplies no implicit partial-pattern failure policy.
module Control.Operation.Flow.Rebindable (module Prelude, module Flow) where

import Prelude hiding (pure, return, (>>=), (>>), fail)
import Control.Operation.Flow as Flow
