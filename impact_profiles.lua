local M={presets=require('impact_presets'),races={[0]='Global (all races)',[1]='Hume male',[2]='Hume female',
    [3]='Elvaan male',[4]='Elvaan female',[5]='Tarutaru male',[6]='Tarutaru female',[7]='Mithra',[8]='Galka'}}
function M.copy(value)
    if type(value)~='table' then return value end
    local result={} for k,v in pairs(value) do result[k]=M.copy(v) end return result
end
function M.key(skill,animation,race)
    return tostring(skill)..':'..tostring(race or 0)..(animation and ':'..tostring(animation) or '')
end
function M.validate(profile)
    if type(profile)~='table' or type(profile.hits)~='table' or #profile.hits<1 or #profile.hits>8 then return nil end
    local previous=-1
    for _,hit in ipairs(profile.hits) do
        if type(hit)~='table' then return nil end
        for _,field in ipairs({'at','pause','strength'}) do
            if type(hit[field])~='number' or hit[field]~=hit[field] then return nil end
        end
        if hit.at<0 or hit.at>10 or hit.at<=previous or hit.pause<0 or hit.pause>1 or hit.strength<0 or hit.strength>1 then return nil end
        previous=hit.at
    end
    return profile
end
function M.resolve(overrides,skill,animation,race)
    if race and race>0 then
        for _,key in ipairs({M.key(skill,animation,race),M.key(skill,nil,race)}) do
            local profile=overrides[key] or M.presets.profiles[key]
            if profile then return M.validate(profile),key end
        end
    end
    for _,key in ipairs({M.key(skill,animation),M.key(skill)}) do
        local profile=overrides[key] or M.presets.profiles[key]
        if profile then return M.validate(profile),key end
    end
end
function M.selected(overrides,skill,race)
    race=race or 0
    local keys={}
    for _,source in ipairs({M.presets.profiles,overrides}) do
        for key in pairs(source) do
            local id,scope=key:match('^(%d+):(%d+)')
            if id==tostring(skill) and tonumber(scope)==race then keys[key]=true end
        end
    end
    local ordered={} for key in pairs(keys) do ordered[#ordered+1]=key end table.sort(ordered)
    for _,key in ipairs(ordered) do
        local profile=overrides[key] or M.presets.profiles[key]
        if M.validate(profile) then return profile,key end
    end
    if race>0 then
        local profile,key=M.selected(overrides,skill,0)
        return profile,key:gsub('^(%d+):0','%1:'..race,1),'global'
    end
    return nil,M.key(skill)
end
function M.hits(profile,config,skill)
    local result={}
    for n,hit in ipairs(profile.hits) do
        local pause=hit.pause
        if not profile.custom_freezes then
            local perHit=M.presets.skill_hit_freezes and M.presets.skill_hit_freezes[tostring(skill)]
            pause=(perHit and perHit[n]) or (M.presets.skill_freezes or {})[tostring(skill)] or config.freeze
        end
        result[n]={at=profile.frame_ticks and math.max(0,hit.at*config.generated_scale+config.generated_offset) or hit.at,
            pause=pause,strength=hit.strength}
    end
    return result
end
function M.disable_key(skill,race)
    return tostring(skill)..((race and race>0) and ':'..race or '')
end
function M.disabled(options,skill,profile,race)
    if race and race>0 then
        local specific=options.disabled_skills[M.disable_key(skill,race)]
        if specific~=nil then return specific end
    end
    local value=options.disabled_skills[tostring(skill)]
    if value~=nil then return value end
    value=(M.presets.disabled_skills or {})[tostring(skill)]
    if value~=nil then return value end
    return profile and profile.enabled==false or false
end
function M.reset(options,skill,race)
    race=race or 0
    for key in pairs(options.profile_overrides) do
        local id,scope=key:match('^(%d+):(%d+)')
        if id==tostring(skill) and tonumber(scope)==race then options.profile_overrides[key]=nil end
    end
    local flag=M.disable_key(skill,race)
    options.disabled_skills[flag]=nil
    if race>0 then
        local profile,key=M.selected({},skill,0)
        if profile then
            key=key:gsub('^(%d+):0','%1:'..race,1)
            options.profile_overrides[key]=M.copy(profile)
            options.profile_overrides[key].key=key
            options.profile_overrides[key].reset_default=true
            options.disabled_skills[flag]=M.disabled({disabled_skills={}},skill,profile)
        else options.disabled_skills[flag]=true end
    end
end
return M
