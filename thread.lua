-- InAdvent client thread!
if not lovr then lovr = require "lovr" end 
if not lovr.thread then lovr.thread = require "lovr.thread" end
if not enet then require "enet" end 
if not json then json = require "json" end
if not lovr.filesystem then lovr.filesystem = require "lovr.filesystem" end 
local m = lovr.filesystem.load('lib.lua'); m()
if not action_types then require "action_types" end 

local lastBroadcast = 99
local clientId 
local lastPing = 99
local pings = {}
local broadcasts = {}
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
local lastPlayerState = {} 

-- Packets 
local packets = {
loginRequest = {
    message_type = 'login', 
    data = {
        player_username = "user",
        password = "password"
    }
},

pong = {
    message_type = "pong",
    data = {}
},

get_ping = { 
    message_type = "get_ping",
    data = {}
},

start_action = {
    message_type = "start_action",
    data = action_types.melee_swing
}

}
-- Connect
local host = enet.host_create(nil, 64, 2, 0, 0)
-- Ben's AWS 01:
local server = host:connect("54.196.121.96:33111", 2)

local channel = lovr.thread.getChannel('chan')

while true do 
    local msg = channel:pop()
    if msg ~= nil then 
        if msg == 'tick' then 
            if server then 
                local event = host:service()
                if event then
                    if event.data ~= (0 or nil) then     
                        --client.process(event)
                        local o = json.decode(event.data)
                        --if o.type then print(o.type) end 
                        if o.type == 'login_response' then 
                            clientId = o.clientId 
                            serverTick = (1/40)
                            print(event.data)
                        elseif o.type == 'ping_response' then
                            local v = o.ts
                            local thisPing = v - lastPing
                            table.insert(pings, thisPing)
                            lastPing = v
                        elseif o.type == 'state' then
                            local v = o.ts
                            local thisBroadcast = v - lastBroadcast
                            table.insert(broadcasts, thisBroadcast)
                            lastBroadcast = v
                            currentState = o.data --FIXME
                            -- Look for 'action' receipt here
                        end
                    end
                else
                    if myPlayerState ~= lastPlayerState then 
                        server:send(json.encode(myPlayerState))
                        lastPlayerState = myPlayerState
                    else
                        server:send(json.encode(packets.get_ping))
                    end
                end
            end
        elseif msg == 'getbc' then 
            local avg = GetAverage(broadcasts)
            print('Average broadcast: ' .. round(avg, 1))
            avg = GetAverage(pings)
            print('Average ping: ' .. round(avg, 1))
        end
    end
end