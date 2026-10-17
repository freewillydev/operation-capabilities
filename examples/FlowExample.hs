{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs, MultiParamTypeClasses #-}
{-# LANGUAGE QualifiedDo, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
module FlowExample where

import Control.Operation
import Control.Operation.Flow (Flow, Values(..))
import qualified Control.Operation.Flow as F

newtype Account = Account Integer
newtype Verified = Verified Integer deriving (Eq, Show)
class Verify op where
  verify :: op -> Integer -> Either String Verified
class Settle op where
  settle :: op -> Verified -> Integer -> Either String Integer
instance Verify Account where
  verify (Account limit) amount
    | amount < 0 || amount > limit = Left "invalid amount"
    | otherwise = Right (Verified amount)
instance Settle Account where
  settle _ (Verified amount) fee
    | fee < 0 = Left "invalid fee"
    | otherwise = Right (amount-fee)

data Action op xs ys a where
  VerifyAmount :: Verify op => Action op '[Integer] '[Verified] Integer
  SettleAmount :: Settle op => Integer -> Action op '[Verified] '[] Integer

-- Capabilities are supplied by the action match after payload equality.
runAction :: op -> Action op xs ys a -> Values xs -> Either String (a, Values ys)
runAction op action values = case action of
  VerifyAmount -> case values of
    amount :& VNil -> verify op amount >>= \verified -> Right (amount, verified :& VNil)
  SettleAmount fee -> case values of
    verified :& VNil -> settle op verified fee >>= \paid -> Right (paid, VNil)

instance Operation Account '[Verify, Settle] where
  type Context Account = (Verify Account, Settle Account)
  type Outcome Account = Flow (Action Account) '[Integer] '[] Integer
  data DSL Account where
    PlanPayment :: Context Account => DSL Account
  interpret operation request = withOperation @Account operation $ \_ -> case request of
    PlanPayment -> Just $ F.do
      amount <- F.step VerifyAmount
      let fee = if amount > 100 then 2 else 1
      F.step (SettleAmount fee)

-- Compilation is pure; the application chooses when and how to evaluate it.
payment :: Account -> Maybe (Flow (Action Account) '[Integer] '[] Integer)
payment value = interpret (SomeOperation value) PlanPayment

runPayment :: Account -> Values xs -> Flow (Action Account) xs '[] Integer -> Either String Integer
runPayment value values program = fst <$> F.runFlow (runAction value) program values
