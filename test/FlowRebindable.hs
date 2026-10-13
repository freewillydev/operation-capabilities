{-# LANGUAGE DataKinds, GADTs, RebindableSyntax, TypeOperators #-}
module FlowRebindable (payment) where

import Control.Operation.Flow.Rebindable
import FlowExample (Account, Action(..), Verified(..))

payment :: Flow (Action Account) '[Integer] '[] Integer
payment = do
  amount <- step VerifyAmount
  let high :: Values '[Verified] -> Bool
      high (Verified n :& VNil) = n > 100
  if high
    then step (SettleAmount (amount `div` 100))
    else step (SettleAmount 1)
