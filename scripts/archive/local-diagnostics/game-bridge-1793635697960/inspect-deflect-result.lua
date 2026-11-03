local f=assert(io.open("D:/pb0online/runs/deflect-consume-signature.txt","w"))
for _,path in ipairs({"/Script/PBZDeflectSystem.DeflectComponent:ConsumeReceivedFrame","/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData"}) do
 local fn=StaticFindObject(path) f:write(fn:GetFullName(),"\n")
 fn:ForEachProperty(function(prop) f:write(prop:GetFullName(),"\n") local ok,s=pcall(function() return prop:GetStruct() end) if ok and PBZ.valid(s) then f:write(s:GetFullName(),"\n") s:ForEachProperty(function(p) f:write("  ",p:GetFullName(),"\n") end) end end)
end
f:close()