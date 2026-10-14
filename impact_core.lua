-- Independent actor timelines. Impact times refer to unpaused playback.
local M={}
function M.new(api,config)
    local self={jobs={},holds={},enabled=true}
    local function same(h) return api.valid(h.index,h.id,h.actor) end
    function self:release(h)
        if api.resume then api.resume(h.actor) end
        self.holds[h.id]=nil
        self.held=nil
    end
    function self:restore()
        local list={} for _,h in pairs(self.holds) do list[#list+1]=h end
        for _,h in ipairs(list) do self:release(h) end
    end
    function self:cancel()
        self:restore();self.jobs={};self.pending=nil
    end
    function self:interrupt(actor)
        local hold=self.holds[actor]
        if hold then self:release(hold) end
        local remaining={}
        for _,job in ipairs(self.jobs) do if job.actor~=actor then remaining[#remaining+1]=job end end
        self.jobs=remaining;self.pending=remaining[1]
    end
    function self:queue(actor,target,now,hits,meta)
        if not self.enabled then return end
        if self.holds[actor] then self:release(self.holds[actor]) end
        -- A new skill from this actor replaces only their previous timeline.
        local kept={} for _,job in ipairs(self.jobs) do if job.actor~=actor then kept[#kept+1]=job end end
        self.jobs=kept
        if #self.jobs>=64 then return end
        local index=api.find(actor)
        local targetIndex=api.find(target)
        if not index or not targetIndex then return end
        local points={}
        for _,hit in ipairs(hits or {}) do
            points[#points+1]={at=hit.at,pause=hit.pause or config.freeze}
        end
        if #points==0 then return end
        local job={actor=actor,target=target,index=index,ptr=api.actor(index),targetIndex=targetIndex,
            targetPtr=api.actor(targetIndex),start=now,shift=0,hits=points,next=1,meta=meta}
        self.jobs[#self.jobs+1]=job
        self.pending=job
    end
    function self:tick(now)
        local release={} for _,h in pairs(self.holds) do
            if not same(h) then release[#release+1]=h
            else
                if not h.confirmed then
                    local started=api.started(h.actor,now)
                    if started then
                        h.confirmed=true;h.until_time=started+h.duration
                        h.job.shift=h.job.shift+h.duration

                    elseif now-h.requested>.5 then
                        release[#release+1]=h
                    end
                end
                if h.confirmed and now>=h.until_time then release[#release+1]=h end
            end
        end
        for _,h in ipairs(release) do self:release(h) end
        local remaining={}
        for _,p in ipairs(self.jobs) do
            local hit=p.hits[p.next]
            local at=p.start+hit.at+p.shift
            local valid=api.valid(p.index,p.actor,p.ptr) and api.valid(p.targetIndex,p.target,p.targetPtr)
            if not valid then
                if self.holds[p.actor] then self:release(self.holds[p.actor]) end

            elseif now<at or self.holds[p.actor] then remaining[#remaining+1]=p
            elseif now-at>.25 then
            else
                local paused=hit.pause>0 and api.pause and api.pause(p.index,p.actor,p.ptr,hit.pause)
                if paused then
                    local h={index=p.index,id=p.actor,actor=p.ptr,until_time=now+hit.pause,
                        requested=now,duration=hit.pause,confirmed=not api.started,job=p}
                    self.holds[p.actor]=h;self.held=h
                    if h.confirmed then p.shift=p.shift+hit.pause end

                end
                p.next=p.next+1
                if p.hits[p.next] then remaining[#remaining+1]=p end
            end
        end
        self.jobs=remaining;self.pending=remaining[1]
    end
    return self
end
return M
