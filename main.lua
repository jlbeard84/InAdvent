--
-- InAdvent
--

TARGETING_OCULUS_QUEST = true

if not enet then enet = require 'enet' end 
if not json then json = require 'cjson' end 
if not b64 then b64 = require 'src/base64' end 
if not EGA then local m = lovr.filesystem.load('src/lib.lua'); m() end 

-- Globals
player_flags = {
    MOVING_FORWARD = false,
    MOVING_BACKWARD = false,
    STRAFE_LEFT = false, 
    STRAFE_RIGHT = false, 
    TURNING_RIGHT = false,
    TURNING_LEFT = false 
}
shader = nil
camera = nil
view = nil
p = {
    x = 0.0, y = 0, z = 0.0, 
    rot = -math.pi/2,
    h = 0.0
}
deltaTime = 0.0
gameTime = 0.0

serverTick = (1/40) -- 25ms, to target 50ms updates
currentState = {
    players = {}
} -- world state .data
local myPlayerState = {
    pos = { x = 0.0, y = 0.0, z = 0.0 },
    rot = { x = 0.0, y = 0.0, z = 0.0, m = 0.0 },
    lHandPos = { x = 0.0, y = 0.0, z = 0.0 },
    lHandRot = { x = 0.0, y = 0.0, z = 0.0, m = 0.0 },
    lHandObj = '',
    rHandPos = { x = 0.0, y = 0.0, z = 0.0 },
    rHandRot = { x = 0.0, y = 0.0, z = 0.0, m = 0.0 },
    rHandObj = '',
    faceTx = '',
    bodyTx = '',
    action = ''
}

local playerSpeed = 5.0
local firstUpdate = false
local toThread 
local toMain 
local channel 
threadCode = lovr.filesystem.read('src/thread.lua')

local headsetState = {
    x = 0, y = 0, z = 0,
    an = 0, ax = 0, ay = 1, az = 0
}

-- GUI code
--[[
local GUI = { canvas = nil }
GUI.render = function ()
    lg.setShader()
    lg.setFont()
    --local guipos = { x = p.x + 2.0 * math.cos(p.rot - 0.33), 
    --    z = p.z + 2.0 * math.sin(p.rot - 0.33), 
    --    y = p.y + p.h }
    local guipos = {
        x = 0, 
        y = 2, 
        z = -2
    }
    GUI.canvas:renderTo(function()
        lg.clear(0, 0, 0, 0)
        lg.print('GUI test\nHP: 10 / 10\nMP: 2 / 2\nLv: 1\nXP: 0 / 1000', 
            guipos.x, guipos.y, guipos.z, 0.2)
    end)
    --lg.plane(lg.newMaterial(GUI.canvas:getTexture()), guipos.x, guipos.y, guipos.z, 2, 1, -p.rot-math.pi/2)
    
end
]]

local ori = {
    x = 0, y = 0, z = 0, an = 0, ax = 0, ay = 1, az = 0
}
local hr 

function lovr.load()
    
    ori.x, ori.y, ori.z, ori.an, ori.ax, ori.ay, ori.az = lovr.headset.getPose()

    -- Setup shaders
    local defaultVert = lovr.filesystem.read('shaders/default.vert')
    local defaultFrag = lovr.filesystem.read('shaders/default.frag')

    shader = lovr.graphics.newShader(defaultVert, defaultFrag, 
        { flags = { uniformScale = true } }
    )

    -- Load models
    p_body = lovr.graphics.newModel('assets/p_body.glb')
    p_head = lovr.graphics.newModel('assets/p_head.glb')
    sword1 = lovr.graphics.newModel('assets/sword1.glb')

    -- Load textures
    texChain = lovr.graphics.newTexture('assets/chainmail.png')
    texChain:setFilter('nearest')
    texFace1 = lovr.graphics.newTexture('assets/face1.png')
    texFace1:setFilter('nearest')
    texSwd1 = lovr.graphics.newTexture('assets/sword1.png')
    texSwd1:setFilter('nearest')

	satFont = lovr.graphics.newFont('assets/saturno.ttf')

    -- Just in case!
    lovr.headset.setClipDistance(0.1, 100.0)

    local scr_w, scr_h
    if TARGETING_OCULUS_QUEST then 
        scr_w, scr_h = lovr.headset.getDisplayDimensions()
        GUI = lovr.graphics.newCanvas(scr_w, scr_h, { stereo = true})
    else 
        scr_w, scr_h = 1080, 600 
        GUI = lovr.graphics.newCanvas(scr_w, scr_h, { stereo = false })
    end

    t = lovr.thread.newThread(threadCode)
    toMain = lovr.thread.getChannel('toMain')
    toThread = lovr.thread.getChannel('toThread')
    t:start()

    print('Debug: LOAD completed')
