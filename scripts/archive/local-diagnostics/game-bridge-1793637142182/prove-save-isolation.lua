local f=assert(io.open("D:/pb0online/runs/save-isolation-guest.txt","w"))
local lib=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
f:write("project=",lib:GetProjectDirectory():ToString(),"\nsaved=",lib:GetProjectSavedDirectory():ToString(),"\n")
local _,p=PBZ.getPlayer1()
f:write("playerReady=",tostring(PBZ.valid(p)),"\n")
if PBZ.valid(p) then
 for _,s in ipairs(FindAllOf("PBZSaveLoadSubsystem") or {}) do
  if s:GetFullName():find("/Engine/Transient") then
   local ok,result=pcall(function() return s:ForceSave(0,{SaveSlotName="PB0IsolationProof_guest",bOverridePlayerCharacterTransform=false,bIsRevive=false,bIsOverrideLevelName=false,bSaveAdvanced=false,bShowSaveTip=false},nil) end)
   f:write("saveCall=",tostring(ok)," result=",tostring(result),"\n")
  end
 end
end
f:close()