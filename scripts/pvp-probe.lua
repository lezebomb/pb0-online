-- Development-only observer: uses the installed Phantom Pact API without changing upstream files.
local config=assert(PB0_PROBE_CONFIG)
local api=assert(PBZ)
local probe={stopped=false,phase="movement"}
local output=assert(io.open(config.output,"w"))
local function quote(v)
    return '"'..tostring(v):gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')..'"'
end
local function encode(v)
    if type(v)=="boolean" then return v and "true" or "false" end
    if type(v)=="number" then return v==v and tostring(v) or "null" end
    if type(v)=="table" then
        local f={}
        for k,x in pairs(v) do f[#f+1]=quote(k)..":"..encode(x) end
        return "{"..table.concat(f,",").."}"
    end
    return v==nil and "null" or quote(v)
end
local function emit(kind,value)
    value=value or {};if api.game.motionUtcMs then value.utcMs=api.game.motionUtcMs() end;value.type,value.phase,value.clock,value.runId=kind,probe.phase,os.clock(),config.runId
    output:write(encode(value),"\n");output:flush()
end
local library=StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
local function ascOf(actor) return api.valid(actor) and library:GetAbilitySystemComponent(actor) or nil end
local function abilities(actor)
    local all,active,asc={},{},ascOf(actor)
    if api.valid(asc) then asc.ActivatableAbilities.Items:ForEach(function(_,element)
        pcall(function()
            local spec=element:get()
            if api.valid(spec.Ability) then
                local cls=spec.Ability:GetClass();local name=cls:GetFName():ToString()
                if name:find("^GA_Hun") then
                    all[name]=cls:GetFullName():gsub("^%S+ ","")
                    if spec.ActiveCount>0 then active[#active+1]=name end
                end
            end
        end)
    end) end
    return all,table.concat(active,",")
end
local function discover(actor)
    local all=abilities(actor)
    local attack,guard=all.GA_Hun_Young_A_C,nil
    for name,path in pairs(all) do
        if not attack and (name:find("_A_C$") or name:find("Attack") or name:find("LightAttack")) then attack=path end
        if not guard and name:find("Stance") then guard=path end
    end
    probe.attack,probe.guard=attack,guard
    emit("capabilities",{attackPath=attack or "",guardPath=guard or "",abilities=all})
end
local function stats(actor)
    local _,active=abilities(actor);local l=actor:K2_GetActorLocation()
    local result={x=l.X,y=l.Y,z=l.Z,hp=api.game.getHealth(actor),posture=api.game.getPosture(actor),active=active}
    pcall(function()
        local m=actor.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if api.valid(m) then result.montage=m:GetFName():ToString() end
    end)
    return result
end
-- Recording-only camera; combat and rendering remain the real game's own systems.
function probe.showcaseCamera(x,y,z)
    local pc,p=api.getPlayer1()
    if not (api.valid(pc) and api.valid(p)) then return false end
    local position={X=x,Y=y-300,Z=z+260}
    if not api.valid(probe.camera) then
        local transform={Rotation={X=0,Y=0,Z=0,W=1},Translation=position,Scale3D={X=1,Y=1,Z=1}}
        local camera=api.gs():BeginDeferredActorSpawnFromClass(pc,StaticFindObject("/Script/Engine.CameraActor"),transform,2,nil,0)
        probe.camera=api.gs():FinishSpawningActor(camera,transform,0)
    end
    if not api.valid(probe.camera) then return false end
    probe.camera:K2_SetActorLocationAndRotation(position,{Pitch=-31,Yaw=90,Roll=0},false,{},true)
    pcall(function() probe.camera.CameraComponent:SetFieldOfView(60) end)
    pc:SetViewTargetWithBlend(probe.camera,0,0,0,false)
    emit("recording_camera",{x=position.X,y=position.Y,z=position.Z})
    return true
end
function probe.attackOnce(faceTarget)
    local _,p=api.getPlayer1()
    if not (api.valid(p) and probe.attack) then emit("local_attack",{ok=false});return false end
    if faceTarget~=false then probe.face() end
    local ok=api.game.playAbility(p,probe.attack)
    emit("local_attack",{ok=ok==true,path=probe.attack,utcMs=api.game.motionUtcMs and api.game.motionUtcMs() or nil})
    return ok
end
function probe.face()
    local pc,p=api.getPlayer1();local g=api.net.ghost
    if not (api.valid(p) and api.valid(g)) then return false end
    local a,b=p:K2_GetActorLocation(),g:K2_GetActorLocation()
    local yaw=math.deg(math.atan(b.Y-a.Y,b.X-a.X))
    p:K2_SetActorRotation({Pitch=0,Yaw=yaw,Roll=0},false)
    pc:SetControlRotation({Pitch=-8,Yaw=yaw,Roll=0})
    return true
end
function probe.defend()
    local _,p=api.getPlayer1()
    if not (api.valid(p) and probe.guard) then emit("guard_activation",{ok=false});return false end
    probe.face()
    local ok=api.game.playAbility(p,probe.guard)
    emit("guard_activation",{ok=ok==true,path=probe.guard})
    return ok
end
-- Feed the normal enhanced-input pipeline: stance must remain held while deflect is pressed.
function probe.parry()
    if config.autoParry==false then return false end
    local pc,p=api.getPlayer1()
    if not (api.valid(pc) and api.valid(p)) then return false end
    probe.face()
    local subsystem,stance,deflect
    for _,s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:GetOuter().ControllerId==pc.Player.ControllerId then subsystem=s;break end
    end
    for _,a in ipairs(FindAllOf("InputAction") or {}) do
        local n=a:GetFName():ToString()
        if n=="IA_Stance" then stance=a elseif n=="IA_Deflect" then deflect=a end
    end
    if not (api.valid(subsystem) and api.valid(stance) and api.valid(deflect)) then emit("deflect_input",{ok=false,error="enhanced input unavailable"});return false end
    local started=os.clock()
    local released=false
    local function feed()
        if released then return end
        local elapsed=os.clock()-started
        if probe.stopped or elapsed>0.45 or probe.cancelInput then
            subsystem:InjectInputVectorForAction(stance,{X=0,Y=0,Z=0},{},{})
            subsystem:InjectInputVectorForAction(deflect,{X=0,Y=0,Z=0},{},{})
            released=true;api.game.after(0.03,function() if not probe.stopped then probe.release() end end);return
        end
        subsystem:InjectInputVectorForAction(stance,{X=1,Y=0,Z=0},{},{})
        subsystem:InjectInputVectorForAction(deflect,{X=elapsed<0.06 and 1 or 0,Y=0,Z=0},{},{})
        api.game.after(0.016,feed)
    end
    probe.cancelInput=false;feed()
    local mode=false;pcall(function() mode=p.PBZNBInput:IsGameInputMode() end)
    emit("deflect_input",{ok=true,method="enhanced-stance-and-deflect",gameInputMode=mode})
    return true
end
function probe.release()
    probe.cancelInput=true
    local _,p=api.getPlayer1();local asc=ascOf(p);local ended=0
    if api.valid(asc) then asc.ActivatableAbilities.Items:ForEach(function(_,element)
        pcall(function()
            local s=element:get()
            if s.ActiveCount>0 and api.valid(s.Ability) and (s.Ability:GetClass():GetFName():ToString():find("Stance") or s.Ability:GetClass():GetFName():ToString():find("HoldDeflect")) then
                for _,field in ipairs({"NonReplicatedInstances","ReplicatedInstances"}) do
                    pcall(function() s[field]:ForEach(function(_,instance)
                        local ab=instance:get()
                        if api.valid(ab) then ab:K2_EndAbility();ended=ended+1 end
                    end) end)
                end
            end
        end)
    end) end
    emit("guard_release",{ended=ended})
end
function probe.setPhase(phase) probe.phase=phase;emit("phase_started") end
function probe.stop() probe.stopped=true end
local adapter=rawget(_G,"PB0_NATIVE_PVP")
if adapter then adapter.onEvent=function(event) if not probe.stopped then emit(event.type,event) end end end
local oldPlay=api.game.playMove
api.game.playMove=function(actor,path,yaw)
    oldPlay(actor,path,yaw)
        if actor==api.net.ghost then
        emit("remote_move_applied",{path=path,yaw=yaw})
        if probe.phase=="parry" and not path:find("Stance") and not path:find("Deflect") and not path:find("Dash") and not path:find("Dodge") and not path:find("Escape") then api.game.after(config.parryDelay or 0.25,function() if not probe.stopped then probe.parry() end end) end
    end
end
-- Observe the engine's own contact verdict. Never create/modify a deflect frame or a result.
local engineHookPath="/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData"
local hookOk,hookPre,hookPost=pcall(RegisterHook,engineHookPath,function() end,function(context,handle,tag,out)
    if probe.stopped then return end
    local ok,err=pcall(function()
        local result=out:get()
        local source,defender=result.SourceAvatar,result.DefenderAvatar
        local _,p=api.getPlayer1()
        if not (api.valid(source) and api.valid(defender) and api.valid(p) and api.valid(api.net.ghost) and source:GetAddress()==api.net.ghost:GetAddress() and defender:GetAddress()==p:GetAddress()) then return end
        emit("engine_deflect",{tag=tag:get().TagName:ToString(),result=result.DeflectResult.TagName:ToString(),hit=result.IsHit==true,handle=handle:get(),source=source:GetFName():ToString(),defender=defender:GetFName():ToString()})
    end)
    if not ok then emit("engine_observer_error",{error=tostring(err)}) end
end)
probe.engineHook={ok=hookOk,pre=hookPre,post=hookPost}
emit("probe_started",{source="real-game",engineHook=hookOk})
pcall(function()
    local lib=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    emit("runtime_paths",{project=lib:GetProjectDirectory():ToString(),saved=lib:GetProjectSavedDirectory():ToString()})
end)
LoopInGameThreadWithDelay(50,function()
    if probe.stopped then if not probe.closed then api.game.playMove=oldPlay;if hookOk then pcall(UnregisterHook,engineHookPath,hookPre,hookPost) end output:close();probe.closed=true end return true end
    local ok,err=pcall(function()
        local _,p=api.getPlayer1()
        local s={playerReady=api.valid(p),enabled=api.net.enabled==true,ghostExists=api.valid(api.net.ghost),ghostHidden=api.net.ghostHidden==true}
        if not s.playerReady and config.autoContinue and not probe.precompileSkipped then
            for _,w in ipairs(FindAllOf("UserWidget") or {}) do
                if w:GetFullName():find("/Engine/Transient") and w:GetFName():ToString():find("W_PrecompilePSO_C") and w:IsVisible() then
                    w["Action Progress_Event"](w,1.0);probe.precompileSkipped=true;emit("shader_precompile_skipped");break
                end
            end
        end
        if not s.playerReady and config.autoContinue and not probe.continueSent then
            for _,w in ipairs(FindAllOf("UserWidget") or {}) do
                if w:GetFName():ToString()=="ContinueGame" and w:GetFullName():find("/Engine/Transient") and w:IsVisible() and w:IsInteractionEnabled() then
                    w:HandleButtonClicked();probe.continueSent=true;emit("continue_requested");break
                end
            end
        end
        if s.playerReady then
            s.player=stats(p);s.cutscene=api.game.inCutscene and api.game.inCutscene() or false
            if probe.playerAddress~=p:GetAddress() or (not probe.attack and os.clock()>=(probe.nextDiscover or 0)) then discover(p);probe.playerAddress=p:GetAddress();probe.nextDiscover=os.clock()+1 end
        end
        if s.ghostExists then
            local g=api.net.ghost;s.ghost=stats(g);s.meshVisible=false
            pcall(function() s.meshVisible=g.Mesh:IsVisible()==true end)
            s.distance=s.playerReady and api.distance(p:K2_GetActorLocation(),g:K2_GetActorLocation()) or -1
        end
        emit("sample",s)
    end)
    if not ok and not probe.reportedError then emit("probe_error",{error=tostring(err)});probe.reportedError=true end
    return false
end)
return probe
