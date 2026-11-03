local f=assert(io.open("D:/pb0online/runs/guest-loading-ui.txt","w"))
for _,w in ipairs(FindAllOf("UserWidget") or {}) do
 if w:GetFullName():find("/Engine/Transient") then
  local ok,visible=pcall(function() return w:IsVisible() end)
  if ok and visible then f:write(w:GetFullName(),"\n") end
 end
end
for _,s in ipairs(FindAllOf("PBZSaveLoadSubsystem") or {}) do if s:GetFullName():find("/Engine/Transient") then f:write("continue=",s:GetContinueSlotName():ToString(),"\n") end end
f:close()