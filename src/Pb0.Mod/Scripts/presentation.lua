-- PvP body capsules. Native ability, damage and engine deflect logic are untouched.
return function(api)
 local state={version=1,configured=0,corrections=0}
 PB0_PRESENTATION=state
 local nextCheck=0
 api.coop.extraTicks.pb0SolidBodies=function()
  if not api.net.pvp or api.net.ghostHidden then return end
  local _,p=api.getPlayer1();local g=api.net.ghost
  if not (api.valid(p) and api.valid(g)) then return end
  local now=os.clock()
  if now>=nextCheck or state.ghost~=g:GetAddress() then
   nextCheck=now+0.2
   for _,actor in ipairs({p,g}) do
    actor:SetActorEnableCollision(true)
    actor.CapsuleComponent:SetCollisionEnabled(3)
    actor.CapsuleComponent:SetCollisionResponseToChannel(2,2) -- Pawn -> Block
   end
   state.ghost=g:GetAddress();state.configured=state.configured+1
  end
  local a,b=p:K2_GetActorLocation(),g:K2_GetActorLocation()
  local ra,rb=p.CapsuleComponent:GetScaledCapsuleRadius(),g.CapsuleComponent:GetScaledCapsuleRadius()
  local ha,hb=p.CapsuleComponent:GetScaledCapsuleHalfHeight(),g.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local dx,dy=b.X-a.X,b.Y-a.Y
  local d=math.sqrt(dx*dx+dy*dy)
  state.distance,state.minimumDistance=d,ra+rb
  -- Native walking sweeps normally prevent penetration. Reconcile an ability's unswept root correction
  -- only if it actually overlaps the pair; preserve Z and let the world's normal collision sweep decide.
  if math.abs(a.Z-b.Z)<ha+hb-math.max(ra,rb) and d<ra+rb-1 then
   local n=state.normal or {X=1,Y=0}
   if d>1 then n={X=dx/d,Y=dy/d} end
   local hit={}
   g:K2_SetActorLocation({X=a.X+n.X*(ra+rb+1),Y=a.Y+n.Y*(ra+rb+1),Z=b.Z},true,hit,false)
   state.corrections=state.corrections+1
  elseif d>1 then state.normal={X=dx/d,Y=dy/d} end
 end
 api.log("PB0 PvP solid body capsules enabled")
 return state
end