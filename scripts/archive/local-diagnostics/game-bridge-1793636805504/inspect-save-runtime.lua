local f=assert(io.open("D:/pb0online/runs/save-runtime-objects.txt","w"))
local count=0
ForEachUObject(function(o)
 local name=o:GetFName():ToString()
 if name:find("Save") and not name:find("Icon") and not name:find("Widget") then
  local full=o:GetFullName()
  if full:find("/Script/") or full:find("/Engine/Transient") then
   f:write(full,"\n");count=count+1
   if full:find("^Class ") and (full:find("ProjectPBZ") or full:find("SaveGame")) then
    o:ForEachFunction(function(fn) f:write("  ",fn:GetFullName(),"\n") fn:ForEachProperty(function(p) f:write("    ",p:GetFullName(),"\n") end) end)
    o:ForEachProperty(function(p) f:write("  ",p:GetFullName(),"\n") end)
   end
  end
 end
end)
f:close()