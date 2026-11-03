-- PB0 adapter: authoritative engine deflect verdict -> Phantom Pact's existing PvP event.
-- No damage, hitboxes, attributes, attack abilities, or deflect frames are implemented here.
local source=debug.getinfo(1,"S").source:gsub("^@","")
local iniPath=source:gsub("PB0CombatAdapter[/\\]Scripts[/\\]main%.lua$","PBZCoop/PhantomPact.ini")
local parryPosture=60
local ini=io.open(iniPath,"r")
if ini then local text=ini:read("a");ini:close();parryPosture=math.max(0,math.min(400,tonumber(text:match("[\r\n]%s*PvPParryPosture%s*=%s*(%d+)")) or 60)) end
local installed=false
local deadline=os.clock()+180
LoopInGameThreadWithDelay(50,function()
    if installed or os.clock()>deadline then return false end
    local api=rawget(_G,"PBZ")
    if not (api and api.coop and api.game) then return false end
    installed=true
    dofile(source:gsub("main%.lua$","presentation.lua"))(api)
    dofile(source:gsub("main%.lua$","locomotion.lua"))(api)
    local adapter={version=1,perfectCount=0,events={}}
    local seen={}
    PB0_NATIVE_PVP=adapter
    local function publish(event)
        adapter.events[#adapter.events+1]=event
        if #adapter.events>128 then table.remove(adapter.events,1) end
        if adapter.onEvent then pcall(adapter.onEvent,event) end
    end
    local ok,pre,post=pcall(RegisterHook,"/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData",function() end,function(context,handle,tag,out)
        local success,err=pcall(function()
            if not (api.net.enabled and api.net.pvp) then return end
            local result=out:get()
            if tag:get().TagName:ToString()~="Deflect.Result.Perfect" or result.IsHit then return end
            local source,defender=result.SourceAvatar,result.DefenderAvatar
            local _,player=api.getPlayer1()
            local ghost=api.net.ghost
            if not (api.valid(source) and api.valid(defender) and api.valid(player) and api.valid(ghost)) then return end
            if source:GetAddress()~=ghost:GetAddress() or defender:GetAddress()~=player:GetAddress() then return end
            -- The engine may query one contact repeatedly. HitGameTime identifies the original contact.
            local id=tostring(source:GetAddress())..":"..tostring(defender:GetAddress())..":"..tostring(result.HitGameTime)..":"..tostring(handle:get())
            local now=os.clock()
            if seen[id] then return end
            for key,time in pairs(seen) do if now-time>8 then seen[key]=nil end end
            seen[id]=now
            local posture=parryPosture -- The receiver applies Phantom Pact's existing V handler.
            adapter.perfectCount=adapter.perfectCount+1
            api.coop.sendEvent("V","parry",tostring(posture))
            publish({type="native_parry_sent",clock=now,tag="Deflect.Result.Perfect",amount=posture,hitGameTime=result.HitGameTime,id=id})
            api.game.after(0,function()
                if api.valid(ghost) and api.net.ghost==ghost and api.game.playHitReaction then
                    api.game.playHitReaction(ghost,"CharacterState.Hitreact.State.Normal.Heavy")
                end
            end)
        end)
        if not success then api.log("PB0 native verdict adapter: "..tostring(err)) end
    end)
    adapter.ready=ok
    if not ok then PB0_NATIVE_PVP=nil;api.log("PB0 native verdict adapter unavailable: "..tostring(pre))
    else adapter.hookPre,adapter.hookPost=pre,post;api.log("PB0 native PvP verdict adapter ready") end
    return false
end)
