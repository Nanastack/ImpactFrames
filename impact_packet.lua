-- FFXI action packet fields are packed least-significant-bit first.
return function(data)
    local offset=32
    local function read(width)
        assert(offset+width<=#data*8,'Truncated action packet')
        local n=0
        for i=0,width-1 do
            local pos=offset+i
            n=n+(math.floor(data:byte(math.floor(pos/8)+1)/2^(pos%8))%2)*2^i
        end
        offset=offset+width
        return n
    end
    read(8)
    local actor=read(32)
    local count=read(6)
    read(4)
    local category=read(4)
    local skill=read(16)
    read(16); read(32)
    if category~=3 or count==0 then return nil end
    local target=read(32)
    local actions=read(4)
    if actions==0 then return nil end
    read(5); local animation=read(12); read(4); read(3); read(3)
    local damage=read(17)
    local message=read(10)
    -- 185: weapon skill damage. Misses and other results do not trigger hitstop.
    if message~=185 or damage==0 then return nil end
    return actor,target,skill,animation
end
