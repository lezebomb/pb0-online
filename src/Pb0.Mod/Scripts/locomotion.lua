-- Input commands use the existing signed/reliable event channel. P snapshots remain authoritative.
return function(api)
 local system=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
 local mathLib=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
 local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
 local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e15 end
 -- Each process calibrates its monotonic clock once against the same computer clock.
 -- Subsequent trace times never follow wall-clock steps; no subtraction of unrelated os.clock epochs.
 local best
 for _=1,7 do
  local first=os.clock()
  local d=mathLib:UtcNow();local utc=mathLib:ToUnixTimestamp(d)*1000+mathLib:GetMillisecond(d)
  local last=os.clock();local span=(last-first)*1000
  if not best or span<best.span then best={span=span,offset=utc-(first+last)*500,utc=utc} end
 end
 api.game.motionClockInfo={kind="shared-UTC-anchored-monotonic",uncertaintyMs=best.span*.5+1,anchorUtcMs=best.utc}
 api.game.motionTimeMs=function() return best.offset+os.clock()*1000 end
 api.game.motionUtcMs=api.game.motionTimeMs -- Compatibility name in existing recording probes.
 api.game.motionFrame=function() return system:GetFrameCount() end
 local state={version=6,mode="input-simulation-native-cmc",enabled=true,delay=0,buffer={},accepted=0,reordered=0,duplicates=0,skipped=0,teleports=0,rootMotionYields=0,updates=0,stops=0,corrections=0,correctionFrames=0,watchdogStops=0,inputSent=0,inputReceived=0,inputRejected=0,sendSeq=0}
 PB0_REMOTE_LOCOMOTION=state
 local nowMs=api.game.motionTimeMs
 local function trace(kind,data)
  if state.onTrace then data=data or {};data.kind=kind;data.utcMs=nowMs();data.mono=os.clock();state.onTrace(data) end
 end
 local function norm(x,y) return math.sqrt(x*x+y*y) end
 local function readInput(p)
  local cm=p.CharacterMovement;local input=p:GetLastMovementInputVector()
  local effective=norm(input.X or 0,input.Y or 0)
  local ok,raw=pcall(function() return p:GetLocomotionDriverComponent():GetCurrentMoveInputWorldSpace() end)
  if ok then
   local amount=norm(raw.X or 0,raw.Y or 0)
   -- The native driver uses the raw stick for gait selection, then normalizes walking input.
   -- Observed 0.0667 raw world input becomes magnitude 1 on the real walking Character.
   if amount>.02 then input={X=raw.X/amount*(effective>.02 and effective or 1),Y=raw.Y/amount*(effective>.02 and effective or 1)}
   else input={X=0,Y=0} end
  end
  local v=p:GetVelocity();local a=cm:GetCurrentAcceleration();local ix,iy=input.X or 0,input.Y or 0
  if not (finite(ix) and finite(iy)) then ix,iy=0,0 end
  local length=norm(ix,iy);if length>1 then ix,iy=ix/length,iy/length end
  if norm(ix,iy)<.02 then ix,iy=0,0 end
  local max=cm.MaxWalkSpeed
  if norm(v.X,v.Y)<3 and norm(ix,iy)>.02 then max=state.lastMovingMax or 100
  elseif norm(v.X,v.Y)>3 then state.lastMovingMax=max end
  local gait=1;pcall(function() gait=p.Mesh:GetAnimInstance().Gait end)
  local p0=p:K2_GetActorLocation()
  local frame=system:GetFrameCount();local stamp=nowMs()
  if frame~=state.velocityFrame then
   local old=state.velocitySample;local elapsed=old and (stamp-old.ms)/1000 or 0
   if old and elapsed>.001 and elapsed<.15 then
    state.physAX=clamp((v.X-old.X)/elapsed,-3000,3000);state.physAY=clamp((v.Y-old.Y)/elapsed,-3000,3000)
   end
   state.velocitySample={X=v.X,Y=v.Y,ms=stamp};state.velocityFrame=frame
  end
  return {ix=ix,iy=iy,yaw=p:K2_GetActorRotation().Yaw,max=clamp(max,1,1500),accel=clamp(cm.MaxAcceleration,1,3000),mode=cm.MovementMode,gait=gait,vx=v.X,vy=v.Y,vz=v.Z,ax=a.X,ay=a.Y,active=norm(v.X,v.Y)>3,bx=state.physAX or 0,by=state.physAY or 0,root=p:IsPlayingRootMotion(),X=p0.X,Y=p0.Y,Z=p0.Z}
 end
 api.game.motionInputState=readInput
 api.game.motionInputChangedMs=function() return state.changedMs or nowMs() end
 local function commandChanged(a,b)
  return not a or norm(a.ix-b.ix,a.iy-b.iy)>.04 or a.mode~=b.mode or a.active~=b.active or a.root~=b.root or (norm(a.ax,a.ay)>2)~=(norm(b.ax,b.ay)>2) or math.abs(a.max-b.max)>25 or math.abs((a.yaw-b.yaw+540)%360-180)>8
 end
 api.game.publishMotionInput=function()
  if not state.enabled or not api.net.enabled then return end
  local frame=system:GetFrameCount();if frame==state.sendFrame then return end;state.sendFrame=frame
  local _,p=api.getPlayer1();if not api.valid(p) then return end
  local input=readInput(p);local now=nowMs()
  local changed=commandChanged(state.localInput,input)
  if changed then
   state.changedMs=now;state.localInput=input;state.stopRepeats=norm(input.ix,input.iy)<.02 and 2 or 0
   trace("input_changed",{inputMs=now,ix=input.ix,iy=input.iy,mode=input.mode,yaw=input.yaw})
  end
  local repeatStop=state.stopRepeats and state.stopRepeats>0 and now-(state.lastSendMs or 0)>=30
  if changed or repeatStop or now-(state.lastSendMs or 0)>=100 then
   state.sendSeq=state.sendSeq+1
   local text=string.format("3 %d %.3f %.3f %.5f %.5f %.2f %.3f %.3f %d %d %.3f %.3f %.3f %.3f %.3f %.3f %.3f %d",
    state.sendSeq,now,state.changedMs or now,input.ix,input.iy,input.yaw,input.max,input.accel,input.mode,input.gait,input.vx,input.vy,input.vz,input.ax,input.ay,input.bx,input.by,input.root and 1 or 0)
   api.coop.sendEvent("W",text)
   state.inputSent=state.inputSent+1;state.lastSendMs=now
   if repeatStop and not changed then state.stopRepeats=state.stopRepeats-1 end
   trace("input_sent",{seq=state.sendSeq,inputMs=state.changedMs,sentMs=now,ix=input.ix,iy=input.iy})
  end
 end
 local function acceptCommand(c,origin)
  local now=nowMs()
  if not (finite(c.sentMs) and finite(c.ix) and finite(c.iy) and finite(c.max) and finite(c.accel) and finite(c.yaw) and finite(c.mode) and finite(c.gait) and finite(c.ax) and finite(c.ay) and finite(c.bx) and finite(c.by)) then return false end
  if state.rejectBeforeMs and c.sentMs<state.rejectBeforeMs then return false end
  if c.sentMs>now+25 or now-c.sentMs>250 or norm(c.ix,c.iy)>1.01 or c.max<1 or c.max>1500 or c.accel<1 or c.accel>3000 then return false end
  if state.command and c.sentMs<=state.command.sentMs then return false end
  c.receivedMs=now;c.origin=origin
  state.command=c;state.inputReceived=state.inputReceived+1
  trace("input_received",{seq=c.seq,inputMs=c.inputMs,sentMs=c.sentMs,ix=c.ix,iy=c.iy,origin=origin})
  return true
 end
 api.coop.handlers.W=function(rest)
  local f={};for word in rest:gmatch("%S+") do f[#f+1]=tonumber(word) end
  if #f~=19 or f[1]~=3 then state.inputRejected=state.inputRejected+1;return end
  if state.eventSession~=api.net.inSession then state.eventSession=api.net.inSession;state.eventSeq=nil;state.command=nil end
  if state.eventSeq and f[2]<=state.eventSeq then state.inputRejected=state.inputRejected+1;return end
  trace("input_event_arrived",{seq=f[2],sentMs=f[3],inputMs=f[4],ix=f[5],iy=f[6]})
  local c={seq=f[2],sentMs=f[3],inputMs=f[4],ix=f[5],iy=f[6],yaw=f[7],max=f[8],accel=f[9],mode=f[10],gait=f[11],vx=f[12],vy=f[13],vz=f[14],ax=f[15],ay=f[16],bx=f[17],by=f[18],root=f[19]==1}
  if acceptCommand(c,"event") then state.eventSeq=f[2] else state.inputRejected=state.inputRejected+1 end
 end
 api.game.acceptRemoteMotion=function(t,seq)
  if state.rejectBeforeMs and finite(t.SourceUtcMs) and t.SourceUtcMs<state.rejectBeforeMs then return false end
  if not api.net.lastRemoteSeq or state.session~=api.net.inSession then
   state.sourceSeq=nil;state.sourceTime=nil;state.session=api.net.inSession;state.authority=nil;state.correcting=false
  end
  if state.sourceSeq and seq<=state.sourceSeq then state.reordered=state.reordered+1;return false end
  if finite(t.SourceTime) and state.sourceTime and t.SourceTime<=state.sourceTime then state.reordered=state.reordered+1;return false end
  local previous=state.authority
  if previous then
   state.skipped=state.skipped+math.max(0,seq-state.sourceSeq-1)
   local dt=finite(t.SourceUtcMs) and finite(previous.SourceUtcMs) and (t.SourceUtcMs-previous.SourceUtcMs)/1000 or .033
   local jump=math.sqrt((t.X-previous.X)^2+(t.Y-previous.Y)^2+(t.Z-previous.Z)^2)
   if jump>600 and (dt<.5 or jump/math.max(dt,.001)>2500) then state.pendingTeleport=t end
  end
  state.authority=t;state.sourceSeq=seq;state.sourceTime=t.SourceTime
  state.accepted=state.accepted+1;state.updates=state.updates+1
  trace("received",{seq=seq,sourceUtcMs=t.SourceUtcMs,X=t.X,Y=t.Y,vx=t.VelX,vy=t.VelY})
  if finite(t.SourceUtcMs) and finite(t.InputX) and finite(t.InputY) then
   acceptCommand({seq=seq,sentMs=t.SourceUtcMs,inputMs=t.InputChangedMs or t.SourceUtcMs,ix=t.InputX,iy=t.InputY,yaw=t.Yaw,max=t.WalkMax,accel=t.AccelMax,mode=t.MoveMode or 1,gait=t.Gait,vx=t.VelX,vy=t.VelY,vz=t.VelZ or 0,ax=t.AccelX or 0,ay=t.AccelY or 0,bx=t.PhysAccelX or 0,by=t.PhysAccelY or 0,root=t.SourceRootMotion==1},"snapshot")
  end
  return true
 end
 local function ensureGaitHook()
  if state.gaitHook then return end
  local ok,pre,post=pcall(RegisterHook,"/HuaShira/Characters/Hero/Hero_Hun/Animation/PBZ_ABP_Hun_Base.PBZ_ABP_Hun_Base_C:UpdateLocomotionState",function(context)
   local good,err=pcall(function()
    if not state.enabled or not api.net.enabled then return end
    local anim=context:get();local owner=anim:TryGetPawnOwner();local g=api.net.ghost
    if not (api.valid(owner) and api.valid(g) and owner:GetAddress()==g:GetAddress()) then return end
    if g:IsPlayingRootMotion() or (api.game.ghostBusy and api.game.ghostBusy(g)) then return end
    local gait=state.render and state.render.Gait
    if gait and gait>=0 and gait<=2 then anim.Gait=gait;state.gaitApplied=gait;state.gaitUpdates=(state.gaitUpdates or 0)+1 end
   end)
   if not good then state.gaitError=tostring(err) end
  end)
  state.gaitHook=ok
  if ok then state.gaitHookPre,state.gaitHookPost=pre,post else state.gaitError=tostring(pre) end
 end
 api.game.steerRemote=function(net)
  if not state.enabled or not net.ghostWalks or net.ghostHidden or net.ghostGliding or net.partnerGone then return false end
  local g,t=net.ghost,net.target;if not (api.valid(g) and t) then return false end
  local frame=system:GetFrameCount();if frame==state.lastFrame then return true end;state.lastFrame=frame
  local now=nowMs();local dt=clamp((now-(state.tickMs or now-16))/1000,.001,.05);state.tickMs=now
  local cm=g.CharacterMovement;local c=state.command
  if not c then return t.InputX~=nil end -- Wait for a fresh command; legacy peers retain upstream behavior.
  ensureGaitHook()
  if state.actor~=g:GetAddress() then
   state.actor=g:GetAddress();state.correctX,state.correctY=0,0
   local _,p=api.getPlayer1()
   if api.valid(p) then pcall(function() cm.TurnPivotBoneInterpSpeed=p.CharacterMovement.TurnPivotBoneInterpSpeed end) end
  end
  if (api.game.ghostBusy and api.game.ghostBusy(g)) or g:IsPlayingRootMotion() or c.root then
   state.rootMotionYields=state.rootMotionYields+1;cm.bHasRequestedVelocity=false;state.correcting=false
   return true
  end
  if state.pendingTeleport then
   local s=state.pendingTeleport;g:K2_SetActorLocationAndRotation({X=s.X,Y=s.Y,Z=s.Z},{Pitch=0,Yaw=s.Yaw,Roll=0},false,{},true)
   cm:StopMovementImmediately();state.teleports=state.teleports+1;state.pendingTeleport=nil
  end
  if c.mode~=1 then return false end
  local p=g:K2_GetActorLocation();local age=finite(t.SourceUtcMs) and clamp((now-t.SourceUtcMs)/1000,0,.08) or 0
  local predicted={X=t.X+(t.VelX or 0)*age,Y=t.Y+(t.VelY or 0)*age,Z=t.Z,Yaw=c.yaw,Gait=c.gait,sourceUtcMs=t.SourceUtcMs,predictionMs=age*1000,InputX=c.ix,InputY=c.iy,sourceSpeed=norm(c.vx or 0,c.vy or 0)}
  state.render=predicted
  local ex,ey=predicted.X-p.X,predicted.Y-p.Y;local gap=norm(ex,ey);state.gap=gap
  local moving=norm(c.ix,c.iy)>.02
  if now-c.sentMs>250 then
   moving=false
   if not state.timedOut then state.watchdogStops=state.watchdogStops+1;state.timedOut=true end
  else state.timedOut=false end
  if state.appliedMs~=c.sentMs then
   state.appliedMs=c.sentMs;state.appliedInputSeq=c.seq
   trace("input_applied",{seq=c.seq,inputMs=c.inputMs,sentMs=c.sentMs,receivedMs=c.receivedMs,ix=c.ix,iy=c.iy,origin=c.origin,gap=gap})
  end
  cm.MaxWalkSpeed=c.max;cm.MaxAcceleration=c.accel
  if moving then
   state.movement=c.gait==2 and "sprint" or c.gait==1 and "run" or "walk"
   if not state.correcting and gap>8 then state.correcting=true;state.corrections=state.corrections+1
   elseif state.correcting and gap<4 then state.correcting=false end
   local cx,cy=0,0
   if state.correcting then
    local length=norm(ex,ey);local bound=math.min(c.max*.3,15+math.max(0,gap-12))
    local k=math.min(1,bound/math.max(.001,length*1.5))
    cx,cy=ex*1.5*k,ey*1.5*k;state.correctionFrames=state.correctionFrames+1
   end
   local k=1-math.exp(-dt/.12)
   state.correctX=(state.correctX or 0)+(cx-(state.correctX or 0))*k
   state.correctY=(state.correctY or 0)+(cy-(state.correctY or 0))*k
   -- Replay the native driver's applied acceleration, not raw intent at an unfiltered speed cap.
   -- Between packets this is a continuous acceleration/velocity model; positions only reconcile drift.
   local horizon=clamp((now-c.sentMs)/1000,0,.12)
   local vx,vy=c.vx or 0,c.vy or 0
   local acceleration=norm(c.ax or 0,c.ay or 0)
   local max=math.max(c.max,norm(vx,vy))
   local px,py=vx+(c.ax or 0)*horizon,vy+(c.ay or 0)*horizon
   local speed=norm(px,py)
   if speed>max then px,py=px*max/speed,py*max/speed end
   state.simVX,state.simVY=px+state.correctX,py+state.correctY
   -- Native request movement keeps the physical capsule and mesh on one swept Character.
   cm.RequestedVelocity={X=state.simVX,Y=state.simVY,Z=0}
   cm.bRequestedMoveWithMaxSpeed=false;cm.bRequestedMoveUseAcceleration=false;cm.bHasRequestedVelocity=true
   local magnitude=norm(c.ax or 0,c.ay or 0)
   if magnitude>2 then g:AddMovementInput({X=c.ax/magnitude,Y=c.ay/magnitude,Z=0},clamp(magnitude/c.accel,0,1),false) end
   state.stopped=false;state.driveSpeed=norm(state.simVX,state.simVY)
  else
   state.movement="idle";state.correcting=false;state.correctX,state.correctY=0,0
   g:ConsumeMovementInputVector()
   -- Input acceleration is zero during braking; replicate the measured physical deceleration.
   local speed=norm(c.vx or 0,c.vy or 0)
   local decel=speed>2 and clamp(-((c.vx or 0)*(c.bx or 0)+(c.vy or 0)*(c.by or 0))/speed,0,3000) or 0
   local horizon=clamp((now-c.sentMs)/1000,0,.12)
   local remaining=math.max(0,speed-decel*horizon)
   if not state.timedOut and speed>2 and remaining>2 then
    cm.RequestedVelocity={X=c.vx/speed*remaining,Y=c.vy/speed*remaining,Z=0}
    cm.bRequestedMoveWithMaxSpeed=false;cm.bRequestedMoveUseAcceleration=false;cm.bHasRequestedVelocity=true
    state.stopped=false;state.movement="braking"
   else
    cm.bHasRequestedVelocity=false
    if not state.stopped then cm:StopMovementImmediately();state.stops=state.stops+1 end
    state.stopped=true
   end
   state.driveSpeed=0
  end
  return true
 end
 state.resetAfterAlignment=function()
  state.command=nil;state.authority=nil;state.pendingTeleport=nil;state.correcting=false
  state.correctX,state.correctY=0,0;state.rejectBeforeMs=nowMs()-2
  local g=api.net.ghost
  if api.valid(g) then g.CharacterMovement.bHasRequestedVelocity=false;g:ConsumeMovementInputVector();g.CharacterMovement:StopMovementImmediately() end
 end
 return state
end
