{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module Planning where

import Control.Operation

class FeeModel op where
  estimateFee :: op -> Integer
class SpendPolicy op where
  availableFunds :: op -> Integer
  paymentAmount :: op -> Integer
  buildUnsigned :: op -> Integer -> Either String UnsignedTx

-- Illustrative planning data only, not a transaction codec or wallet.
data UnsignedTx = UnsignedTx Integer Integer deriving (Eq, Show)
data Payment = Payment Integer Integer Integer
instance FeeModel Payment where
  estimateFee (Payment _ _ fee) = fee
instance SpendPolicy Payment where
  availableFunds (Payment funds _ _) = funds
  paymentAmount (Payment _ amount _) = amount
  buildUnsigned payment fee = Right (UnsignedTx (paymentAmount payment) fee)

planPayment :: (FeeModel op, SpendPolicy op) => op -> Either String UnsignedTx
planPayment value
  | amount <= 0 = Left "Payment must be positive"
  | fee < 0 = Left "Invalid fee estimate"
  | amount + fee > availableFunds value = Left "Insufficient funds"
  | otherwise = buildUnsigned value fee
  where
    amount = paymentAmount value
    fee = estimateFee value

instance Operation Payment '[FeeModel, SpendPolicy] where
  type Context Payment = (FeeModel Payment, SpendPolicy Payment)
  type Outcome Payment = Either String UnsignedTx
  data DSL Payment where
    PlanPayment :: Context Payment => DSL Payment
  interpret operation PlanPayment = withOperation @Payment operation (Just . planPayment)
