-- Short-session observer and real Enhanced Input driver. Does not change player movement/animation state.
local api,base,c=PBZ,PB0_TEST,assert(PB0_LOCO_CONFIG)
local q={actions={},phase="setup",stopped=false,rows={},events={},lastFrame=-1,input={X=0,Y=0,Z=0}}
local system=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local abilityLib=StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
local function encode(v)
 local kind=type(v)
 if kind=="number" then return v==v and tostring(v) or "null" elseif kind=="boolean" then return tostring(v) elseif kind=="table" then
  local f={};for k,x in pairs(v) do f[#f+1]='"'..tostring(k)..'":'..encode(x) end;return "{"..table.concat(f,",").."}"
 end
 return '"'..tostring(v):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")..'"'
end
local log=assert(io.open(c.output,"w"))
local function event(kind,data)
 data=data or {};data.type=kind;data.phase=q.phase;data.wallClock=os.clock();pcall(function() data.utcMs=api.game.motionUtcMs() end)
 -- Stamp immediately, flush with the existing 200ms observer batch; tracing must not stall every frame.
 log:write(encode(data),"\n")
end
local function abilities(actor)
 local result={}
 local asc=abilityLib:GetAbilitySystemComponent(actor)
 if api.valid(asc) then asc.ActivatableAbilities.Items:ForEach(function(_,e)
  pcall(function() local s=e:get();if api.valid(s.Ability) then
   local cls=s.Ability:GetClass();local n=cls:GetFName():ToString()
   if n:find("Locomotion") or n:find("SpaceState") or n:find("Motion") then result[n]={active=s.ActiveCount,path=cls:GetFullName():gsub("^%S+ ","")} end
  end end)
 end) end
 return result
end
local bones={}
local function discoverBones(actor)
 local key=actor.Mesh:GetClass():GetFullName()
 if bones[key] then return bones[key] end
 local names={}
 local allNames={};local count=actor.Mesh:GetNumBones()
 for index=0,count-1 do
  local n=actor.Mesh:GetBoneName(index):ToString()
  if index<24 then allNames[#allNames+1]=n end
  if n=="foot_l" or n=="foot_r" then names[#names+1]=n end
 end
 bones[key]=names;event("foot_bones",{names=names,count=count,firstBones=allNames})
 return names
end
local function info(actor)
 local p=actor:K2_GetActorLocation();local cm=actor.CharacterMovement;local v=actor:GetVelocity();local rotation=actor:K2_GetActorRotation()
 local r={x=p.X,y=p.Y,z=p.Z,yaw=rotation.Yaw,vx=v.X,vy=v.Y,speed=math.sqrt(v.X*v.X+v.Y*v.Y),maxWalkSpeed=cm.MaxWalkSpeed,maxAcceleration=cm.MaxAcceleration,braking=cm.BrakingDecelerationWalking,groundFriction=cm.GroundFriction,orientToMovement=cm.bOrientRotationToMovement,controllerDesiredRotation=cm.bUseControllerDesiredRotation,useControllerYaw=actor.bUseControllerRotationYaw,feet={}}
 pcall(function() local capsule=actor.CapsuleComponent:K2_GetComponentLocation();local mesh=actor.Mesh:K2_GetComponentLocation();r.capsuleActorGap=math.sqrt((capsule.X-p.X)^2+(capsule.Y-p.Y)^2);r.meshCapsuleGapXY=math.sqrt((mesh.X-capsule.X)^2+(mesh.Y-capsule.Y)^2);r.pawnCollision=actor.CapsuleComponent:GetCollisionResponseToChannel(2) end)
 pcall(function() r.meshSettings={updateRateOptimization=actor.Mesh.bEnableUpdateRateOptimizations,visibilityTick=actor.Mesh.VisibilityBasedAnimTickOption,perBoneMotionBlur=actor.Mesh.bPerBoneMotionBlur} end)
 pcall(function() r.acceleration=cm:GetCurrentAcceleration();r.requestedVelocity={X=cm.RequestedVelocity.X,Y=cm.RequestedVelocity.Y,Z=cm.RequestedVelocity.Z};r.hasRequestedVelocity=cm.bHasRequestedVelocity end)
 pcall(function() r.cmVelocity={X=cm.Velocity.X,Y=cm.Velocity.Y,Z=cm.Velocity.Z} end)
 pcall(function() r.lastInput=actor:GetLastMovementInputVector() end)
 pcall(function() r.rootMotion=actor:IsPlayingRootMotion();r.gameInputMode=actor.PBZNBInput:IsGameInputMode() end)
 pcall(function() local d=actor:GetLocomotionDriverComponent():GetCurrentMoveInputWorldSpace();r.nativeMoveInput={X=d.X,Y=d.Y,Z=d.Z} end)
 pcall(function()
  local anim=actor.Mesh:GetAnimInstance();r.animClass=anim:GetClass():GetFullName()
  r.animation={gait=anim.Gait,hasVelocity=anim.bHasVelocity,hasAcceleration=anim.bHasAcceleration,displacementSpeed=anim.DisplacementSpeed};
  pcall(function() local a=anim.LocalAcceleration2D;r.animation.localAcceleration={X=a.X,Y=a.Y,Z=a.Z};r.animation.rateScale=actor.Mesh.GlobalAnimRateScale end)
  local m=anim:GetCurrentActiveMontage();r.montage=api.valid(m) and m:GetFName():ToString() or ""
 end)
 pcall(function() for _,name in ipairs(discoverBones(actor)) do
  local loc=actor.Mesh:GetSocketLocation(FName(name));r.feet[name]={x=loc.X,y=loc.Y,z=loc.Z}
  local yaw=math.rad(rotation.Yaw);local dx,dy=loc.X-p.X,loc.Y-p.Y
  r.feet[name].rootX=dx*math.cos(yaw)+dy*math.sin(yaw)
  r.feet[name].rootY=-dx*math.sin(yaw)+dy*math.cos(yaw)
  r.feet[name].rootZ=loc.Z-p.Z
 end end)
 return r
end
function q.discover()
 local pc,p=api.getPlayer1()
 local actions={}
 for _,a in ipairs(FindAllOf("InputAction") or {}) do
  local n=a:GetFName():ToString()
  if n:find("Move") or n:find("Walk") or n:find("Sprint") then
   actions[n]=a:GetFullName()
   q.actions[n]=a
   if n=="IA_JoystickMoveInput" then q.action=a elseif n=="IA_MoveInput" and not q.action then q.action=a end
  end
 end
 for _,s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
  if s:GetOuter().ControllerId==pc.Player.ControllerId then q.subsystem=s;break end
 end
 local driver={version=PB0_REMOTE_LOCOMOTION.version,mode=PB0_REMOTE_LOCOMOTION.mode}
 event("input_capabilities",{driver=driver,clock=api.game.motionClockInfo,actions=actions,subsystem=api.valid(q.subsystem),selected=q.action and q.action:GetFullName() or "",player=info(p),playerAbilities=abilities(p),ghostAbilities=abilities(api.net.ghost)})
 local out=assert(io.open(c.status,"w"));out:write(encode({ready=api.valid(q.subsystem) and api.valid(q.action),driver=driver,actions=actions}));out:close()
end
if PB0_REMOTE_LOCOMOTION then
 PB0_REMOTE_LOCOMOTION.onTrace=function(data)
  if q.phase~="setup" and q.phase~="postfix-forward" and q.phase~="postfix-stop" then event("motion_trace",data) end
 end
end
function q.phaseTo(name) q.phase=name;event("phase") end
function q.selectAction(name) q.action=assert(q.actions[name],"No such actual loaded input action");event("input_selected",{action=q.action:GetFullName()}) end
function q.move(x,y,seconds)
 if not (api.valid(q.action) and api.valid(q.subsystem)) then error("Actual movement InputAction and EnhancedInput subsystem required") end
 local _,p=api.getPlayer1()
 q.input={X=x,Y=y,Z=0};q.inputEnd=api.game.motionTimeMs()/1000+seconds;q.releaseUntil=q.inputEnd+.2
 event("enhanced_move",{x=x,y=y,seconds=seconds,action=q.action:GetFullName()})
end
function q.controlYaw(yaw)
 local pc=api.getPlayer1()
 pc:SetControlRotation({Pitch=-8,Yaw=yaw,Roll=0})
 event("control_yaw",{yaw=yaw})
end
function q.stop()
 q.input={X=0,Y=0,Z=0};q.inputEnd=0
 if api.valid(q.subsystem) and api.valid(q.action) then q.subsystem:InjectInputVectorForAction(q.action,q.input,{},{}) end
 q.stopped=true;log:close()
end
function q.inventory()
 local _,p=api.getPlayer1();local g=api.net.ghost
 local function inspect(obj)
  if not api.valid(obj) then return {} end
  local result={class=obj:GetClass():GetFullName(),functions={},fields={}}
  local cls=obj:GetClass();local depth=0
  while api.valid(cls) and depth<4 do
   cls:ForEachFunction(function(fn)
    local name=fn:GetFName():ToString()
    if name:lower():find("move") or name:lower():find("input") or name:lower():find("locomotion") then
     local params={};fn:ForEachProperty(function(prop) params[#params+1]=prop:GetFullName() end)
     result.functions[name]=params
    end
   end)
   cls:ForEachProperty(function(prop)
    local n=prop:GetFName():ToString();local lower=n:lower()
    if lower:find("speed") or lower:find("velocity") or lower:find("accel") or lower:find("input") or lower:find("locomotion") or lower:find("gait") then
     pcall(function()
      local v=obj[n]
      if type(v)=="number" or type(v)=="boolean" then result.fields[n]=v
      else local ok,x,y,z=pcall(function() return v.X,v.Y,v.Z end)
       if ok and type(x)=="number" then result.fields[n]={X=x,Y=y,Z=z} else result.fields[n]=tostring(v) end
      end
     end)
    end
   end)
   cls=cls:GetSuperStruct();depth=depth+1
  end
  return result
 end
 event("movement_inventory",{localProvider=inspect(p:GetLocomotionDriverComponent().MoveInputDataProvider),remoteProvider=inspect(g:GetLocomotionDriverComponent().MoveInputDataProvider),localDriver=inspect(p:GetLocomotionDriverComponent()),remoteDriver=inspect(g:GetLocomotionDriverComponent()),localActor=inspect(p),remoteActor=inspect(g),localMovement=inspect(p.CharacterMovement),remoteMovement=inspect(g.CharacterMovement),localInput=inspect(p.PBZNBInput),localAnim=inspect(p.Mesh:GetAnimInstance()),remoteInput=inspect(g.PBZNBInput),remoteAnim=inspect(g.Mesh:GetAnimInstance())})
end
function q.screenshot(path)
 local pc=api.getPlayer1()
 system:ExecuteConsoleCommand(pc,'HighResShot 1 filename="'+path..'"',pc)
end
LoopInGameThreadWithDelay(1,function()
 if q.stopped or base.stopped then return true end
 local ok,err=pcall(function()
  local pc,p=api.getPlayer1();if not api.valid(p) then return end
  local frame=system:GetFrameCount();if frame==q.lastFrame then return end;q.lastFrame=frame
  local now=api.gs():GetRealTimeSeconds(p)
  local inputNow=api.game.motionTimeMs()/1000
  if q.inputEnd and inputNow<=q.releaseUntil then
   local value=inputNow<q.inputEnd and q.input or {X=0,Y=0,Z=0}
   q.subsystem:InjectInputVectorForAction(q.action,value,{},{})
   if not q.lastInjected or q.lastInjected.X~=value.X or q.lastInjected.Y~=value.Y then
    q.lastInjected={X=value.X,Y=value.Y};event("input_injected",{x=value.X,y=value.Y})
   end
  end
  for _,subject in ipairs({"player","ghost"}) do
   local actor=subject=="player" and p or api.net.ghost
   if api.valid(actor) then
    local vel=actor:GetVelocity();local moving=math.sqrt(vel.X*vel.X+vel.Y*vel.Y)>3
    q.motion=q.motion or {}
    if q.motion[subject]~=moving then
     local pos=actor:K2_GetActorLocation()
     event("actor_motion",{who=subject,moving=moving,x=pos.X,y=pos.Y,vx=vel.X,vy=vel.Y})
     q.motion[subject]=moving
    end
   end
  end
  if not q.lastSample or now-q.lastSample>=.025 then
   q.lastSample=now
   local row={type="sample",phase=q.phase,time=now,wallClock=os.clock(),utcMs=api.game.motionUtcMs(),frame=frame,localSeq=api.net.seq,delta=api.gs():GetWorldDeltaSeconds(p),player=info(p),target=api.net.target,targetSeq=api.net.lastRemoteSeq,remoteDriver={driverMode=PB0_REMOTE_LOCOMOTION.mode,corrections=PB0_REMOTE_LOCOMOTION.corrections,correctionFrames=PB0_REMOTE_LOCOMOTION.correctionFrames,inputSent=PB0_REMOTE_LOCOMOTION.inputSent,inputReceived=PB0_REMOTE_LOCOMOTION.inputReceived,inputRejected=PB0_REMOTE_LOCOMOTION.inputRejected,watchdogStops=PB0_REMOTE_LOCOMOTION.watchdogStops,command=PB0_REMOTE_LOCOMOTION.command or {},render=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.render or {},accepted=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.accepted or 0,reordered=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.reordered or 0,skipped=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.skipped or 0,teleports=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.teleports or 0,rootMotionYields=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.rootMotionYields or 0,movement=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.movement or "",delay=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.delay or 0,gaitHook=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.gaitHook or false,gaitApplied=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.gaitApplied or nil,gaitError=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.gaitError or nil,mode=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.mode or "original",controlled=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.controlled or false,error=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.error or nil,input=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.input or {},gap=PB0_REMOTE_LOCOMOTION and PB0_REMOTE_LOCOMOTION.gap or 0}}
   if api.valid(api.net.ghost) then row.ghost=info(api.net.ghost) end
   log:write(encode(row),"\n")
  end
  if not q.lastFlush or now-q.lastFlush>.2 then log:flush();q.lastFlush=now end
 end)
 if not ok and not q.error then q.error=tostring(err);event("observer_error",{error=q.error}) end
 return false
end)
q.discover()
if c.inventory then local inventoryOk,inventoryError=pcall(q.inventory) if not inventoryOk then event("inventory_error",{error=tostring(inventoryError)}) end end
return q
