local _,p=PBZ.getPlayer1()
local provider=p:GetLocomotionDriverComponent().MoveInputDataProvider
local out={}
for name,obj in pairs({Provider=provider,Joystick=provider.JoystickMoveInput,Keyboard=provider.KeyboardMoveInput,InputComponent=provider.InputComponent}) do
 local result={class=obj:GetClass():GetFullName(),fields={},functions={}}
 local cls=obj:GetClass();local depth=0
 while PBZ.valid(cls) and depth<3 do
  cls:ForEachProperty(function(prop)
   local n=prop:GetFName():ToString()
   pcall(function()
    local v=obj[n];local t=type(v)
    if t=="number" or t=="boolean" or t=="string" then result.fields[n]=v
    else
     local ok,x,y,z=pcall(function() return v.X,v.Y,v.Z end)
     if ok and type(x)=="number" then result.fields[n]={X=x,Y=y,Z=z} else result.fields[n]=tostring(v) end
    end
   end)
  end)
  cls:ForEachFunction(function(fn)
   local n=fn:GetFName():ToString()
   if n:find("Input") or n:find("Value") or n:find("Move") or n:find("Trigger") then
    local params={};fn:ForEachProperty(function(prop) params[#params+1]=prop:GetFullName() end)
    result.functions[n]=params
   end
  end)
  cls=cls:GetSuperStruct();depth=depth+1
 end
 out[name]=result
end
local function enc(v)
 if type(v)=="table" then local f={};for k,x in pairs(v) do f[#f+1]='"'..k..'":'..enc(x) end;return "{"..table.concat(f,",").."}" end
 if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 return '"'..tostring(v):gsub("\\","\\\\"):gsub('"','\\"')..'"'
end
local f=assert(io.open(PB0_QUALITY_CONFIG.root.."/native-input-api.json","w"));f:write(enc(out));f:close()
return "native input values inspected"