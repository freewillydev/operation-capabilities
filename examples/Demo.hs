{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module Demo where

import Control.Operation
import Data.Char (toUpper)
import Data.Proxy (Proxy(..))
import Data.Typeable (eqT, (:~:)(Refl))

class Labelled op where
  label :: op -> String
class Editable op where
  edit :: (String -> String) -> op -> op
class Renderable op where
  render :: op -> String

newtype Note = Note String
instance Labelled Note where
  label _ = "note"
instance Editable Note where
  edit f (Note text) = Note (f text)
instance Renderable Note where
  render (Note text) = text

type NoteCaps = '[Labelled, Editable, Renderable]

instance Operation Note NoteCaps where
  type Context Note = Renderable Note
  type Outcome Note = String
  data DSL Note where
    Rendering :: Context Note => DSL Note
  interpret (SomeOperation (value :: actual)) Rendering =
    case eqT @actual @Note of
      Just Refl -> Just (render value)
      Nothing -> Nothing

clean :: Stage String '[Labelled, Editable]
clean = Stage $ \value ->
  if label value == "note" then Right (edit (unwords . words) value)
  else Left "expected a note"

notePipeline :: Pipeline String (SomeOperationWith NoteCaps NoteCaps) (SomeOperationWith NoteCaps '[Renderable])
notePipeline =
  Restrict (Proxy @'[Labelled, Editable]) :>>>
  Preserve clean :>>>
  Preserve (Stage (Right . edit (map toUpper))) :>>>
  Expand (Proxy @NoteCaps) :>>>
  Restrict (Proxy @'[Renderable])

renderNote :: String -> Either String (Maybe String)
renderNote text = do
  pending <- pipeline notePipeline (prepare (Note text))
  pure (interpret (forgetCapabilities pending) Rendering)
