-- Local recording director: relocate only the isolated test actors onto real floor and use a real CameraActor.
local api,probe,config=PBZ,PB0_TEST,PB0_QUALITY_CONFIG
local sys=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local scene={candidates={},active=false,index=0,rows={},lastLog=0}
local function vec(x,y,z) return {X=x,Y=y,Z=z} end
local function json(v)
 if type(v)=="number" then return tostring(v) elseif type(v)=="boolean" then return tostring(v) elseif type(v)=="table" then
 local a={};for k,x in pairs(v) do a[#a+1]='"'..k..'":'..json(x) end;return "{"..table.concat(a,",").."}"
 else return '"'..tostring(v):gsub("\\","\\\\"):gsub('"','\\"')..'"' end
end
local function write(name,data) local f=assert(io.open(config.root.."/"..name,"w"));f:write(json(data));f:close() end
local function trace(a,b)
 local pc,p=api.getPlayer1();local hit={}
 local ignores={p};if api.valid(api.net.ghost) then ignores[#ignores+1]=api.net.ghost end
 local yes=sys:LineTraceSingle(pc,a,b,0,true,ignores,0,hit,true,{R=0,G=0,B=0,A=0},{R=0,G=0,B=0,A=0},0)
 return yes,hit
end
local function floor(x,y,z)
 local yes,h=trace(vec(x,y,z+250),vec(x,y,z-600))
 if not yes or not h.ImpactPoint or h.ImpactNormal.Z<0.88 then return nil end
 return h.ImpactPoint.Z
end
local function clearance(camera,center,hh,actualA,actualB)
 local clear,total=0,0
 local actors=actualA and {actualA,actualB} or {vec(center.X-90,center.Y,center.Z),vec(center.X+90,center.Y,center.Z)}
 for _,actor in ipairs(actors) do
  for _,dz in ipairs({-hh+12,0,hh-5}) do
   for _,dy in ipairs({-22,22}) do
    total=total+1
    if not trace(camera,vec(actor.X,actor.Y+dy,actor.Z+dz)) then clear=clear+1 end
   end
  end
 end
 return clear,total
end
function scene.find()
 local _,p=api.getPlayer1();local a=p:K2_GetActorLocation()
 local hh=p.CapsuleComponent:GetScaledCapsuleHalfHeight()
 for _,radius in ipairs({350,700,1050,1400,0}) do
  for n=0,(radius==0 and 0 or 11) do
   local angle=n*math.pi/6
   local x,y=a.X+math.cos(angle)*radius,a.Y+math.sin(angle)*radius
   local z=floor(x,y,a.Z)
   if z then
    local flat=true
    for _,d in ipairs({{-180,0},{180,0},{0,-180},{0,180},{-180,-180},{180,180}}) do
     local h=floor(x+d[1],y+d[2],a.Z)
     if not h or math.abs(h-z)>25 then flat=false;break end
    end
    if flat then
     local center=vec(x,y,z+hh+2)
     for _,degrees in ipairs({270,90,225,315,45,135,0,180}) do
      local rad=math.rad(degrees)
      local camera=vec(x+math.cos(rad)*720,y+math.sin(rad)*720,center.Z+330)
      local clear,total=clearance(camera,center,hh)
      if clear==total then
       local side=math.abs(math.sin(rad))
       scene.candidates[#scene.candidates+1]={center=center,camera=camera,angle=rad,clear=clear,total=total,score=side*100-radius*.015,distanceFromOriginal=radius}
      end
     end
    end
   end
  end
 end
 table.sort(scene.candidates,function(a,b) return a.score>b.score end)
 write("scene-search.json",{count=#scene.candidates,original=a,candidates=scene.candidates})
 if #scene.candidates==0 then error("No flat, unobstructed two-player recording area found") end
 return scene.select(1)
end
local function aim(camera,target)
 local dx,dy,dz=target.X-camera.X,target.Y-camera.Y,target.Z-camera.Z
 return {Pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy))),Yaw=math.deg(math.atan(dy,dx)),Roll=0}
end
function scene.select(index)
 local c=assert(scene.candidates[index],"No such recording candidate")
 local pc,p=api.getPlayer1();local g=api.net.ghost
 scene.index=index;scene.selection=c;scene.active=false;scene.cameraDistance=c.distance or 720;scene.cameraHeight=c.height or 330
 p:K2_SetActorLocationAndRotation(vec(c.center.X-90,c.center.Y,c.center.Z),{Pitch=0,Yaw=0,Roll=0},false,{},true)
 g:K2_SetActorLocationAndRotation(vec(c.center.X+90,c.center.Y,c.center.Z),{Pitch=0,Yaw=180,Roll=0},false,{},true)
 p.CharacterMovement:StopMovementImmediately();g.CharacterMovement:StopMovementImmediately()
 if not api.valid(scene.camera) then
  local t={Rotation={X=0,Y=0,Z=0,W=1},Translation=c.camera,Scale3D=vec(1,1,1)}
  scene.camera=api.gs():BeginDeferredActorSpawnFromClass(pc,StaticFindObject("/Script/Engine.CameraActor"),t,2,nil,0)
  scene.camera=api.gs():FinishSpawningActor(scene.camera,t,0)
 end
 scene.camera:K2_SetActorLocationAndRotation(c.camera,aim(c.camera,c.center),false,{},true)
 scene.camera.CameraComponent:SetFieldOfView(55)
 pc:SetViewTargetWithBlend(scene.camera,0,0,0,false)
 scene.center=vec(c.center.X,c.center.Y,c.center.Z);scene.active=true
 write("scene-selection.json",{index=index,count=#scene.candidates,center=c.center,camera=c.camera,clear=c.clear,total=c.total})
 return c
end
function scene.boardwalk()
 local _,p=api.getPlayer1();local a=p:K2_GetActorLocation()
 scene.candidates={}
 for _,view in ipairs({{-90,360,430},{90,360,430},{-45,360,430},{45,360,430},{-135,360,430},{135,360,430},{-90,220,520},{90,220,520}}) do
  local rad=math.rad(view[1]);local center=vec(a.X+90,a.Y,a.Z)
  scene.candidates[#scene.candidates+1]={center=center,angle=rad,distance=view[2],height=view[3],camera=vec(center.X+math.cos(rad)*view[2],center.Y+math.sin(rad)*view[2],center.Z+view[3]),clear=-1,total=12}
 end
 write("scene-search.json",{count=#scene.candidates,original=a,candidates=scene.candidates})
 return scene.select(4)
end
function scene.restore()
 return scene.select(scene.index)
end
function scene.testCollision()
 local _,p=api.getPlayer1();local g=api.net.ghost
 local results={}
 for _,pair in ipairs({{p,g},{g,p}}) do
  local moving,other=pair[1],pair[2]
  local a,b=moving:K2_GetActorLocation(),other:K2_GetActorLocation()
  local dx,dy=b.X-a.X,b.Y-a.Y;local length=math.sqrt(dx*dx+dy*dy)
  local hit={}
  moving:K2_SetActorLocation(vec(b.X+dx/length*120,b.Y+dy/length*120,a.Z),true,hit,false)
  local actual=moving:K2_GetActorLocation();local actorName=""
  pcall(function() actorName=hit.HitObjectHandle.ReferenceObject:Get():GetFName():ToString() end)
  local radius=moving.CapsuleComponent:GetScaledCapsuleRadius()+other.CapsuleComponent:GetScaledCapsuleRadius()
  local gap=math.sqrt((actual.X-b.X)^2+(actual.Y-b.Y)^2)
  results[#results+1]={moving=moving:GetFName():ToString(),expectedBlocker=other:GetFName():ToString(),hitActor=actorName,blocking=hit.bBlockingHit==true,separation=gap,radiusSum=radius,stoppedBeforeOther=(actual.X-b.X)*dx+(actual.Y-b.Y)*dy<0,pass=hit.bBlockingHit==true and actorName==other:GetFName():ToString() and gap>=radius-2 and ((actual.X-b.X)*dx+(actual.Y-b.Y)*dy<0)}
  moving:K2_SetActorLocation(a,false,{},true)
 end
 write("body-collision-proof.json",{results=results,configured=PB0_PRESENTATION and PB0_PRESENTATION.configured or 0,allPassed=results[1].pass and results[2].pass})
end
local function bounds(location,camera,rotation,hh)
 local y,p=math.rad(rotation.Yaw),math.rad(rotation.Pitch)
 local forward=vec(math.cos(p)*math.cos(y),math.cos(p)*math.sin(y),math.sin(p))
 local right=vec(-math.sin(y),math.cos(y),0)
 local up=vec(-math.sin(p)*math.cos(y),-math.sin(p)*math.sin(y),math.cos(p))
 local out={minX=1,maxX=0,minY=1,maxY=0}
 for _,dz in ipairs({-hh,hh}) do
  for _,dx in ipairs({-40,40}) do
   local v=vec(location.X+dx-camera.X,location.Y-camera.Y,location.Z+dz-camera.Z)
   local depth=v.X*forward.X+v.Y*forward.Y+v.Z*forward.Z
   local horizontal=v.X*right.X+v.Y*right.Y+v.Z*right.Z
   local vertical=v.X*up.X+v.Y*up.Y+v.Z*up.Z
   local x=.5+horizontal/(2*depth*math.tan(math.rad(55/2)))
   local yy=.5-vertical/(2*depth*math.tan(math.rad(55/2))*9/16)
   out.minX=math.min(out.minX,x);out.maxX=math.max(out.maxX,x);out.minY=math.min(out.minY,yy);out.maxY=math.max(out.maxY,yy)
  end
 end
 return out
end
LoopInGameThreadWithDelay(16,function()
 if probe.stopped then scene.active=false;return true end
 if not scene.active then return false end
 local ok,err=pcall(function()
  local pc,p=api.getPlayer1();local g=api.net.ghost
  if not (api.valid(p) and api.valid(g)) then return end
  local a,b=p:K2_GetActorLocation(),g:K2_GetActorLocation()
  local now=api.gs():GetRealTimeSeconds(p)
  local dt=math.min(.05,now-(scene.lastTime or now-.016));scene.lastTime=now
  local target=vec((a.X+b.X)/2,(a.Y+b.Y)/2,(a.Z+b.Z)/2)
  local k=1-math.exp(-dt*7)
  for _,key in ipairs({"X","Y","Z"}) do scene.center[key]=scene.center[key]+(target[key]-scene.center[key])*k end
  local distance=math.max(scene.cameraDistance or 720,math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)*1.7)
  local angle=scene.selection.angle
  local camera=vec(scene.center.X+math.cos(angle)*distance,scene.center.Y+math.sin(angle)*distance,scene.center.Z+(scene.cameraHeight or 330))
  local rotation=aim(camera,scene.center)
  scene.camera:K2_SetActorLocationAndRotation(camera,rotation,false,{},true)
  if now-scene.lastLog>.2 then
   scene.lastLog=now
   local ph=p.CapsuleComponent:GetScaledCapsuleHalfHeight();local gh=g.CapsuleComponent:GetScaledCapsuleHalfHeight()
   local ba,bb=bounds(a,camera,rotation,ph),bounds(b,camera,rotation,gh)
   local visible=ba.minX>.08 and ba.maxX<.92 and ba.minY>.07 and ba.maxY<.93 and bb.minX>.08 and bb.maxX<.92 and bb.minY>.07 and bb.maxY<.93
   local clear,total=clearance(camera,vec((a.X+b.X)/2,(a.Y+b.Y)/2,(a.Z+b.Z)/2),ph,a,b)
   local record={time=now,phase=probe.phase,capture=PB0_QUALITY and PB0_QUALITY.capture or false,framed=visible,player=ba,ghost=bb,clear=clear,total=total,index=scene.index,distance=api.distance(a,b),minimumDistance=PB0_PRESENTATION and PB0_PRESENTATION.minimumDistance or 0,bodyCorrections=PB0_PRESENTATION and PB0_PRESENTATION.corrections or 0}
   local f=assert(io.open(config.root.."/scene-observations.jsonl","a"));f:write(json(record),"\n");f:close()
   write("scene-status.json",record)
  end
 end)
 if not ok then write("scene-error.json",{error=tostring(err)});scene.active=false end
 return false
end)
return scene