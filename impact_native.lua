local M={available=false,status='Native helper not loaded.'}
local ffi=require('ffi')
local lib
local errors={[-1]='FFXiMain.dll not loaded',[-2]='playback signature missing or ambiguous',
    [-3]='playback layout differs from verified capture',[-4]='hook library initialization failed',
    [-5]='hook creation failed',[-6]='hook enabling failed',[-7]='helper lifetime protection failed'}
local ok,err=pcall(function()
    ffi.cdef[[
        int impact_initialize(void);
        int impact_pause(uint32_t actor, int milliseconds);
        void impact_cancel(void);
        void impact_cancel_actor(uint32_t actor);
        int impact_actor_pause_age(uint32_t actor);
        void impact_set_effect_sync(int enabled);
        void impact_shutdown(void);
    ]]
    lib=ffi.load(AshitaCore:GetInstallPath()..'\\addons\\impactframes\\impact_native_release_v2.dll')
    local result=lib.impact_initialize()
    M.available=result==1
    M.status=M.available and 'Native playback hook ready (captured client layout).' or
        ('Native pause unavailable: '..(errors[result] or tostring(result)))
end)
if not ok then M.status='Native pause unavailable: '..tostring(err) end
local player=0
function M.observe(ptr)
    if not M.available then return end
    if ptr~=player then
        if player~=0 then lib.impact_cancel_actor(player) end
        player=ptr
    end
end
function M.pause(ptr,seconds)
    return M.available and lib.impact_pause(ptr,math.floor(seconds*1000+.5))==1
end
function M.cancel(ptr)
    if M.available then
        if ptr then lib.impact_cancel_actor(ptr) else lib.impact_cancel() end
    end
end
function M.started(ptr,now)
    if not M.available then return end
    local age=tonumber(lib.impact_actor_pause_age(ptr))
    if age>=0 then return now-age/1000 end
end
function M.effect_sync(value)
    if M.available then lib.impact_set_effect_sync(value and 1 or 0) end
end
function M.shutdown()
    if M.available then lib.impact_shutdown();M.available=false end
end
return M
