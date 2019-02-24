-- Load dependencies
local Moat = require('lib/moat')

-- Render constants
local GAME_WIDTH = 200
local GAME_HEIGHT = 200
local RENDER_SCALE = 3

-- Define a unique ID for each type of entity
local ENTITY_TYPES = {
  Player = 0,
  Bullet = 1,
  Ball = 2
}

-- Define some constants that configure the way Moat works
local MOAT_CONFIG = {
  TickInterval = 1.0 / 60.0,
  WorldSize = math.max(GAME_WIDTH, GAME_HEIGHT),
  ClientVisibility = math.max(GAME_WIDTH, GAME_HEIGHT)
}

-- Game variables
local hasRequestedSpawn
local spriteSheet
local quads
local sounds

-- Create a new game using Moat, which allows for networked online play
local Game = Moat:new(ENTITY_TYPES, MOAT_CONFIG)

-- Initializes the game state
function Game:serverInitWorld(state)
  -- Spawn a ball
  self:spawn(ENTITY_TYPES.Ball, GAME_WIDTH / 2 - 5, GAME_HEIGHT / 2 - 5, 10, 10, {
    vx = 0,
    vy = 0
  })
end
function Game:clientLoad()
  -- Load images
  spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
  spriteSheet:setFilter('nearest', 'nearest')
  -- Calculate the quads within the sprite sheet
  local width, height = spriteSheet:getDimensions()
  quads = {
    ball = love.graphics.newQuad(22, 34, 10, 10, width, height),
    teams = {
      {
        tankVertical = love.graphics.newQuad(22, 0, 16, 16, width, height),
        tankHorizontal = love.graphics.newQuad(39, 0, 16, 16, width, height),
        goal = love.graphics.newQuad(0, 0, 10, 40, width, height),
        bullet = love.graphics.newQuad(56, 6, 8, 5, width, height)
      },
      {
        tankVertical = love.graphics.newQuad(22, 17, 16, 16, width, height),
        tankHorizontal = love.graphics.newQuad(39, 17, 16, 16, width, height),
        goal = love.graphics.newQuad(11, 0, 10, 40, width, height),
        bullet = love.graphics.newQuad(56, 23, 8, 5, width, height)
      }
    }
  }
  -- Load sounds
  sounds = {
    goal = love.audio.newSource('sfx/goal.wav', 'static'),
    shoot = love.audio.newSource('sfx/shoot.wav', 'static'),
    ballHit = love.audio.newSource('sfx/ball-hit.wav', 'static'),
    bulletHit = love.audio.newSource('sfx/bullet-hit.wav', 'static')
  }
  -- Initialize variables
  hasRequestedSpawn = false
end

-- Updates the game state
function Game:clientUpdate(state)
  -- Keep track of player input
  if self:clientIsSpawned() then
    local player = self:getPlayerState()
    local aimX, aimY = love.mouse.getX() / RENDER_SCALE, love.mouse.getY() / RENDER_SCALE
    self:setPlayerInput({
      up = love.keyboard.isDown('up') or love.keyboard.isDown('w'),
      left = love.keyboard.isDown('left') or love.keyboard.isDown('a'),
      down = love.keyboard.isDown('down') or love.keyboard.isDown('s'),
      right = love.keyboard.isDown('right') or love.keyboard.isDown('d'),
      shoot = love.mouse.isDown(1),
      aimAngle = math.atan2(aimY - player.y - player.w / 2, aimX - player.x - player.h / 2)
    })
  end
end
function Game:playerUpdate(player, input)
  -- Based on player update the player
  if input then
    -- Change velocity in response to player input
    player.vx = 32 * ((input.right and 1 or 0) - (input.left and 1 or 0))
    player.vy = 32 * ((input.down and 1 or 0) - (input.up and 1 or 0))
    if player.vx ~= 0 then
      player.vy = 0
      player.isFacingHorizontal = true
    elseif player.vy ~=0 then
      player.isFacingHorizontal = false
    end
    -- Keep the player in bounds
    player.x = clamp(0, player.x + player.vx * MOAT_CONFIG.TickInterval, GAME_WIDTH - player.w)
    player.y = clamp(0, player.y + player.vy * MOAT_CONFIG.TickInterval, GAME_HEIGHT - player.h)
    -- Shoot bullets when the mouse is clicked
    player.shootCooldown = math.max(0.00, player.shootCooldown - MOAT_CONFIG.TickInterval)
    if input.shoot and input.aimAngle and player.shootCooldown <= 0.00 then
      player.shootCooldown = 1.00
      self:spawn(ENTITY_TYPES.Bullet, player.x + player.w / 2 - 2.5, player.y + player.h / 2 - 2.5, 5, 5, {
        vx = 64 * math.cos(input.aimAngle),
        vy = 64 * math.sin(input.aimAngle),
        angle = input.aimAngle,
        ownerClientId = player.clientId
      })
      if self.isClient then
        -- love.audio.play(sounds.shoot:clone())
      end
    end
    self:moveEntity(player)
  end
