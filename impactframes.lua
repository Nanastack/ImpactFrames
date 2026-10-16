addon.name='impactframes'
addon.author='Zarianna (100% vibe coded)'
addon.version='1.3.3'
addon.desc='Weapon-skill impact freezes and synchronized visuals.'
require('common')
local imgui=require('imgui')
local bit=require('bit')
local settings=require('settings')
settings.settings_path=function() return AshitaCore:GetInstallPath()..'\\config\\addons\\impactframes\\release\\' end
local profiles=require('impact_profiles')
local native=require('impact_native')
local decode=require('impact_packet')
local knockback_targets=require('impact_knockback')
local names=require('impact_skills')
local search=require('impact_search')
local tuning=profiles.presets.defaults
local options=settings.load(T{enabled=tuning.enabled~=false,other_players=tuning.other_players==true,
    profile_overrides=T{},disabled_skills=T{},selected_skill=1,selected_race=0,scope_ui_version=0})
if options.scope_ui_version<1 then
    options.selected_skill=1;options.selected_race=0;options.scope_ui_version=1;settings.save()
end
local config=profiles.copy(tuning)
config.freeze=config.freeze or .120
config.sync_ws_effects=tuning.sync_ws_effects~=false
config.generated_scale=config.generated_scale or 1;config.generated_offset=config.generated_offset or .1
local entity=AshitaCore:GetMemoryManager():GetEntity()
local function say(text) print('[impactframes] '..text) end
local function find(id)
    for index=1,0x8FF do if entity:GetServerId(index)==id and entity:GetActorPointer(index)~=0 then return index end end
end
local core=require('impact_core').new({find=find,actor=function(index)return entity:GetActorPointer(index)end,
    valid=function(index,id,ptr)return ptr~=0 and entity:GetServerId(index)==id and entity:GetActorPointer(index)==ptr end,
    pause=function(_,_,ptr,seconds)native.effect_sync(config.sync_ws_effects);return native.pause(ptr,seconds)end,
    resume=function(ptr)native.cancel(ptr)end,started=native.started},config)
local window={false}
local skillSearch={''}
local editor,editorKey,editorSkill,editorRace
local editorDirty=false
local editorMessage=''
local function apply_options()
    core:cancel();native.cancel();if package.loaded.impact_preview then package.loaded.impact_preview.cancel() end;native.effect_sync(config.sync_ws_effects)
    core.enabled=options.enabled
end
apply_options()
local function save()settings.save()end
local function load_editor()
    editorSkill=options.selected_skill
    editorRace=options.selected_race
    local profile,key,inherited=profiles.selected(options.profile_overrides,editorSkill,editorRace)
    editorKey=key;editor={enabled=not profiles.disabled(options,editorSkill,profile,editorRace),custom_freezes=true,hits={}}
    if profile then editor.hits=profiles.hits(profile,config,editorSkill) end
    local own=options.profile_overrides[key]
    editorMessage=(own and (own.reset_default and 'Impact Frames default.' or 'Your saved override.'))
        or (profile and (inherited and 'Inheriting global timings.' or '') or 'No exported timing. Add hits to create your own.')
    editorDirty=false
end
local function save_editor()
    if not profiles.validate(editor) then editorMessage='Not saved: hit times must increase and stay within 0ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“10000 ms.';return false end
    local profile=profiles.copy(editor);profile.key=editorKey;profile.enabled=editor.enabled
    options.profile_overrides[editorKey]=profile;core:cancel();save();editorDirty=false;editorMessage='Override saved.'
    return true
end
local exactInputs={}
local function slider_int(label,value,minimum,maximum)
    imgui.SetNextItemWidth(180)
    local modified=imgui.SliderInt(label,value,minimum,maximum)
    local finished=imgui.IsItemDeactivatedAfterEdit()
    local input=exactInputs[label] or {value={value[1]},active=false}
    exactInputs[label]=input
    if not input.active or modified then input.value[1]=value[1] end
    imgui.SameLine();imgui.SetNextItemWidth(85)
    local inputChanged=imgui.InputInt('##Exact '..label,input.value,0,0)
    local inputFinished=imgui.IsItemDeactivatedAfterEdit()
    input.active=imgui.IsItemActive()
    if not modified and (inputFinished or (inputChanged and not input.active)) then value[1]=input.value[1];modified=true end
    finished=inputFinished or finished
    if modified then value[1]=math.max(minimum,math.min(maximum,value[1])) end
    return modified,finished
end

-- Session-only developer unlock; preview code and hooks load only on first use.
local localTesting=false
local konamiStep,konamiTime=1,0
local konamiKeys={'UpArrow','UpArrow','DownArrow','DownArrow','LeftArrow','RightArrow','LeftArrow','RightArrow','B','A'}
local function unlock_local_testing()
    if localTesting then return end
    if not imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows) or imgui.GetIO().WantTextInput then konamiStep=1;return end
    local now=imgui.GetTime()
    if now-konamiTime>3 then konamiStep=1 end
    for key=ImGuiKey_Tab,ImGuiKey_Oem102 do
        if imgui.IsKeyPressed(key,false) then
            local expected=_G['ImGuiKey_'..konamiKeys[konamiStep]]
            konamiStep=key==expected and konamiStep+1 or (key==ImGuiKey_UpArrow and 2 or 1)
            konamiTime=now
            if konamiStep>#konamiKeys then localTesting=true;return end
        end
    end
