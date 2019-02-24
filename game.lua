-- Load dependencies
local Moat = require('lib/moat')

-- Render constants
local GAME_WIDTH = 200
local GAME_HEIGHT = 200
local RENDER_SCALE = 3

-- Define a unique ID for each type of entity that can exist
local ENTITY_TYPES = {
  Player = 0,
  Bullet = 1
}

-- Define some constants that configure the way Moat shares client data
local MOAT_CONFIG = {
  TickInterval = 1.0 / 60.0,
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
function Game:serverUpdate(state)
end
function Game:clientUpdate(state)
  if self:clientIsSpawned() then
    local player = self:getPlayerState()
    local aimX = love.mouse.getX() / RENDER_SCALE
    local aimY = love.mouse.getY() / RENDER_SCALE
    local aimAngle = math.atan2(aimY - player.y - player.w / 2, aimX - player.x - player.h / 2)
    self:setPlayerInput({
      up = love.keyboard.isDown('up') or love.keyboard.isDown('w'),
      left = love.keyboard.isDown('left') or love.keyboard.isDown('a'),
      down = love.keyboard.isDown('down') or love.keyboard.isDown('s'),
      right = love.keyboard.isDown('right') or love.keyboard.isDown('d'),
      shoot = love.mouse.isDown(1),
      aimAngle = aimAngle
    })
  end
end
function Game:playerUpdate(player, input)
  if input then
    player.vx = 32 * ((input.right and 1 or 0) - (input.left and 1 or 0))
    player.vy = 32 * ((input.down and 1 or 0) - (input.up and 1 or 0))
    player.x = clamp(0, player.x + player.vx * MOAT_CONFIG.TickInterval, GAME_WIDTH - player.w)
    player.y = clamp(0, player.y + player.vy * MOAT_CONFIG.TickInterval, GAME_HEIGHT - player.h)
    self:moveEntity(player)
    player.shootCooldown = math.max(0.00, player.shootCooldown - MOAT_CONFIG.TickInterval)
    if input.shoot and input.aimAngle and player.shootCooldown <= 0.00 then
      player.shootCooldown = 1.00
      self:spawn(ENTITY_TYPES.Bullet, player.x + player.w / 2 - 3, player.y + player.h / 2 - 3, 6, 6, {
        vx = 64 * math.cos(input.aimAngle),
        vy = 64 * math.sin(input.aimAngle),
        ownerClientId = player.clientId
      })
    end
  end
end
function Game:worldUpdate(state)
  -- Move bullets and check for hits
  self:eachEntityOfType(ENTITY_TYPES.Bullet, function(bullet)
    bullet.x = bullet.x + bullet.vx * MOAT_CONFIG.TickInterval
    bullet.y = bullet.y + bullet.vy * MOAT_CONFIG.TickInterval
    self:moveEntity(bullet)

    -- Check for bullet hits
    self:eachOverlapping(bullet, function(entity)
      -- Bullets push players back a bit
      if entity.type == ENTITY_TYPES.Player and entity.clientId ~= bullet.ownerClientId then
        entity.x = entity.x + 6 * bullet.vx * MOAT_CONFIG.TickInterval
        entity.y = entity.y + 6 * bullet.vy * MOAT_CONFIG.TickInterval
        self:moveEntity(entity)
        self:despawn(bullet)
      -- Bullets cancel each other out
      elseif entity.type == ENTITY_TYPES.Bullet and entity.ownerClientId ~= bullet.ownerClientId then
        self:despawn(entity)
        self:despawn(bullet)
      end
    end)

    -- Despawn bullets that go off screen
    if bullet.x > GAME_WIDTH or bullet.y > GAME_HEIGHT or bullet.x < -bullet.w or bullet.y < -bullet.h then
      self:despawn(bullet)
    end
  end)
end

-- Draws the game
function Game:clientDraw()
  -- Scale up the screen
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)

  -- Clear the screen
  love.graphics.setColor(50 / 255, 0 / 255, 100 / 255)
  love.graphics.rectangle('fill', 0, 0, GAME_WIDTH, GAME_HEIGHT)

  -- Draw all the bullets
  self:eachEntityOfType(ENTITY_TYPES.Bullet, function(bullet)
    love.graphics.setColor(1, 0, 0)
    love.graphics.rectangle('fill', bullet.x, bullet.y, bullet.w, bullet.h)
  end)

  -- Draw all players
  self:eachEntityOfType(ENTITY_TYPES.Player, function(player)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle('fill', player.x, player.y, player.w, player.h)
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
-- The player spawns at a random location
function Game:serverResetPlayer(player)
  player.x = math.random(20, GAME_WIDTH - 20)
  player.y = math.random(20, GAME_WIDTH - 20)
  player.w = 16
  player.h = 16
  player.vx = 0
  player.vy = 0
  player.shootCooldown = 0.00
end

-- Keeps a number between the given minimum and maximum values
function clamp(minimum, num, maximum)
  return math.min(math.max(minimum, num), maximum)
end

-- Run the game
Game:run()
