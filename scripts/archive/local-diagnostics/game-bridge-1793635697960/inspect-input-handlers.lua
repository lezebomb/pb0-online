local f=assert(io.open("D:/pb0online/runs/input-handler-inspection.txt","w"))
local _,p=PBZ.getPlayer1()
local function describe(x)
  local ok,y=pcall(function() return x:get() end) if ok then x=y end
  local ok,n=pcall(function() return x:GetFullName() end)
  if ok then return n end
  if type(x)=="table" then local t={} for k,v in pairs(x) do local ok,z=pcall(function() return v:GetFullName() end) t[#t+1]=tostring(k).."="..(ok and z or tostring(v)) end return table.concat(t,",") end
  return tostring(x)
end
for _,name in ipairs({"SGameInputComponent","AbilityInputComponent"}) do
  for _,c in ipairs(FindAllOf(name) or {}) do
    local ok,o=pcall(function() return c:GetOwner() end)
    if ok and PBZ.valid(o) and o:GetAddress()==p:GetAddress() then
      f:write(c:GetFullName(),"\n")
      for _,field in ipairs({"InputHandlers","InputBindings","CurrentInputSets"}) do
        local ok,err=pcall(function() c[field]:ForEach(function(k,v) f:write(field," ",describe(k)," -> ",describe(v),"\n") end) end)
        if not ok then f:write(field," ",tostring(err),"\n") end
      end
    end
  end
end
f:close()