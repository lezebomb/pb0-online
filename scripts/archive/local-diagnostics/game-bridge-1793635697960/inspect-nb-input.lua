local f=assert(io.open("D:/pb0online/runs/nb-input-dispatch.txt","w"))
local _,p=PBZ.getPlayer1()
local c=p.PBZNBInput
local cls=c:GetClass()
for level=1,4 do
 if not PBZ.valid(cls) then break end
 f:write(cls:GetFullName(),"\n")
 cls:ForEachFunction(function(fn) f:write(fn:GetFullName(),"\n") fn:ForEachProperty(function(prop) f:write("  ",prop:GetFullName(),"\n") end) end)
 cls:ForEachProperty(function(prop) f:write("  ",prop:GetFullName(),"\n") end)
 cls=cls:GetSuperStruct()
end
f:close()