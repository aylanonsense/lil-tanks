-- Load dependencies
local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/f01f65c143604046ef11f76218860dc63a267452/simulsim.lua'

-- Render constants
local GAME_WIDTH = 200
local GAME_HEIGHT = 200
local RENDER_SCALE = 2

-- Client variables
local spriteSheet
local sounds

-- Server variables
local nextTankTeam

-- Define a new game
local game = simulsim.defineGame()
function game.update(self, dt, isRenderable)
  self:forEachEntityWhere({ type = 'ball' }, function(ball)
    -- Move the ball
    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt
    -- Bounce the ball off of walls
    local bouncedOffSideWalls = false
    if ball.x < 0 then
      ball.x = 0
      ball.vx = math.abs(ball.vx)
      bouncedOffSideWalls = true
    elseif ball.x + ball.width > GAME_WIDTH then
      ball.x = GAME_WIDTH - ball.width
      ball.vx = -math.abs(ball.vx)
      bouncedOffSideWalls = true
    end
    if ball.y < 0 then
      ball.y = 0
      ball.vy = math.abs(ball.vy)
    elseif ball.y + ball.height > GAME_HEIGHT then
      ball.y = GAME_HEIGHT - ball.height
      ball.vy = -math.abs(ball.vy)
    end
    -- Apply friction to the ball's velocity
    ball.vx = ball.vx * 0.999
    ball.vy = ball.vy * 0.999
    -- Check to see if the ball entered the goal
    if bouncedOffSideWalls and 80 < ball.y and ball.y < 108 - ball.height then
      ball.x = GAME_WIDTH / 2 - 5
      ball.y = GAME_HEIGHT / 2 - 5
      ball.vx = 0
      ball.vy = 0
      if isRenderable then
        love.audio.play(sounds.goal:clone())
      end
    end
  end)
  self:forEachEntityWhere({ type = 'tank' }, function(tank)
    local inputs = self:getInputsForClient(tank.clientId) or {}
    -- Change tank velocity in response to player input
    tank.vx = 50 * ((inputs.right and 1 or 0) - (inputs.left and 1 or 0))
    tank.vy = 50 * ((inputs.down and 1 or 0) - (inputs.up and 1 or 0))
    if tank.vx ~= 0 then
      tank.vy = 0
      tank.isFacingHorizontal = true
    elseif tank.vy ~=0 then
      tank.isFacingHorizontal = false
    end
    -- Keep the tank in bounds
    tank.x = clamp(0, tank.x + tank.vx * dt, GAME_WIDTH - tank.width)
    tank.y = clamp(0, tank.y + tank.vy * dt, GAME_HEIGHT - tank.height)
    -- Reduce shoot cooldown
    tank.shootCooldown = math.max(0.00, tank.shootCooldown - dt)
  end)
  self:forEachEntityWhere({ type = 'bullet' }, function(bullet)
    -- Move the bullet
    bullet.x = bullet.x + bullet.vx * dt
    bullet.y = bullet.y + bullet.vy * dt
    -- Check for hits
    self:forEachEntity(function(entity)
      if isOverlapping(entity, bullet) then
        -- Bullets push opposing tanks back a bit
        if entity.type == 'tank' and entity.team ~= bullet.team then
          entity.x = entity.x + 10 * bullet.vx * dt
          entity.y = entity.y + 10 * bullet.vy * dt
          self:despawnEntity(bullet)
          -- Temporarily disable syncing for the tank to prevent thrashing (due to client-predicted
          -- entities interacting with non-preicted entities and vice versa)
          self:temporarilyDisableSyncForEntity(entity)
          if isRenderable then
            love.audio.play(sounds.bulletHit:clone())
          end
        -- Bullets push balls away
        elseif entity.type == 'ball' then
          local dx = entity.x - bullet.x
          local dy = entity.y - bullet.y
          local dist = math.sqrt(dx * dx + dy * dy)
          if dist > 0 then
            entity.vx = (entity.vx + bullet.vx + 20 * dx / dist) / 2
            entity.vy = (entity.vy + bullet.vy + 20 * dy / dist) / 2
          end
          -- Set the clientId on the ball so that the client who hit the ball sees the predicted arc of movement
          entity.clientId = bullet.clientId
          self:despawnEntity(bullet)
          if isRenderable then
            love.audio.play(sounds.ballHit:clone())
          end
        -- Bullets cancel each other out
        elseif entity.type == 'bullet' and entity.team ~= bullet.team then
          self:despawnEntity(bullet)
          self:despawnEntity(entity)
          if isRenderable then
            love.audio.play(sounds.bulletHit:clone())
          end
        end
      end
    end)
    -- Despawn the bullet if it goes off screen
    if bullet.x > GAME_WIDTH or bullet.y > GAME_HEIGHT or bullet.x < -bullet.width or bullet.y < -bullet.height then
      self:despawnEntity(bullet)
    end
  end)
