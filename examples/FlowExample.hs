{-# LANGUAGE DataKinds, FlexibleInstances, GADTs, MultiParamTypeClasses #-}
{-# LANGUAGE QualifiedDo, ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
module FlowExample where

import Control.Operation
import Control.Operation.Flow (Flow, Values(..))
import qualified Control.Operation.Flow as F
import Data.Typeable (eqT, (:~:)(Refl))

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

payment :: Flow (Action Account) '[Integer] '[] Integer
payment = F.do
  amount <- F.step VerifyAmount
  let fee = if amount > 100 then 2 else 1
  paid <- F.step (SettleAmount fee)
  F.pure paid

instance Operation Account '[Verify, Settle] where
  type Context Account = Verify Account
  type Outcome Account = Either String Integer
  data DSL Account where
    RunPayment :: Values xs -> Flow (Action Account) xs '[] Integer -> DSL Account
  interpret (SomeOperation (value :: actual)) request =
    case eqT @actual @Account of
      Nothing -> Nothing
      Just Refl -> case request of
        RunPayment values program -> Just (fst <$> F.runFlow (runAction value) program values)