end
function Game:worldUpdate(state)
  -- Update all bullets
  self:eachEntityOfType(ENTITY_TYPES.Bullet, function(bullet)
    -- Move the bullet
    bullet.x = bullet.x + bullet.vx * MOAT_CONFIG.TickInterval
    bullet.y = bullet.y + bullet.vy * MOAT_CONFIG.TickInterval
    self:moveEntity(bullet)
    -- Check for hits
    self:eachOverlapping(bullet, function(entity)
      -- Bullets push players back a bit
      if entity.type == ENTITY_TYPES.Player and entity.clientId ~= bullet.ownerClientId then
        entity.x = entity.x + 6 * bullet.vx * MOAT_CONFIG.TickInterval
        entity.y = entity.y + 6 * bullet.vy * MOAT_CONFIG.TickInterval
        self:moveEntity(entity)
        self:despawn(bullet)
        if self.isClient then
          -- love.audio.play(sounds.bulletHit:clone())
        end
      -- Bullets push balls away
      elseif entity.type == ENTITY_TYPES.Ball then
        local dx = entity.x - bullet.x
        local dy = entity.y - bullet.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 0 then
          entity.vx = (entity.vx + bullet.vx + 50 * dx / dist) / 2
          entity.vy = (entity.vy + bullet.vy + 50 * dy / dist) / 2
        end
        self:despawn(bullet)
        if self.isClient then
          -- love.audio.play(sounds.ballHit:clone())
        end
      -- Bullets cancel each other out
      elseif entity.type == ENTITY_TYPES.Bullet and entity.ownerClientId ~= bullet.ownerClientId then
        self:despawn(entity)
        self:despawn(bullet)
        if self.isClient then
          -- love.audio.play(sounds.bulletHit:clone())
        end
      end
    end)
    -- Despawn the bullet if it goes off screen
    if bullet.x > GAME_WIDTH or bullet.y > GAME_HEIGHT or bullet.x < -bullet.w or bullet.y < -bullet.h then
      self:despawn(bullet)
    end
  end)

  -- Update all balls
  self:eachEntityOfType(ENTITY_TYPES.Ball, function(ball)
    -- Move the ball
    ball.x = ball.x + ball.vx * MOAT_CONFIG.TickInterval
    ball.y = ball.y + ball.vy * MOAT_CONFIG.TickInterval
    -- Bounce the ball off of walls
    local bouncedOffSideWalls = false
    if ball.x < 0 then
      ball.x = 0
      ball.vx = math.abs(ball.vx)
      bouncedOffSideWalls = true
    elseif ball.x + ball.w > GAME_WIDTH then
      ball.x = GAME_WIDTH - ball.w
      ball.vx = -math.abs(ball.vx)
      bouncedOffSideWalls = true
    end
    if ball.y < 0 then
      ball.y = 0
      ball.vy = math.abs(ball.vy)
    elseif ball.y + ball.h > GAME_HEIGHT then
      ball.y = GAME_HEIGHT - ball.h
      ball.vy = -math.abs(ball.vy)
    end
    -- Apply friction to the ball's velocity
    ball.vx = ball.vx * 0.999
    ball.vy = ball.vy * 0.999
    -- Check to see if the ball entered the goal
    if bouncedOffSideWalls and 80 < ball.y and ball.y < 108 - ball.h then
      ball.x = GAME_WIDTH / 2 - 5
      ball.y = GAME_HEIGHT / 2 - 5
      ball.vx = 0
      ball.vy = 0
      if self.isClient then
        -- love.audio.play(sounds.goal:clone())
      end
    end
    self:moveEntity(ball)
  end)
end

-- Draws the game
function Game:clientDraw()
  -- Scale up the screen
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)

  -- Clear the screen
  love.graphics.setColor(244 / 255, 56 / 255, 11 / 255)
  love.graphics.rectangle('fill', 0, 0, GAME_WIDTH, GAME_HEIGHT)
  love.graphics.setColor(1, 1, 1)

  -- Draw the goals
  love.graphics.draw(spriteSheet, quads.teams[1].goal, 1, 77)
  love.graphics.draw(spriteSheet, quads.teams[2].goal, GAME_WIDTH - 11, 77)

  -- Draw all the bullets
  self:eachEntityOfType(ENTITY_TYPES.Bullet, function(bullet)
    love.graphics.draw(spriteSheet, quads.teams[1 + bullet.ownerClientId % 2].bullet, bullet.x + bullet.w / 2, bullet.y + bullet.h / 2, bullet.angle, 1, 1, 4, 2.5)
  end)

  -- Draw all the players
  self:eachEntityOfType(ENTITY_TYPES.Player, function(player)
    if player.isFacingHorizontal then
      love.graphics.draw(spriteSheet, quads.teams[1 + player.clientId % 2].tankHorizontal, player.x, player.y)
    else
      love.graphics.draw(spriteSheet, quads.teams[1 + player.clientId % 2].tankVertical, player.x, player.y)
    end
  end)

  -- Draw all the balls
  self:eachEntityOfType(ENTITY_TYPES.Ball, function(ball)
    love.graphics.draw(spriteSheet, quads.ball, ball.x, ball.y)
  end)
end

-- Click to request a spawn
function Game:clientMousePressed(key)
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
  player.x, player.y = math.random(20, GAME_WIDTH - 20), math.random(20, GAME_WIDTH - 20)
  player.w, player.h = 16, 16
  player.vx, player.vy = 0, 0
  player.shootCooldown = 0.00
  player.isFacingHorizontal = true
end

-- Keeps a number between the given minimum and maximum values
function clamp(minimum, num, maximum)
  return math.min(math.max(minimum, num), maximum)
end

-- Run the game
Game:run()
