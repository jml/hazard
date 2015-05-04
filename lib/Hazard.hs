-- Copyright (c) 2015 Jonathan M. Lange <jml@mumak.net>
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}

module Hazard ( hazardWeb
              ) where


import Control.Monad (mzero)

import Data.Aeson (FromJSON(..), ToJSON(..), (.=), Value(Object), object, (.:))
import Network.HTTP.Types.Status
import Web.Scotty

import Hazard.Model (GameCreationRequest(..))


instance ToJSON GameCreationRequest where
  toJSON (GameCreationRequest { .. }) = object [ "numPlayers" .= reqNumPlayers
                                               , "turnTimeout" .= reqTurnTimeout
                                               ]

instance FromJSON GameCreationRequest where
  parseJSON (Object v) = GameCreationRequest <$> v .: "numPlayers" <*> v .: "turnTimeout"
  parseJSON _ = mzero



hazardWeb :: ScottyM ()
hazardWeb = do
  get "/" $ do
    html "Hello World!"
  get "/games" $ do
    json ([] :: [Int])
  post "/games" $ do
    _ <- (jsonData :: ActionM GameCreationRequest)
    status created201
    setHeader "Location" "/game/0"
    raw ""