end
function game.handleEvent(self, type, data, isRenderable)
  -- Spawn a ball
  if type == 'spawn-ball' then
    self:spawnEntity({
      type = 'ball',
      x = GAME_WIDTH / 2 - 5,
      y = GAME_HEIGHT / 2 - 5,
      width = 10,
      height = 10,
      vx = 0,
      vy = 0
    })
  -- Spawn a tank
  elseif type == 'spawn-tank' then
    self:spawnEntity({
      type = 'tank',
      clientId = data.clientId,
      team = data.team,
      x = data.x,
      y = data.y,
      width = 16,
      height = 16,
      vx = 0,
      vy = 0,
      shootCooldown = 0.00,
      isFacingHorizontal = true
    })
  -- Despawn a tank
  elseif type == 'despawn-tank' then
    local tank = self:getEntityWhere({ type = 'tank', clientId = data.clientId })
    if tank then
      self:despawnEntity(tank)
    end
  -- Shoot a bullet
  elseif type == 'shoot-bullet' then
    local tank = self:getEntityWhere({ type = 'tank', clientId = data.clientId })
    if tank and tank.shootCooldown <= 0.00 then
      tank.shootCooldown = 1.00
      local aimAngle = math.atan2((data.aimY or 0) - tank.y - tank.width / 2, (data.aimX or 0) - tank.x - tank.height / 2)
      self:spawnEntity({
        type = 'bullet',
        clientId = tank.clientId,
        team = tank.team,
        x = tank.x + tank.width / 2 - 2.5,
        y = tank.y + tank.height / 2 - 2.5,
        width = 5,
        height = 5,
        vx = 64 * math.cos(aimAngle),
        vy = 64 * math.sin(aimAngle),
        angle = aimAngle
      })
      if isRenderable then
        love.audio.play(sounds.shoot:clone())
      end
    end
  end
end

-- Create a new network
local network, server, client = simulsim.createGameNetwork(game, { mode = 'multiplayer', framesBetweenFlushes = 1 })

-- The game starts with just a ball
function server.load()
  nextTankTeam = 1
  server.fireEvent('spawn-ball')
end

-- Whenever a client connects, spawn a tank for them
function server.clientconnected(client)
  server.fireEvent('spawn-tank', {
    clientId = client.clientId,
    team = nextTankTeam,
    x = math.random(20, GAME_WIDTH - 20),
    y = math.random(20, GAME_WIDTH - 20)
  })
  nextTankTeam = 3 - nextTankTeam
end

-- Whenever a client disconnects, despawn their tank
function server.clientdisconnected(client)
  server.fireEvent('despawn-tank', { clientId = client.clientId })
end

-- Load assets client-side
function client.load()
  -- Load images
  spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
  spriteSheet:setFilter('nearest', 'nearest')
  -- Load sounds
  sounds = {
    goal = love.audio.newSource('sfx/goal.wav', 'static'),
    shoot = love.audio.newSource('sfx/shoot.wav', 'static'),
    ballHit = love.audio.newSource('sfx/ball-hit.wav', 'static'),
    bulletHit = love.audio.newSource('sfx/bullet-hit.wav', 'static')
  }
end

-- Send inputs to the server every frame
function client.update(dt)
  client.setInputs({
    up = love.keyboard.isDown('w') or love.keyboard.isDown('up'),
    left = love.keyboard.isDown('a') or love.keyboard.isDown('left'),
    down = love.keyboard.isDown('s') or love.keyboard.isDown('down'),
    right = love.keyboard.isDown('d') or love.keyboard.isDown('right')
  })
end

-- Whenever a mouse button is pressed, shoot a bullet
function client.mousepressed(x, y)
  client.fireEvent('shoot-bullet', {
    clientId = client.clientId,
    aimX = x / RENDER_SCALE,
    aimY = y / RENDER_SCALE
  })
