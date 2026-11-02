-- Release only a confirmed idle Halloween movement reservation.
local s = assert(getgenv().ChilliOriginalDebug)
local h, trace = s.HubState, assert(s.DeliveryDebug17)
assert(not trace.StaleEventLock30, "already installed")
local event
for _, value in pairs(debug.getupvalues(h.HalloweenOnly)) do
    if type(value)=="table" and rawget(value,"Pumpkin_") and rawget(value,"Dog_") then
        event=value
        break
    end
end
assert(event, "Halloween state not identified; no changes made")
local patch = {previous=h.ClaimMovement}
trace.StaleEventLock30=patch
function patch.ReleaseIdle()
    if h.Movement.Owner~="halloween" then return false end
    if event.Busy or event.Entering or event.Move or event.Chase or event.Stealing or event.SwapVis then return false end
    if h.HalloweenOnly()~=nil then return false end
    if event.Status~="Off" then return false end
    trace.Emit("STALE_EVENT_LOCK_RELEASE", {owner=h.Movement.Owner,status=event.Status})
    h.ReleaseMovement("halloween")
    return true
end
h.ClaimMovement=function(owner,...)
    if owner~="halloween" then patch.ReleaseIdle() end
    return patch.previous(owner,...)
end
local released=patch.ReleaseIdle()
trace.Flush()
return {installed=true,released=released,owner=h.Movement.Owner}
