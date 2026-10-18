{-# LANGUAGE CPP, ConstraintKinds, DataKinds, FlexibleContexts, GADTs, TypeApplications #-}
module CapabilityApplications where

import Control.Operation
import Control.Operation.Capability
import qualified CapableOutputs as C
import Data.Proxy (Proxy(..))

valid :: String
valid = withCapability (C.quoteApplication @C.Balance) $
  C.quote (Proxy @"BTC") (Proxy @24) (C.Balance 50)

restricted :: Either String (SomeOperationWith C.BalanceCaps '[C.Quotation])
restricted = pipeline (Restrict (Proxy @'[C.Quotation])) (prepare (C.Balance 50))

#ifdef WRONG_KIND
bad :: Application Show (Show Int)
bad = Argument (Proxy @24) Resolved
#endif
#ifdef WRONG_RESULT
bad :: Application Show (Eq Int)
bad = Argument (Proxy @Int) Resolved
#endif
#ifdef INCOMPLETE
bad :: Application Show (Show Int)
bad = Resolved
#endif
#ifdef FORGED_DICTIONARY
data Missing
bad :: Application Show (Show Missing)
bad = Argument (Proxy @Missing) Resolved
#endif
#ifdef HIDDEN_METHOD
bad :: SomeOperationWith C.BalanceCaps '[C.TextDescription] -> String
bad = withCapabilities (C.quote (Proxy @"BTC") (Proxy @24))
#endif
#ifdef UNDECLARED
bad :: Either String (SomeOperationWith C.BalanceCaps '[ 'OnPayload ('Class Show)])
bad = pipeline (Restrict (Proxy @'[ 'OnPayload ('Class Show)])) (prepare (C.Balance 50))
#endif
#ifdef DUPLICATE
unique :: UniqueCapabilities caps => Proxy caps -> ()
unique _ = ()
bad :: ()
bad = unique (Proxy @'[C.Quotation, C.Quotation])
#endif
