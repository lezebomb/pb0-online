local f=assert(io.open("D:/pb0online/runs/save-isolation-host.txt","w"))
local lib=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
f:write("project=",lib:GetProjectDirectory():ToString(),"\nsaved=",lib:GetProjectSavedDirectory():ToString(),"\n")
for _,s in ipairs(FindAllOf("PBZSaveLoadSubsystem") or {}) do
 if s:GetFullName():find("/Engine/Transient") then
  f:write("continue=",s:GetContinueSlotName():ToString(),"\n")
  local ok,result=pcall(function() return s:ForceSave(0,{SaveSlotName="PB0IsolationProof_host",bOverridePlayerCharacterTransform=false,bIsRevive=false,bIsOverrideLevelName=false,bSaveAdvanced=false,bShowSaveTip=false},nil) end)
  f:write("saveCall=",tostring(ok)," result=",tostring(result),"\n")
 end
end
f:close()