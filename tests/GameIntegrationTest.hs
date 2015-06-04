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

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module GameIntegrationTest (suite) where

import BasicPrelude

import Data.Aeson hiding (json)
import Data.Aeson.Types (parseMaybe)
import Data.Foldable (for_)
import Data.IORef
import Data.Maybe (fromJust)

import Network.Wai.Test (SResponse(..), assertStatus, assertContentType)
import Test.Hspec.Wai hiding (get, post)
import Test.Hspec.Wai.Internal (WaiSession(WaiSession))
import Test.Hspec.Wai.JSON
import Test.Tasty
import Test.Tasty.Hspec

import Haverer.Deck (Card(..), Complete, Deck)

import qualified Hazard.Routes as Route
import Web.Spock.Safe (renderRoute)

import Utils (get, getAs, hazardTestApp', post, postAs, requiresAuth, makeTestDeck)


testDeck :: Deck Complete
testDeck = makeTestDeck "sscmwwskkpcsgspx"



spec :: IORef (Deck Complete) -> Spec
spec deckVar = with (hazardTestApp' deckVar) $ do
  describe "GET /" $
    it "responds with 200" $
      get "/" `shouldRespondWith` 200

  describe "/games" $ do
    it "GET returns empty list when there are no games" $
      get "/games" `shouldRespondWith` [json|[]|]

    it "POST creates game" $ do
      post "/users" [json|{username: "foo"}|]
      postAs "foo" "/games" [json|{numPlayers: 3, turnTimeout: 3600}|] `shouldRespondWith`
        [json|{"creator": "0", "state": "pending", "players": {"0":null}, "turnTimeout": 3600,
              "numPlayers": 3}|]
        {matchStatus = 201, matchHeaders = ["Location" <:> "/game/0"] }

    it "POST twice creates 2 game" $ do
      post "/users" [json|{username: "foo"}|]
      postAs "foo" "/games" [json|{numPlayers: 3, turnTimeout: 3600}|] `shouldRespondWith`
        [json|{"creator": "0", "state": "pending", "players": {"0": null}, "turnTimeout": 3600,
              "numPlayers": 3}|]
        {matchStatus = 201, matchHeaders = ["Location" <:> "/game/0"] }
      postAs "foo" "/games" [json|{numPlayers: 2, turnTimeout: 3600}|] `shouldRespondWith`
        [json|{"creator": "0", "state": "pending", "players": {"0":null}, "turnTimeout": 3600,
              "numPlayers": 2}|] {matchStatus = 201, matchHeaders = ["Location" <:> "/game/1"] }

    it "URLs from POSTs align properly" $ do
      -- Post a 2 player game and 3 player game, and make sure that when we
      -- GET the URLs that number of players is as we requested.
      post "/users" [json|{username: "foo"}|]
      postAs "foo" "/games" [json|{numPlayers: 3, turnTimeout: 3600}|]
      postAs "foo" "/games" [json|{numPlayers: 2, turnTimeout: 3600}|]
      game0 <- get "/game/0"
      jsonResponseIs game0 (getKey "numPlayers") (Just 3 :: Maybe Int)
      game1 <- get "/game/1"
      jsonResponseIs game1 (getKey "numPlayers") (Just 2 :: Maybe Int)

    it "unauthenticated POST fails" $
      post "/games" [json|{numPlayers: 3, turnTimeout: 3600}|] `shouldRespondWith` requiresAuth

    it "Created game appears in list" $ do
      post "/users" [json|{username: "foo"}|]
      postAs "foo" "/games" [json|{numPlayers: 3, turnTimeout: 3600}|]
      get "/games" `shouldRespondWith` [json|["/game/0"]|]

  describe "/game/N" $ do
    it "GET returns 404 if it hasn't been created" $
      get "/game/0" `shouldRespondWith` 404

    it "POST returns 404 if it hasn't been created" $ do
      post "/users" [json|{username: "foo"}|]
      postAs "foo" "/game/0" [json|null|] `shouldRespondWith` 404

    it "Created game has POST data" $ do
      game <- makeGameAs "foo" 3
      get game `shouldRespondWith` [json|{numPlayers: 3, turnTimeout: 3600, creator: "0",
                                          state: "pending", players: {"0":null}}|] {matchStatus = 200}

    it "POST without authorization fails" $ do
      game <- makeGameAs "foo" 3
      post game [json|null|] `shouldRespondWith` requiresAuth

    it "Can be re-joined by same player" $ do
      game <- makeGameAs "foo" 3
      postAs "foo" game [json|null|] `shouldRespondWith`
        [json|{numPlayers: 3, turnTimeout: 3600, creator: "0",
               state: "pending", players: {"0": null}}|] {matchStatus = 200}

    it "POST joins game" $ do
      game <- makeGameAs "foo" 3
      post "/users" [json|{username: "bar"}|]
      postAs "bar" game [json|null|] `shouldRespondWith`
        [json|{numPlayers: 3, turnTimeout: 3600, creator: "0",
               state: "pending", players: {"1": null, "0": null}}|] {matchStatus = 200}

    it "POSTing to started game returns bad request" $ do
      game <- makeGameAs "foo" 2
      post "/users" [json|{username: "bar"}|]
      postAs "bar" game [json|null|]
      post "/users" [json|{username: "qux"}|]
      postAs "bar" game [json|null|] `shouldRespondWith`
        [json|{message: "Game already started"}|] {matchStatus = 400}

    it "Game starts when enough people have joined" $ do
      game <- makeGameAs "foo" 2
      post "/users" [json|{username: "bar"}|]
      postAs "bar" game [json|null|] `shouldRespondWith`
        [json|{numPlayers: 2,
               turnTimeout: 3600,
               creator: "0",
               state: "in-progress",
               players: {"1": 0, "0": 0}
              }|] {matchStatus = 200}

    it "Same data on GET after POST" $ do
      game <- makeGameAs "foo" 2
      post "/users" [json|{username: "bar"}|]
      postAs "bar" game [json|null|]
      get game `shouldRespondWith`
        [json|{numPlayers: 2,
               turnTimeout: 3600,
               creator: "0",
               state: "in-progress",
               players: {"1": 0, "0": 0}
               }|] {matchStatus = 200}


  describe "Playing a game" $ do
    it "Rounds don't exist for unstarted game (GET)" $ do
      game <- makeGameAs "foo" 2
      get (game ++ "/round/0") `shouldRespondWith` 404

    it "Rounds don't exist for unstarted game (POST)" $ do
      game <- makeGameAs "foo" 2
      postAs "foo" (game ++ "/round/0") [json|{card: "priestess"}|] `shouldRespondWith` 404

    it "started game is started" $ do
      (game, _) <- makeStartedGame 3
      get game `shouldRespondWith` [json|{
                                       numPlayers: 3,
                                       turnTimeout: 3600,
                                       creator: "0",
                                       state: "in-progress",
                                       players: {"2": 0,"1": 0,"0": 0}
                                       }|] {matchStatus = 200}

    it "Rounds do exist for started games" $ do
      -- TODO: Have a makeStartedGame helper that returns a Map of player IDs
      -- to usernames as well as the ID of the current player
      let deck = makeTestDeck "sscmwwskkpcsgspx"
      (game, [foo, bar, baz]) <- makeStartedGame' 3 deck
      get (game ++ "/round/0") `hasJsonResponse`
        object [
          "players" .= [
             object [
                "id" .= ("0" :: Text),
                "active" .= True,
                "protected" .= False,
                "discards" .= ([] :: [Card])
                ],
             object [
               "id" .= ("1" :: Text),
               "active" .= True,
               "protected" .= False,
               "discards" .= ([] :: [Card])
               ],
             object [
               "id" .= ("2" :: Text),
               "active" .= True,
               "protected" .= False,
               "discards" .= ([] :: [Card])
               ]
             ],
          -- TODO: Randomize the first player (and the player order).
          -- Currently it's always the *first* person who signed up (i.e. the
          -- creator) followed by other players in signup order.
          "currentPlayer" .= ("0" :: Text)
          ]

    it "Shows your hand when you GET" $ do
      (game, [_, bar, _]) <- makeStartedGame 3
      response <- getAs (encodeUtf8 bar) (game ++ "/round/0")
      jsonResponseIs response (isJust . (getPlayer 1 >=> getCard "hand")) True

    it "Doesn't show other hands when you GET" $ do
      (game, [_, bar, _]) <- makeStartedGame 3
      response <- getAs (encodeUtf8 bar) (game ++ "/round/0")
      jsonResponseIs response (getPlayer 0 >=> getKey "hand") (Nothing :: Maybe Card)
      jsonResponseIs response (getPlayer 2 >=> getKey "hand") (Nothing :: Maybe Card)

    it "Doesn't include dealt card when it's not your turn" $ do
      (game, [_, bar, _]) <- makeStartedGame 3
      response <- getAs (encodeUtf8 bar) (game ++ "/round/0")
      jsonResponseIs response (getKey "dealtCard") (Nothing :: Maybe Card)

    it "Does include dealt card when it is your turn" $ do
      (game, [foo, _, _]) <- makeStartedGame 3
      response <- getAs (encodeUtf8 foo) (game ++ "/round/0")
      jsonResponseIs response (isJust . getCard "dealtCard") True

    it "POST without authorization fails" $ do
      (game, _) <- makeStartedGame 3
      post (game ++ "/round/0") [json|null|] `shouldRespondWith` requiresAuth

    it "POST when it's not your turn returns error" $ do
      (game, [_, bar, _]) <- makeStartedGame 3
      postAs (encodeUtf8 bar) (game ++ "/round/0") [json|{card: "priestess"}|]
        `shouldRespondWith` [json|{message: "Not your turn",
                                   currentPlayer: "0"}|] { matchStatus = 400 }

    it "POST when you aren't in the game returns error" $ do
      (game, _) <- makeStartedGame 3
      post "/users" [json|{username: "qux"}|]
      postAs "qux" (game ++ "/round/0") [json|{card: "priestess"}|]
        `shouldRespondWith` [json|{message: "You are not playing"}|] { matchStatus = 400 }

    it "POST does *something*" $ do
      let deck = makeTestDeck "sscmwwskkpcsgspx"
      (game, [foo, _, _]) <- makeStartedGame' 3 deck
      -- Hands are Soldier, Clown, Minister. Player is dealt Wizard.

      -- Play Wizard on self.
      let roundUrl = game ++ "/round/0"
          user = encodeUtf8 foo
      postAs user roundUrl [json|{card: "wizard", target: "2"}|]
        `shouldRespondWith` [json|{id: "0", result: "forced-discard", card: "Wizard", target: "2"}|]

    it "ending round reports winner correctly" $ do
      -- XXX: Deals cards, then burns, then draws. Really should be burn, deal draw.
      -- XXX: Players are 0, 1. Player 0 "goes" first, and is dealt the first
      -- card from the deck.
      (game, [foo, _]) <- makeStartedGame' 2 easyToTerminateDeck
      let roundUrl = game ++ "/round/0"
          user = encodeUtf8 foo
      postAs user roundUrl terminatingPlay
        `shouldRespondWith`
        [json|{id: "0", result: "eliminated", card: "Soldier", guess: "Knight", target: "1", eliminated: "1"}|]
        { matchStatus = 200 }
      -- TODO: Include burn card in serialization of finished round.
      -- TODO: Include survivors in serialization of finished round.

      -- XXX: Maybe the testing strategy here should be to test various
      -- serializations of Round, and use the Haverer testing library to
      -- generate rounds in the states we find interesting?
      getAs user roundUrl `shouldRespondWith`
        [json|
         {currentPlayer: null,
          winners: ["0"],
          players: [
            {protected:false,
             active:true,
             id:"0",
             hand:"Minister",
             discards:["Soldier"]
            },
            {protected:null,
             active:false,
             id:"1",
             discards:["Knight"]
            }
            ]}|] { matchStatus = 200 }

    it "cannot POST to round after round is over" $ do
      (game, [foo, _]) <- makeStartedGame' 2 easyToTerminateDeck
      let roundUrl = game ++ "/round/0"
          user = encodeUtf8 foo
      postAs user roundUrl terminatingPlay
      postAs user roundUrl terminatingPlay
        `shouldRespondWith`
        [json|{message: "Round not active"}|] { matchStatus = 400 }

    it "updates game when round is over" $ do
      (game, [foo, _]) <- makeStartedGame' 2 easyToTerminateDeck
      let roundUrl = game ++ "/round/0"
          user = encodeUtf8 foo
      postAs user roundUrl terminatingPlay
      get game
      `shouldRespondWith`
        [json|{"creator":"0","state":"in-progress","players":{"1":0,"0":1},"turnTimeout":3600,"numPlayers":2}|]
        { matchStatus = 200 }

    it "creates new round after previous is over" $ do
      (game, [foo, _]) <- makeStartedGame' 2 easyToTerminateDeck
      let roundUrl = game ++ "/round/0"
          user = encodeUtf8 foo
      postAs user roundUrl terminatingPlay
      let roundUrl2 = game ++ "/round/1"
      get roundUrl2
        `shouldRespondWith`
        [json|{"currentPlayer": "0",
               "players": [
                 {"protected": false,
                  "active": true,
                  "id": "0",
                  "discards": []
                 },
                 {"protected": false,
                  "active": true,
                  "id": "1",
                  "discards": []
                 }
                 ]
              }|]
        { matchStatus = 200 }

    it "ends game when final score reached" $ do
      (game, [foo, _]) <- makeStartedGame' 2 easyToTerminateDeck
      let user = encodeUtf8 foo
          roundUrl i = encodeUtf8 $ renderRoute Route.round 0 i
      postAs user (roundUrl 0) terminatingPlay
      postAs user (roundUrl 1) terminatingPlay
      postAs user (roundUrl 2) terminatingPlay
      postAs user (roundUrl 3) terminatingPlay
      get game
      `shouldRespondWith`
        [json|{"creator":"0","state":"finished","players":{"1": 0,"0": 4},"turnTimeout":3600,"numPlayers":2}|]
        { matchStatus = 200 }

      -- TODO: Test that there's interesting history available at round/0
      -- TODO: Test that we can't POST anything to finished games


  where
    makeGameAs :: Text -> Int -> WaiSession ByteString
    makeGameAs user numPlayers = do
      post "/users" (encode $ object ["username" .= (user :: Text)])
      response <- postAs (encodeUtf8 user) "/games" (encode $
                                                     object ["turnTimeout" .= (3600 :: Int)
                                                            ,"numPlayers" .= numPlayers])
      case lookup "Location" (simpleHeaders response) of
       Just path -> return path
       Nothing -> error "Did not create game: could not find return header"


    makeStartedGame :: Int -> WaiSession (ByteString, [Text])
    makeStartedGame n = makeStartedGame' n testDeck

    makeStartedGame' :: Int -> Deck Complete -> WaiSession (ByteString, [Text])
    makeStartedGame' n deck =
      let userPool = ["foo", "bar", "baz", "qux"]
          users = take n userPool
          creator:others = users
      in do
        liftIO $ writeIORef deckVar deck
        game <- makeGameAs creator n
        for_ others (\u -> do post "/users" (encode $ object ["username" .= u])
                              postAs (encodeUtf8 u) game [json|null|] `shouldRespondWith` 200)
        return (game, users)

    getPlayer i v = getKey "players" v >>= \ps -> ps !! i


    getKey :: FromJSON a => Text -> Value -> Maybe a
    getKey key = parseMaybe (withObject "expected object" (.: key))

    getCard :: Text -> Value -> Maybe Card
    getCard = getKey

    easyToTerminateDeck :: Deck Complete
    easyToTerminateDeck = makeTestDeck "skcmwwskspcsgspx"

    terminatingPlay = encode $ object [ "card" .= ("soldier" :: Text),
                                        "target" .= ("1" :: Text),
                                        "guess" .= ("knight" :: Text) ]

    getJsonResponse :: FromJSON a => SResponse -> WaiSession a
    getJsonResponse response = do
      WaiSession $ assertStatus 200 response
      WaiSession $ assertContentType jsonContentType response
      return . fromJust . decode . simpleBody $ response
      where jsonContentType = "application/json; charset=utf-8"

    jsonResponseIs :: (FromJSON a, Eq b, Show a, Show b) => SResponse -> (a -> b) -> b -> WaiSession ()
    jsonResponseIs response f value = do
      decoded <- getJsonResponse response
      liftIO $ decoded `shouldSatisfy` ((==) value . f)

    hasJsonResponse :: (Eq a, Show a, FromJSON a, ToJSON a) => WaiSession SResponse -> a -> WaiSession ()
    hasJsonResponse response x = do
      response' <- getJsonResponse =<< response
      liftIO $ response' `shouldBe` x


suite :: IO TestTree
suite = do
  deckVar <- newIORef testDeck
  testSpec "Game API" (spec deckVar)
