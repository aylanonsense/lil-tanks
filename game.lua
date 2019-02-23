local Moat = require('lib/moat')

-- Define a unique ID for each type of entity that can exist
local GameEntities = {
  Player = 0
}

-- Define some constants that'll be shared on the server and client
local GameConstants = {}

-- Create a new game
local Game = Moat:new(
  GameEntities,
  GameConstants
)

-- Initialize the game state
function Game:serverInitWorld(state)
end
function Game:clientLoad()
end

-- Update the game state
function Game:worldUpdate(state)
end
function Game:serverUpdate(state)
end
function Game:clientUpdate(state)
end
function Game:playerUpdate(player, input)
end

-- Draw the game
function Game:clientDraw() 
end

-- Spawn new players as clients connect
function Game:serverReceive(clientId, msg)
end
function Game:serverResetPlayer(player)
end

-- Run the game
Game:run()
