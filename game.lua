-- Load dependencies
local Moat = require('lib/moat')

-- Render constants
local GAME_WIDTH = 200
local GAME_HEIGHT = 200
local RENDER_SCALE = 2

-- Define a unique ID for each type of entity that can exist
local ENTITY_TYPES = {
  Player = 0
}

-- Define some constants that configure the way Moat shares client data
local MOAT_CONFIG = {
  WorldSize = math.max(GAME_WIDTH, GAME_HEIGHT),
  ClientVisibility = math.max(GAME_WIDTH, GAME_HEIGHT)
}

-- Game variables
local hasRequestedSpawn

-- Create a new game using Moat, which allows for networked online play
local Game = Moat:new(ENTITY_TYPES, MOAT_CONFIG)

-- Initializes the game state
function Game:serverInitWorld(state)
end
function Game:clientLoad()
  hasRequestedSpawn = false
end

-- Updates the game state
function Game:worldUpdate(state)
end
function Game:serverUpdate(state)
end
function Game:clientUpdate(state)
  if self:clientIsSpawned() then
    Game:setPlayerInput({
      up = love.keyboard.isDown('up') or love.keyboard.isDown('w'),
      left = love.keyboard.isDown('left') or love.keyboard.isDown('a'),
      down = love.keyboard.isDown('down') or love.keyboard.isDown('s'),
      right = love.keyboard.isDown('right') or love.keyboard.isDown('d')
    })
  end
end
function Game:playerUpdate(player, input)
  if input then 
    player.x = clamp(0, player.x + (input.right and 1 or 0) - (input.left and 1 or 0), GAME_WIDTH - player.width)
    player.y = clamp(0, player.y + (input.down and 1 or 0) - (input.up and 1 or 0), GAME_HEIGHT - player.height)
    Game:moveEntity(player)
  end
end

-- Draws the game
function Game:clientDraw()
  -- Scale up the screen
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)

  -- Clear the screen
  love.graphics.setColor(50 / 255, 0 / 255, 100 / 255)
  love.graphics.rectangle('fill', 0, 0, GAME_WIDTH, GAME_HEIGHT)

  -- Draw all players
  self:eachEntityOfType(ENTITY_TYPES.Player, function(player)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle('fill', player.x, player.y, player.width, player.height)
  end)
end

-- Press a button to request a spawn
function Game:clientKeyPressed(key)
  -- Ask the server for permission to spawn
  if self:clientIsConnected() and not self:clientIsSpawned() and not hasRequestedSpawn then
    self:clientSend({ cmd = 'request_spawn' })
    hasRequestedSpawn = true
  end
end
-- The server responds by spawning the player
function Game:serverReceive(clientId, msg)
  if msg.cmd == 'request_spawn' then
    self:spawnPlayer(clientId)
  end
end
function Game:serverResetPlayer(player)
  player.x = math.random(20, GAME_WIDTH - 20)
  player.y = math.random(20, GAME_WIDTH - 20)
  player.width = 10
  player.height = 10
end

-- Keeps a number between the given minimum and maximum values
function clamp(minimum, num, maximum)
  return math.min(math.max(minimum, num), maximum)
end

-- Run the game
Game:run()
