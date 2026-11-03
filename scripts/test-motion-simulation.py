"""Boundary tests for the actual Lua motion adapter (requires lupa)."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runs/lua-runtime'))
from lupa import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
clock,frame=1,1
os.clock=function() return clock end
sys={GetFrameCount=function() return frame end}
mathlib={UtcNow=function() return clock end,ToUnixTimestamp=function(_,t) return 1700000000+math.floor(t) end,GetMillisecond=function(_,t) return math.floor(t*1000)%1000 end}
StaticFindObject=function(path) return path:find("KismetMath") and mathlib or sys end
RegisterHook=function() return 1,2 end
cm={Velocity={X=0,Y=0,Z=0},MaxWalkSpeed=100,MaxAcceleration=500,MovementMode=1,GroundFriction=5}
function cm:GetCurrentAcceleration() return {X=500,Y=0,Z=0} end
function cm:StopMovementImmediately() self.Velocity={X=0,Y=0,Z=0} end
g={CharacterMovement=cm,pos={X=0,Y=0,Z=0},adds=0}
function g:GetAddress() return 1 end
function g:K2_GetActorLocation() return self.pos end
function g:K2_GetActorRotation() return {Yaw=0} end
function g:K2_SetActorLocationAndRotation(p,r) self.pos=p end
function g:GetVelocity() return cm.Velocity end
function g:GetLastMovementInputVector() return {X=1,Y=0,Z=0} end
function g:GetLocomotionDriverComponent() return {GetCurrentMoveInputWorldSpace=function() return {X=.06666667,Y=0,Z=0} end} end
g.Mesh={GetAnimInstance=function() return {Gait=0} end}
function g:IsPlayingRootMotion() return self.root or false end
function g:ConsumeMovementInputVector() end
function g:AddMovementInput(v,s) self.adds=self.adds+1;self.input=v;self.amount=s end
sent={}
api={net={enabled=true,ghostWalks=true,ghost=g,inSession="peer1"},game={},coop={handlers={},sendEvent=function(kind,text) sent[#sent+1]={kind,text} end},valid=function(x) return x~=nil end,getPlayer1=function() return nil,g end}
""")
module=lua.eval('function(s) return assert(load(s))() end')((root/'src/Pb0.Mod/Scripts/locomotion.lua').read_text(encoding='utf-8-sig'))
module(lua.globals().api)
lua.execute("""
local state=PB0_REMOTE_LOCOMOTION
assert(not state.singleMotion,"regressed movement experiment must stay off by default")
assert(api.game.motionClockInfo.uncertaintyMs<=2)
api.game.publishMotionInput()
assert(#sent==1 and sent[1][1]=="W")
assert(math.abs(api.game.motionInputState(g).ix-1)<.0001,"raw stick must not scale walking speed down")
local stamp=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 1 %.3f %.3f 1 0 0 100 500 1 0 0 0 0 500 0 0 0 0",stamp,stamp))
assert(state.inputReceived==1)
local t={X=0,Y=0,Z=0,Yaw=0,Speed=0,SourceUtcMs=stamp,SourceTime=clock,VelX=0,VelY=0,InputX=1,InputY=0,WalkMax=100,AccelMax=500,Gait=0,MoveMode=1,AccelX=500,AccelY=0}
assert(api.game.acceptRemoteMotion(t,1));api.net.target=t;api.net.lastRemoteSeq=1
api.game.steerRemote(api.net)
assert(g.adds==1,"default retains the previously verified movement path")
state.singleMotion=true;frame=frame+1;api.game.steerRemote(api.net)
assert(g.adds==1 and cm.bHasRequestedVelocity,"experimental request cannot add a second physical input")
local n=g.adds;api.game.steerRemote(api.net);assert(g.adds==n,"one update per engine frame")
clock=clock+.02;frame=frame+1
local fresh=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 2 %.3f %.3f 0 0 0 100 500 1 0 0 0 0 0 0 0 0 0",fresh,fresh))
api.coop.handlers.W(string.format("3 1 %.3f %.3f 1 0 0 100 500 1 0 0 0 0 500 0 0 0 0",stamp,stamp))
assert(state.command.ix==0,"old move must not undo stop")
api.game.steerRemote(api.net);assert(not cm.bHasRequestedVelocity)
clock=clock+.02;frame=frame+1;fresh=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 3 %.3f %.3f 1 0 0 100 500 1 0 0 0 0 500 0 0 0 0",fresh,fresh))
g.root=true;api.game.steerRemote(api.net);assert(state.rootMotionYields==1 and not cm.bHasRequestedVelocity)
g.root=false;clock=clock+.3;frame=frame+1
api.game.steerRemote(api.net);assert(state.watchdogStops==1 and not cm.bHasRequestedVelocity)
clock=clock+.01;frame=frame+1;fresh=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 4 %.3f %.3f 0 0 0 100 500 1 0 60 0 0 0 0 -400 0 0",fresh,fresh))
clock=clock+.05;frame=frame+1
api.game.steerRemote(api.net)
assert(cm.bHasRequestedVelocity and math.abs(cm.RequestedVelocity.X-40)<.01,"native brake tail must not be cut short")
fresh=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 5 %.3f %.3f 0 0 0 100 500 1 0 0 0 0 0 0 0 0 0",fresh,fresh))
frame=frame+1;api.game.steerRemote(api.net);assert(not cm.bHasRequestedVelocity)
clock=clock+.01;frame=frame+1;fresh=api.game.motionTimeMs()
api.coop.handlers.W(string.format("3 6 %.3f %.3f 1 0 0 100 500 1 0 100 0 0 500 0 0 0 1",fresh,fresh))
local yielded=state.rootMotionYields;api.game.steerRemote(api.net)
assert(state.rootMotionYields==yielded+1 and not cm.bHasRequestedVelocity,"source Root Motion must wait for native ability")
assert(state.teleports==0,"ordinary walking cannot teleport")
assert(not api.game.acceptRemoteMotion(t,1),"stale snapshot rejected")
""")
print('PASS: clock calibration, native input normalization, event sequencing, frame guard, stale-stop protection, Root Motion yield, watchdog and no walking teleports')