end

local clientId

function GetHead()
    local fx, fy, fz, fan, fax, fay, faz = lovr.headset.getPose('head')
    local o = { x = fx, y = fy, z = fz, an = fan, ax = fax, ay = fay, az = faz }
    return o
end

function lovr.update(dT)
    
    deltaTime = dT
    gameTime = gameTime + dT

    headsetState.an, headsetState.ax, headsetState.ay, headsetState.az = lovr.headset.getOrientation()
    headsetState = GetHead()
    p.h = headsetState.y

    -- Get pending info from Thread if any 
    local cmsg = toMain:pop()
    if cmsg ~= nil then 
        if cmsg == 'GivingClientID' then 
            clientId = WaitForNext(toMain)
            print(clientId)
        elseif cmsg == 'GivingWorldState' then 
            currentState = json.decode(WaitForNext(toMain))
        end
    end

    if TARGETING_OCULUS_QUEST then 
        local lx, ly = lovr.headset.getAxis('hand/left', 'thumbstick')
        --print(lx, ly) -- UP is Y+, DOWN is Y-, LEFT is X-, RIGHT is X+
        --projected: 
        if ly < -0.5 then player_flags.MOVING_BACKWARD = true else player_flags.MOVING_BACKWARD = false end 
        if ly > 0.5 then player_flags.MOVING_FORWARD = true else player_flags.MOVING_FORWARD = false end 
        if lx < -0.5 then player_flags.STRAFE_LEFT = true else player_flags.STRAFE_LEFT = false end 
        if lx > 0.5 then player_flags.STRAFE_RIGHT = true else player_flags.STRAFE_RIGHT = false end 
        local rx, ry = lovr.headset.getAxis('hand/right', 'thumbstick')
        if rx > 0.5 then player_flags.TURNING_RIGHT = true else player_flags.TURNING_RIGHT = false end 
        if rx < -0.5 then player_flags.TURNING_LEFT = true else player_flags.TURNING_LEFT = false end 
    end

    if not TARGETING_OCULUS_QUEST then
        if player_flags.MOVING_FORWARD then 
            p.z = p.z + (deltaTime * playerSpeed) * math.sin(p.rot)
            p.x = p.x + (deltaTime * playerSpeed) * math.cos(p.rot)
        elseif player_flags.MOVING_BACKWARD then 
            p.z = p.z - (deltaTime * playerSpeed) * math.sin(p.rot)
            p.x = p.x - (deltaTime * playerSpeed) * math.cos(p.rot)
        end
        if player_flags.STRAFE_RIGHT then 
            p.x = p.x + (deltaTime * playerSpeed) * math.cos(p.rot + math.pi/2)
            p.z = p.z + (deltaTime * playerSpeed) * math.sin(p.rot + math.pi/2)
        elseif player_flags.STRAFE_LEFT then 
            p.x = p.x + (deltaTime * playerSpeed) * math.cos(p.rot - math.pi/2)
            p.z = p.z + (deltaTime * playerSpeed) * math.sin(p.rot - math.pi/2)
        end
    else 
        hr = headsetState.an * headsetState.ay
        if hr < -math.pi then hr = hr + math.pi end 
        if hr > math.pi then hr = hr - math.pi end 
        hr = hr * -1
        if player_flags.MOVING_FORWARD then 
            p.z = p.z + (deltaTime * playerSpeed) * math.sin(hr + p.rot)
            p.x = p.x + (deltaTime * playerSpeed) * math.cos(hr + p.rot)
        elseif player_flags.MOVING_BACKWARD then 
            p.z = p.z - (deltaTime * playerSpeed) * math.sin(hr + p.rot)
            p.x = p.x - (deltaTime * playerSpeed) * math.cos(hr + p.rot)
        end
        if player_flags.STRAFE_RIGHT then 
            p.x = p.x + (deltaTime * playerSpeed) * math.cos((hr+p.rot) + math.pi/2)
            p.z = p.z + (deltaTime * playerSpeed) * math.sin((hr+p.rot) + math.pi/2)
        elseif player_flags.STRAFE_LEFT then 
            p.x = p.x + (deltaTime * playerSpeed) * math.cos((hr+p.rot) - math.pi/2)
            p.z = p.z + (deltaTime * playerSpeed) * math.sin((hr+p.rot) - math.pi/2)
        end
    end
    if player_flags.TURNING_RIGHT then 
        p.rot = p.rot + (deltaTime * playerSpeed/2)
    elseif player_flags.TURNING_LEFT then 
        p.rot = p.rot - (deltaTime * playerSpeed/2)
    end
    if p.rot < -math.pi then p.rot = math.pi end 
    if p.rot > math.pi then p.rot = -math.pi end 
    if player_flags.MOVING_BACKWARD or player_flags.MOVING_FORWARD or player_flags.STRAFE_RIGHT 
    or player_flags.STRAFE_LEFT or player_flags.TURNING_LEFT or player_flags.TURNING_RIGHT then 
        myPlayerState.UPDATE_ME = true 
    else 
        myPlayerState.UPDATE_ME = false 
    end 
    -- Update my state for the thread!
    myPlayerState.pos.x = round(p.x, 3); myPlayerState.pos.y = round(p.y + p.h, 3); myPlayerState.pos.z = round(p.z, 3);
    -- convert rotation to quaternion
    myPlayerState.rot.m = -p.rot + math.pi/2; 
    
    -- VIEW
    camera = lovr.math.newMat4():lookAt(
        vec3(p.x, p.y, p.z),
        vec3(p.x + math.cos(p.rot), 
             p.y, 
             p.z + math.sin(p.rot)))
    view = lovr.math.newMat4(camera):invert()

    -- CLIENT service called right before draw()    
	serverTick = serverTick - deltaTime 
	if serverTick < 0 then 
		serverTick = serverTick + (1/40)
        toThread:push('tick')
        toThread:push(json.encode(myPlayerState))
	end