end

function client.draw()
  -- Scale up and clear the screen
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)
  love.graphics.setColor(244 / 255, 56 / 255, 11 / 255)
  love.graphics.rectangle('fill', 0, 0, GAME_WIDTH, GAME_HEIGHT)
  love.graphics.setColor(1, 1, 1)

  -- Draw the goals
  drawSprite(spriteSheet, 0, 0, 10, 40, 1, 77)
  drawSprite(spriteSheet, 11, 0, 10, 40, GAME_WIDTH - 11, 77)

  -- Draw all the server-side game entities
  client.gameWithoutPrediction:forEachEntity(function(entity)
    if entity.type == 'bullet' then
      drawSprite(spriteSheet, 56, entity.team == 1 and 40 or 57, 8, 5, entity.x + entity.width / 2, entity.y + entity.height / 2, entity.angle, 1, 1, 4, 2.5)
    elseif entity.type == 'tank' then
      drawSprite(spriteSheet, entity.isFacingHorizontal and 39 or 22, entity.team == 1 and 34 or 51, 16, 16, entity.x, entity.y)
    elseif entity.type == 'ball' then
      drawSprite(spriteSheet, 33, 85, 10, 10, entity.x, entity.y)
    end
  end)

  -- Draw all the unsmoothed game entities
  client.gameWithoutSmoothing:forEachEntity(function(entity)
    if entity.type == 'bullet' then
      drawSprite(spriteSheet, 56, 74, 8, 5, entity.x + entity.width / 2, entity.y + entity.height / 2, entity.angle, 1, 1, 4, 2.5)
    elseif entity.type == 'tank' then
      drawSprite(spriteSheet, entity.isFacingHorizontal and 39 or 22, 68, 16, 16, entity.x, entity.y)
    elseif entity.type == 'ball' then
      drawSprite(spriteSheet, 44, 85, 10, 10, entity.x, entity.y)
    end
  end)

  -- Draw all the game entities
  client.game:forEachEntity(function(entity)
    if entity.type == 'bullet' then
      drawSprite(spriteSheet, 56, entity.team == 1 and 6 or 23, 8, 5, entity.x + entity.width / 2, entity.y + entity.height / 2, entity.angle, 1, 1, 4, 2.5)
    elseif entity.type == 'tank' then
      drawSprite(spriteSheet, entity.isFacingHorizontal and 39 or 22, entity.team == 1 and 0 or 17, 16, 16, entity.x, entity.y)
    elseif entity.type == 'ball' then
      drawSprite(spriteSheet, 22, 85, 10, 10, entity.x, entity.y)
    end
  end)

  -- Draw network status
  love.graphics.setColor(0, 0, 0)
  if client.isConnecting() then
    love.graphics.print('Connecting', 3, 3)
  elseif not client.isConnected() then
    love.graphics.print('Disconnected', 3, 3)
  elseif not client.isSynced() then
    love.graphics.print('Syncing', 3, 3)
  else
    love.graphics.print('Frames of latency: ' .. client.getFramesOfLatency(), 3, 3)
  end
end

-- Write a custom smoothing function so that entities' position are adjusted a little more smoothly
function client.smoothEntity(game, entity, idealEntity)
  if idealEntity and entity then
    local dx, dy = idealEntity.x - entity.x, idealEntity.y - entity.y
    idealEntity.x = entity.x + dx / 10
    idealEntity.y = entity.y + dy / 10
  end
  return idealEntity
end

-- Keeps a number between the given minimum and maximum values
function clamp(minimum, num, maximum)
  return math.min(math.max(minimum, num), maximum)
end

-- Checks to see if two entities are overlapping using AABB detection
function isOverlapping(entity1, entity2)
  return entity1.x + entity1.width > entity2.x and entity2.x + entity2.width > entity1.x
    and entity1.y + entity1.height > entity2.y and entity2.y + entity2.height > entity1.y
end

-- Draw a sprite from a sprite sheet to the screen
function drawSprite(spriteSheet, sx, sy, sw, sh, ...)
  local width, height = spriteSheet:getDimensions()
  local quad = love.graphics.newQuad(sx, sy, sw, sh, width, height)
  return love.graphics.draw(spriteSheet, quad, ...)
end
