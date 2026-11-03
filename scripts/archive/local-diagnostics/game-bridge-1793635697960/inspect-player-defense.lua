local f=assert(io.open("D:/pb0online/runs/player-defense-dispatch.txt","w"))
local pc,p=PBZ.getPlayer1()
for _,obj in ipairs({p,pc}) do
  local cls=obj:GetClass()
  for level=1,8 do
    if not PBZ.valid(cls) then break end
    f:write(cls:GetFullName(),"\n")
    cls:ForEachFunction(function(fn)
      local n=fn:GetFName():ToString()
      if n:find("Deflect") or n:find("Stance") then
        f:write(fn:GetFullName(),"\n")
        fn:ForEachProperty(function(prop) f:write("  ",prop:GetFullName(),"\n") end)
      end
    end)
    cls:ForEachProperty(function(prop) local n=prop:GetFName():ToString() if n:find("Deflect") or n:find("Input") then f:write("  ",prop:GetFullName(),"\n") end end)
    cls=cls:GetSuperStruct()
  end
end
f:close()