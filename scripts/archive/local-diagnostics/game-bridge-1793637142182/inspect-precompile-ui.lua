local f=assert(io.open("D:/pb0online/runs/guest-precompile-ui-api.txt","w"))
for _,w in ipairs(FindAllOf("UserWidget") or {}) do
 if w:GetFullName():find("/Engine/Transient") and (w:GetFName():ToString():find("PrecompilePSO") or w:GetFName():ToString():find("SkipButton")) then
  f:write(w:GetFullName(),"\n")
  w:GetClass():ForEachFunction(function(fn) f:write(fn:GetFullName(),"\n") fn:ForEachProperty(function(p) f:write("  ",p:GetFullName(),"\n") end) end)
 end
end
f:close()