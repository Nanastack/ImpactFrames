-- Observe 0x028 knockback fields without changing or blocking packet data.
return function(data)
    assert(type(data)=='string','Action packet must be a string')
    local offset=32
    local function skip(width)
        assert(offset+width<=#data*8,'Truncated action packet')
        offset=offset+width
    end
    local function read(width)
        local first=offset;skip(width)
        local value=0
        for n=0,width-1 do
            local position=first+n
            value=value+(math.floor(data:byte(math.floor(position/8)+1)/2^(position%8))%2)*2^n
        end
        return value
    end
    skip(8+32)
    local count=read(10)
    skip(4+16+16+32)
    local targets,seen={},{}
    for _=1,count do
        local target=read(32)
        local actions=read(4)
        for _=1,actions do
            skip(5+12+4+3)
            local knockback=read(3)
            skip(17+10+31)
            if read(1)~=0 then skip(37) end
            if read(1)~=0 then skip(34) end
            if knockback~=0 and target~=0 and not seen[target] then
                targets[#targets+1]=target;seen[target]=true
            end
        end
    end
    return targets
end
