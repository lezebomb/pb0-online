local f=assert(io.open("D:/pb0online/runs/videos/window-title-api.txt","w"))
ForEachUObject(function(o)
 local n=o:GetFName():ToString()
 if n:find("WindowTitle") then
  local full=o:GetFullName()
  if full:find("^Function ") then
   f:write(full,"\n")
   o:ForEachProperty(function(p) f:write("  ",p:GetFullName(),"\n") end)
  end
 end
end)
f:close()