-- Optional read-only frame/motion observer plus session-only resolution control.
local api,probe,c=PBZ,PB0_TEST,assert(PB0_QUALITY_CONFIG)
local system=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local viewport=StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
local q={capture=false,stage="setup",lastFrame=-1,buffer={},motion={},started=os.clock()}
local frames=assert(io.open(c.root.."/quality-frame-times.csv","w"))
frames:write("frame,realSeconds,worldDeltaMs,phase,capture,utcMs\n")
local motion=assert(io.open(c.root.."/quality-motion.csv","w"))
motion:write("realSeconds,phase,playerX,playerY,ghostX,ghostY,ghostZ,velocityX,velocityY,targetX,targetY,targetSeq,ghostWalks,ghostGliding,ghostBusy,rootMotion,montage\n")
local function context() return api.getPlayer1() end
function q.resolution(w,h)
 local pc=context()
 local settings=StaticFindObject("/Script/Engine.Default__GameUserSettings"):GetGameUserSettings()
 settings:SetFullscreenMode(2)
 settings:SetScreenResolution({X=w,Y=h})
 settings:SetVSyncEnabled(false)
 pcall(function() settings:SetFrameRateLimit(60) end)
 settings:ApplyResolutionSettings(false)
 settings:ConfirmVideoMode()
 system:ExecuteConsoleCommand(pc,"t.IdleWhenNotForeground 0",pc)
 system:ExecuteConsoleCommand(pc,"r.SetRes "..w.."x"..h.."w",pc)
 system:ExecuteConsoleCommand(pc,"r.ScreenPercentage 100",pc)
 system:ExecuteConsoleCommand(pc,"r.DynamicRes.OperationMode 0",pc)
 system:ExecuteConsoleCommand(pc,"t.MaxFPS 60",pc)
end
-- Session-only presentation diagnosis. The caller restores private settings afterwards.
function q.presentation(mode)
 local pc=context()
 local settings=StaticFindObject("/Script/Engine.Default__GameUserSettings"):GetGameUserSettings()
 local synced=mode~="legacy"
 settings:SetVSyncEnabled(synced)
 pcall(function() settings:SetFrameRateLimit(mode=="diagnostic60" and 60 or 0) end)
 pcall(function() settings:ApplyNonResolutionSettings() end)
 system:ExecuteConsoleCommand(pc,"r.VSync "..(synced and "1" or "0"),pc)
 system:ExecuteConsoleCommand(pc,"t.MaxFPS "..(mode=="diagnostic60" and "60" or "0"),pc)
 if synced then
  system:ExecuteConsoleCommand(pc,"r.Streamline.DLSSG.Enable 0",pc)
  system:ExecuteConsoleCommand(pc,"r.FidelityFX.FI.Enabled 0",pc)
 end
 local fg=StaticFindObject("/Script/StreamlineBlueprint.Default__StreamlineLibraryDLSSG")
 local fgMode=-1
 pcall(function() if api.valid(fg) then if synced then fg:SetDLSSGMode(0) end fgMode=fg:GetDLSSGMode() end end)
 local values={rVSync=-1,maxFPS=-1,dlssG=-1,fsrFI=-1}
 pcall(function() values.rVSync=system:GetConsoleVariableIntValue("r.VSync");values.maxFPS=system:GetConsoleVariableFloatValue("t.MaxFPS");values.dlssG=system:GetConsoleVariableIntValue("r.Streamline.DLSSG.Enable");values.fsrFI=system:GetConsoleVariableIntValue("r.FidelityFX.FI.Enabled") end)
 local out=assert(io.open(c.root.."/presentation-"..mode..".json","w"))
 out:write(string.format('{"mode":"%s","vsyncSetting":%s,"rVSync":%d,"maxFPS":%.3f,"dlssGCVar":%d,"fsrFICVar":%d,"dlssGLibraryPresent":%s,"dlssGMode":%d,"utcMs":%.0f}',mode,tostring(settings:IsVSyncEnabled()),values.rVSync,values.maxFPS,values.dlssG,values.fsrFI,tostring(api.valid(fg)),fgMode,api.game.motionUtcMs() or 0))
 out:close()
end
function q.mark(stage)
 q.stage=stage;q.markTime=nil;q.markFrame=nil
end
function q.flush()
 if #q.buffer>0 then frames:write(table.concat(q.buffer));q.buffer={};frames:flush() end
 if #q.motion>0 then motion:write(table.concat(q.motion));q.motion={};motion:flush() end
end
function q.finish()
 q.flush();q.stopped=true;frames:close();motion:close()
 local f=assert(io.open(c.root.."/quality-telemetry-done","w"));f:write("done");f:close()
end
LoopInGameThreadWithDelay(1,function()
 if q.stopped or probe.stopped then return true end
 local ok,err=pcall(function()
  local pc,p=context();if not api.valid(p) then return end
  local f=system:GetFrameCount()
  if f==q.lastFrame then return end
  q.lastFrame=f
  local gs=api.gs()
  local now=gs:GetRealTimeSeconds(p)
  local delta=gs:GetWorldDeltaSeconds(p)*1000
  q.buffer[#q.buffer+1]=string.format("%d,%.9f,%.6f,%s,%d,%.0f\n",f,now,delta,probe.phase,q.capture and 1 or 0,api.game.motionUtcMs() or 0)
  q.markTime=q.markTime or now;q.markFrame=q.markFrame or f
  if not q.lastMotion or now-q.lastMotion>=0.05 then
   q.lastMotion=now
   local g=api.net.ghost
   if api.valid(g) then
    local a,b,v,t=p:K2_GetActorLocation(),g:K2_GetActorLocation(),g:GetVelocity(),api.net.target or {}
    local rm,montage="",""
    pcall(function() rm=tostring(g:IsPlayingRootMotion()) end)
    pcall(function() local m=g.Mesh:GetAnimInstance():GetCurrentActiveMontage();if api.valid(m) then montage=m:GetFName():ToString() end end)
    q.motion[#q.motion+1]=string.format("%.9f,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%s,%s,%s,%s,%s\n",now,probe.phase,a.X,a.Y,b.X,b.Y,b.Z,v.X,v.Y,t.X or 0,t.Y or 0,api.net.lastRemoteSeq or 0,tostring(api.net.ghostWalks),tostring(api.net.ghostGliding),tostring(api.game.ghostBusy()),rm,montage)
   end
  end
  if not q.lastFlush or now-q.lastFlush>=0.5 then
   q.lastFlush=now;q.flush()
   local size=viewport:GetViewportSize(pc)
   local fps=(now-q.markTime)>0 and (f-q.markFrame)/(now-q.markTime) or 0
   local out=assert(io.open(c.root.."/quality-status.json","w"))
   out:write(string.format('{"ready":true,"width":%d,"height":%d,"fps":%.4f,"frame":%d,"realSeconds":%.9f,"stage":"%s"}',size.X,size.Y,fps,f,now,q.stage));out:close()
  end
 end)
 if not ok and not q.error then
  q.error=tostring(err)
  local e=io.open(c.root.."/quality-error.txt","w");if e then e:write(q.error);e:close() end
 end
 return false
end)
return q