end
local function preview_ws()
    if not localTesting then return end
    if editorDirty and not save_editor() then return end
    local memory=AshitaCore:GetMemoryManager()
    local index=memory:GetParty():GetMemberTargetIndex(0)
    local target=memory:GetTarget():GetTargetIndex(0)
    if not index or index==0 or not target or target==0 or target==index then say('Select a visible target other than yourself.');return end
    if entity:GetStatus(index)~=0 then say('Stand idle and disengaged for the local preview.');return end
    if entity.GetModelUpdateFlags and entity:GetModelUpdateFlags(index)~=0 then say('Wait for the model refresh.');return end
    local actorPtr,targetPtr=entity:GetActorPointer(index),entity:GetActorPointer(target)
    if actorPtr==0 or targetPtr==0 then return end
    local race,skill=entity:GetRace(index),options.selected_skill
    local preview=require('impact_preview')
    local resource=preview.resource(skill,race)
    if not resource then say('No local animation mapping for this WS and race.');return end
    local profile=profiles.resolve(options.profile_overrides,skill,resource.animation,race)
    local hits
    if core.enabled and profile and not profiles.disabled(options,skill,profile,race) then
        hits=profiles.hits(profile,config,skill)
        if not profiles.validate({hits=hits}) then return end
    end
    core:cancel();native.cancel();preview.cancel()
    local ok,message=preview.start(actorPtr,targetPtr,race,skill)
    say(message)
    if ok and hits then core:queue(entity:GetServerId(index),entity:GetServerId(target),imgui.GetTime(),hits) end
