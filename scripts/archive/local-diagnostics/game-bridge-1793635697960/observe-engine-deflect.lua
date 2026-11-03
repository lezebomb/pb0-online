local f=assert(io.open("D:/pb0online/runs/deflect-engine-results.jsonl","w"))
PB0_ENGINE_RESULT_HOOK=select(1,RegisterHook("/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData",function() end,function(context,handle,tag,out)
 local ok,err=pcall(function()
  local result=out:get()
  local a,d=result.SourceAvatar,result.DefenderAvatar
  local _,p=PBZ.getPlayer1()
  if not ((PBZ.valid(a) and PBZ.valid(PBZ.net.ghost) and a:GetAddress()==PBZ.net.ghost:GetAddress()) or (PBZ.valid(d) and PBZ.valid(p) and d:GetAddress()==p:GetAddress())) then return end
  f:write('{"clock":',os.clock(),',"tag":"',tag:get().TagName:ToString(),'","result":"',result.DeflectResult.TagName:ToString(),'","hit":',tostring(result.IsHit),',"source":"',PBZ.valid(a) and a:GetFName():ToString() or "",'","defender":"',PBZ.valid(d) and d:GetFName():ToString() or "",'"}\n');f:flush()
 end)
 if not ok then PBZ.log("PB0 result observer: "..tostring(err)) end
end))
PB0_TEST.setPhase("parry-verdict")
local old=PBZ.game.playMove
PBZ.game.playMove=function(g,p,y)
 old(g,p,y)
 if g==PBZ.net.ghost and PB0_TEST.phase=="parry-verdict" then PBZ.game.after(0.25,PB0_TEST.parryAbility) end
end
return "engine verdict observer armed"