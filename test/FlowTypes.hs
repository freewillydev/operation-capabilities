{-# LANGUAGE CPP, DataKinds, GADTs, QualifiedDo #-}
module FlowTypes where

import Control.Operation.Flow (Flow)
import qualified Control.Operation.Flow as F
import FlowExample

valid :: Flow (Action Account) '[Integer] '[] Integer
valid = F.do
  amount <- F.step VerifyAmount
  F.step (SettleAmount (amount `div` 100))

#if defined(WRONG_INPUT)
bad :: Flow (Action Account) '[Bool] '[] Integer
bad = valid
#elif defined(WRONG_SEQUENCE)
bad :: Flow (Action Account) '[Integer] '[] Integer
bad = F.do
  F.step (SettleAmount 1)
  F.step VerifyAmount
#elif defined(WRONG_BRANCH)
bad :: Flow (Action Account) '[Integer] '[] Integer
bad = F.Branch (const True) valid (F.pure 1)
#elif defined(WRONG_RESULT)
bad :: Flow (Action Account) '[Integer] '[] Bool
bad = valid
#elif defined(MISSING_CAPABILITY)
data Unregistered = Unregistered
bad :: Flow (Action Unregistered) '[Integer] '[Verified] Integer
bad = F.step VerifyAmount
#endif