end
local function render_settings()
    if not window[1] then konamiStep=1;if editorDirty then save_editor() end;return end
    imgui.SetNextWindowSize({590,0},ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSizeConstraints({520,220},{900,math.max(220,imgui.GetIO().DisplaySize.y-40)})
    local flags=bit.bor(ImGuiWindowFlags_AlwaysAutoResize,ImGuiWindowFlags_NoFocusOnAppearing,ImGuiWindowFlags_NoNavInputs,ImGuiWindowFlags_NoNavFocus)
    local visible=imgui.Begin('Impact Frames',window,flags)
    if visible then
        unlock_local_testing()
        for _,option in ipairs({{'Enable Impact Frames','enabled'},{'Impact Frames for other player characters','other_players'}}) do
            local value={options[option[2]]}
            if imgui.Checkbox(option[1],value) then options[option[2]]=value[1];apply_options();save() end
        end
        if not native.available then imgui.TextWrapped('Animation freezes are unavailable on this client.') end
        imgui.Separator()
        if imgui.CollapsingHeader('Custom timing offsets and overrides') then
        if imgui.BeginCombo('Race',profiles.races[options.selected_race]) then
            for race=0,8 do
                local selected=options.selected_race==race
                if imgui.Selectable(profiles.races[race],selected) then
                    if editorDirty then save_editor() end
                    options.selected_race=race;editor=nil;save()
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end
        imgui.TextWrapped('Editing: '..profiles.races[options.selected_race]..'. These settings follow the race of the player performing the WS.')
        local selected=options.selected_skill
        if imgui.BeginCombo('Weapon skill',(names[selected] or 'Unknown skill')..' ('..selected..')') then
            if imgui.IsWindowAppearing() then
                skillSearch[1]=''
                imgui.SetKeyboardFocusHere()
            end
            imgui.InputText('Search name or ID',skillSearch,128,ImGuiInputTextFlags_AutoSelectAll)
            local matches=search.skills(names,skillSearch[1])
            if #matches==0 then imgui.Text('No matching weapon skills.') end
            for _,skill in ipairs(matches) do
                local current=selected==skill.id
                if imgui.Selectable(skill.name..' ('..skill.id..')',current) then
                    if editorDirty then save_editor() end
                    options.selected_skill=skill.id;editor=nil;save()
                    imgui.CloseCurrentPopup()
                end
            end
            imgui.EndCombo()
        end
        if not editor or editorSkill~=options.selected_skill or editorRace~=options.selected_race then load_editor() end
        local profile=profiles.selected(options.profile_overrides,editorSkill,editorRace)
        local disabled={profiles.disabled(options,editorSkill,profile,editorRace)}
        if imgui.Checkbox('Disable ImpactFrames for this weaponskill',disabled) then
            options.disabled_skills[profiles.disable_key(editorSkill,editorRace)]=disabled[1];editor.enabled=not disabled[1];core:cancel();save()
        end
        if imgui.Button('Reset to impactframes default value') then
            core:cancel();profiles.reset(options,editorSkill,editorRace);save();load_editor()
        end
        if editorMessage~='' then imgui.TextWrapped(editorMessage) end
        imgui.TextWrapped('Freezes automatically delay the remaining hits. Changes made autosave.')
        if imgui.Button('Add hit') and #editor.hits<8 then
            local previous=editor.hits[#editor.hits]
            editor.hits[#editor.hits+1]={at=previous and previous.at+.3 or 0,pause=config.freeze,strength=1};save_editor()
        end
        imgui.SameLine()
        if imgui.Button('Remove hit') and #editor.hits>1 then table.remove(editor.hits);save_editor() end
        imgui.BeginChild('WS hit controls',{0,240},ImGuiChildFlags_Borders,bit.bor(ImGuiWindowFlags_NoNavInputs,ImGuiWindowFlags_NoNavFocus))
        for n,hit in ipairs(editor.hits) do
            for _,field in ipairs({{'Time (ms)','at',1000,0,10000},{'freeze duration(ms)','pause',1000,0,1000}}) do
                local value={math.floor(hit[field[2]]*field[3]+.5)}
                local modified,finished=slider_int('Hit '..n..' '..field[1],value,field[4],field[5])
                if modified then hit[field[2]]=value[1]/field[3];editorDirty=true end
                if editorDirty and finished then save_editor() end
            end
        end
        imgui.EndChild()
        if editorDirty and imgui.Button('Save timing override') then save_editor() end
        imgui.TextWrapped('Race-specific overrides take priority over global timings. Reset affects only the selected WS and race scope. Settings are shared by all your characters.')
        elseif editorDirty then save_editor()
        end
        imgui.Separator()
        if localTesting then
            imgui.Text('Local WS testing unlocked (this session).')
            if imgui.Button('Play selected WS locally') then preview_ws() end
        end
        imgui.Text('By: Zarianna (100% vibe coded)')
    end
    imgui.End()
end
local function disable_after_error(err)
    core.enabled=false;pcall(function()core:cancel();native.cancel()end);say('Disabled after error: '..tostring(err))
end
ashita.events.register('packet_in','impactframes_packet',function(e)
    if e.id==0x00A or e.id==0x00B then core:cancel();native.cancel();if package.loaded.impact_preview then package.loaded.impact_preview.cancel() end;return end
    if e.id~=0x028 or not core.enabled then return end
    local selfId=AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
    local parsed,targets=pcall(knockback_targets,e.data)
    local knocked={}
    if parsed then
        for _,id in ipairs(targets) do
            if id==selfId then
                knocked[id]=true
                core:interrupt(id)
                local affected=find(id)
                if affected then native.cancel(entity:GetActorPointer(affected)) end
            end
        end
    end
    local ok,actor,target,skill,animation=pcall(decode,e.data)
    if not ok or not actor or knocked[actor] then return end
    local index=find(actor);if not index then return end
    if actor~=selfId then
        if not options.other_players or not entity.GetSpawnFlags or bit.band(entity:GetSpawnFlags(index),1)==0 then return end
    end
    local race=entity.GetRace and entity:GetRace(index) or 0
    local profile=profiles.resolve(options.profile_overrides,skill,animation,race)
    if not profile or profiles.disabled(options,skill,profile,race) then return end
    local hits=profiles.hits(profile,config,skill)
    if profiles.validate({hits=hits}) then core:queue(actor,target,imgui.GetTime(),hits) end
end)
local function tick()
    local now=imgui.GetTime()
    local index=AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0)
    native.observe(index and index>0 and entity:GetActorPointer(index) or 0)
    core:tick(now)
    return now
end
ashita.events.register('d3d_beginscene','impactframes_hold',function(backbuffer)
    if backbuffer==false then return end
    local ok,err=pcall(tick);if not ok then disable_after_error(err) end
end)
ashita.events.register('d3d_present','impactframes_present',function()
    local ok,err=pcall(function()
        tick()
        render_settings()
    end)
    if not ok then disable_after_error(err) end
end)
settings.register('settings','impactframes_settings',function(s)
    options=s or settings.get();apply_options();editor=nil
end)
ashita.events.register('unload','impactframes_unload',function()
    if editorDirty then save_editor() end
    core:cancel();if package.loaded.impact_preview then package.loaded.impact_preview.cancel() end;native.shutdown()
end)
ashita.events.register('command','impactframes_command',function(e)
    local args=e.command:args();local root=args[1] and args[1]:lower()
    if root~='/if' and root~='/impactframes' then return end
    e.blocked=true
    local cmd=(args[2] or 'config'):lower()
    if cmd=='reload' then
        if editorDirty then save_editor() end
        core:cancel();save();AshitaCore:GetChatManager():QueueCommand(1,'/addon reload impactframes')
    elseif cmd=='localws' and localTesting then preview_ws()
    elseif cmd=='config' or cmd=='gui' then window[1]=true
    else say('/if opens settings | /if reload reloads the addon.') end
end)

