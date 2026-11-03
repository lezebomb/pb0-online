-- Same clear recording angle on the real local source and its real remote clone; no actor repositioning.
local api,base,c=PBZ,PB0_TEST,PB0_LOCO_CONFIG
local subject=c.subject=="remote" and api.net.ghost or select(2,api.getPlayer1())
local pc=api.getPlayer1()
local a=subject:K2_GetActorLocation()
local function v(x,y,z) return {X=x,Y=y,Z=z} end
local pos=v(a.X+300,a.Y+300,a.Z+330)
local transform={Rotation={X=0,Y=0,Z=0,W=1},Translation=pos,Scale3D=v(1,1,1)}
local cam=api.gs():BeginDeferredActorSpawnFromClass(pc,StaticFindObject("/Script/Engine.CameraActor"),transform,2,nil,0)
cam=api.gs():FinishSpawningActor(cam,transform,0)
cam.CameraComponent:SetFieldOfView(55)
pc:SetViewTargetWithBlend(cam,0,0,0,false)
local center=v(a.X,a.Y,a.Z)
local last
LoopInGameThreadWithDelay(16,function()
 if base.stopped then return true end
 local s=c.subject=="remote" and api.net.ghost or select(2,api.getPlayer1())
 if not api.valid(s) then return false end
 if pc:GetViewTarget():GetAddress()~=cam:GetAddress() then pc:SetViewTargetWithBlend(cam,0,0,0,false) end
 local loc=s:K2_GetActorLocation();local now=api.gs():GetRealTimeSeconds(s)
 local dt=math.min(.05,now-(last or now-.016));last=now
 local k=1-math.exp(-dt*8)
 for _,key in ipairs({"X","Y","Z"}) do center[key]=center[key]+(loc[key]-center[key])*k end
 cam:K2_SetActorLocationAndRotation(v(center.X+300,center.Y+300,center.Z+330),{Pitch=-math.deg(math.atan(310,math.sqrt(180000))),Yaw=-135+(c.presentationPan and 3*math.sin(now*1.8) or 0),Roll=0},false,{},true)
 return false
end)
return cam