local M={}
function M.skills(names,query)
    query=(query or ''):lower():match('^%s*(.-)%s*$')
    local numeric=tonumber(query)
    local matches={}
    for id,name in pairs(names) do
        local match=true
        if numeric then match=id==numeric
        else
            for word in query:gmatch('%S+') do
                if not name:lower():find(word,1,true) then match=false;break end
            end
        end
        if match then matches[#matches+1]={id=id,name=name} end
    end
    table.sort(matches,function(a,b) return a.id<b.id end)
    return matches
end
return M
