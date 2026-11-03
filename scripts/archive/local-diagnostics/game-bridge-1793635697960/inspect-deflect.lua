local f=assert(io.open("D:/pb0online/runs/native-deflect-inspection.txt","w"))
local _,p=PBZ.getPlayer1()
local function cls(c)
  f:write(c:GetFullName(),"\n")
  c:ForEachProperty(function(prop) f:write("  ",prop:GetFullName(),"\n") end)
  c:ForEachFunction(function(fn)
    local n=fn:GetFName():ToString()
    if n:find("Deflect") or n:find("Input") or n:find("ForceTrigger") or n:find("GetSelfResultData") then
      f:write("  ",fn:GetFullName(),"\n")
      fn:ForEachProperty(function(prop) f:write("    ",prop:GetFullName(),"\n") end)
    end
  end)
end
for _,name in ipairs({"SGameInputComponent","DeflectComponent","AbilityInputComponent"}) do
  for _,c in ipairs(FindAllOf(name) or {}) do
    local ok,o=pcall(function() return c:GetOwner() end)
    if ok and PBZ.valid(o) and o:GetAddress()==p:GetAddress() then
      cls(c:GetClass())
      if name=="DeflectComponent" then local ok,v=pcall(function() return c:GetSelfResultData() end) f:write("result ",tostring(ok)," ",tostring(v),"\n") if type(v)=="table" then for k,x in pairs(v) do f:write(tostring(k),"=",tostring(x),"\n") end end end
    end
  end
end
for _,c in ipairs(FindAllOf("Class") or {}) do local n=c:GetFName():ToString() if n:find("Deflect") and n:find("Input") then cls(c) end end
f:close()