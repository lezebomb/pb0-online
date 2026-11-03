local f=assert(io.open("D:/pb0online/runs/save-live-instance.txt","w"))
for _,s in ipairs(FindAllOf("PBZSaveLoadSubsystem") or {}) do
 f:write(s:GetFullName(),"\n")
 if s:GetFullName():find("/Engine/Transient") then local ok,x=pcall(function() return s:GetContinueSlotName() end) f:write("continue ",tostring(ok)," ",tostring(x),"\n") end
end
local fn=StaticFindObject("/Script/ProjectPBZ.PBZSaveLoadSubsystem:ForceSave")
fn:ForEachProperty(function(p) local ok,s=pcall(function() return p:GetStruct() end) if ok and PBZ.valid(s) then f:write(s:GetFullName(),"\n") s:ForEachProperty(function(v) f:write(v:GetFullName(),"\n") end) end end)
f:close()