end

--Input

if not TARGETING_OCULUS_QUEST then 
    include 'src/input.lua'

    function lovr.mirror()
        lovr.graphics.clear()
        --lovr.graphics.transform(view)
        lovr.draw()
    end
end
--

lg = lovr.graphics 

function lovr.draw()
    lovr.graphics.transform(view)
    lovr.graphics.setShader(shader)

    shader:send('curTex', texSwd1)
    sword1:draw(-1, 1, -5, 1, gameTime*4, 1, 0, 0)

    lovr.graphics.setShader()
    lovr.graphics.setColor(0, 1, 0, 1)
    lovr.graphics.plane('fill', 0, 0, 0, 20, 20, math.pi/2, 1, 0, 0)
    lovr.graphics.setColor(1, 1, 1, 1)

	lovr.graphics.setShader()
	lovr.graphics.setFont(satFont)
    lovr.graphics.print('ima fk uup\npoing!', 2, 3, -6)

    for k,v in pairs(currentState.players) do 
        if k then 
            if (v.pos) then 
                lg.setShader(shader)
                if tonumber(k) ~= clientId then 
                    shader:send('curTex', texChain) -- TODO 
                    p_body:draw(v.pos.x, v.pos.y - 0.25, v.pos.z, 1.0, v.rot.m)
                    shader:send('curTex', texFace1) -- TODO
                    p_head:draw(v.pos.x, v.pos.y, v.pos.z, 1.0, v.rot.m)
                end
                lg.setShader()
                lg.print(k, v.pos.x, v.pos.y + 3, v.pos.z, 1.0, v.rot.m)
            end
        end
    end

    -- Draw gui
    --[[ World-rotation agnostic GUI]]
    local guipos = { x = p.x + 2.0 * math.cos(p.rot), 
        z = p.z + 2.0 * math.sin(p.rot), 
        y = p.h }
    lg.print('GUI test', 
        guipos.x, guipos.y, guipos.z, 0.2, -p.rot-math.pi/2)
    --[[ HMD-oriented GUI]]
    local gpos2 = { x = p.x + 2.0 * math.cos(hr + p.rot - 0.2),
        y = p.h + 1,
        z = p.z + 2.0 * math.sin(hr + p.rot - 0.2) }
    lg.print('HP: 10 / 10\nMP: 2 / 2\nLv: 1\nXP: 0 / 1000', 
        gpos2.x, gpos2.y, gpos2.z, 0.1, -(hr+p.rot)-math.pi/2)

    lovr.graphics.reset()
end

function lovr.quit()

	toThread:push('getbc')
	
end