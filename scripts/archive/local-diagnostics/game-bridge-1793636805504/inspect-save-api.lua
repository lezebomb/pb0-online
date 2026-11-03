local f=assert(io.open("D:/pb0online/runs/save-api-types.txt","w"))
for _,c in ipairs(FindAllOf("Class") or {}) do
 local n=c:GetFName():ToString()
 if (n:find("SaveGame") or n:find("SaveManager")) and not n:find("REINST") then
  f:write(c:GetFullName(),"\n")
  c:ForEachFunction(function(fn) local x=fn:GetFName():ToString() if x:find("Save") or x:find("Path") or x:find("Slot") then f:write("  ",fn:GetFullName(),"\n") fn:ForEachProperty(function(p) f:write("    ",p:GetFullName(),"\n") end) end end)
  c:ForEachProperty(function(p) local x=p:GetFName():ToString() if x:find("Path") or x:find("Slot") or x:find("Directory") then f:write("  ",p:GetFullName(),"\n") end end)
 end
end
f:close()