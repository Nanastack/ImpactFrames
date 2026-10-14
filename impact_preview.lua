-- Manually requested local playback; no packet API or game commands.
local M={status='Local WS preview has not been initialized.'}
local ffi=require('ffi')
local lib
local failed=false
local resources=require('impact_preview_resources')
function M.resource(skill,race) return resources[tostring(skill)..':'..tostring(race)] end
function M.start(actor,target,race,skill)
    if failed then return nil,M.status end
    if type(race)~='number' or race<1 or race>8 then return nil,'Unsupported player race.' end
    local resource=M.resource(skill or 32,race)
    if not resource then return nil,'No local animation mapping for this weapon skill and race.' end
    local ok,result=pcall(function()
        if not lib then
            ffi.cdef[[int impact_preview_initialize(void);
                int impact_preview_start(uint32_t actor,uint32_t target,uint32_t file);
                void impact_preview_cancel(void);
                uint32_t impact_preview_motion_calls(void);
                int impact_preview_set_clips(const uint32_t* tags,uint32_t count);]]
            lib=ffi.load(AshitaCore:GetInstallPath()..'\\addons\\impactframes\\impact_preview_v3.dll')
            local code=lib.impact_preview_initialize()
            if code~=1 then error('Client layout check failed ('..code..').') end
        end
        local tags=ffi.new('uint32_t[?]',#resource.tags)
        for n,tag in ipairs(resource.tags) do tags[n-1]=tag end
        if lib.impact_preview_set_clips(tags,#resource.tags)~=1 then error('Invalid motion tag mapping.') end
        return lib.impact_preview_start(actor,target,resource.file)
    end)
    if not ok or result~=1 then
        failed=not ok or result==-9
        M.status='Local preview unavailable: '..tostring(result)
        return nil,M.status
    end
    M.status='Local WS '..tostring(skill or 32)..' routine started; no WS command or packet injection.'
    return true,M.status
end
function M.cancel() if lib then lib.impact_preview_cancel() end end
function M.calls() return lib and tonumber(lib.impact_preview_motion_calls()) or 0 end
return M
