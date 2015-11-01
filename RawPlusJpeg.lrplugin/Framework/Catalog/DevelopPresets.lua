--[[
        DevelopPresets.lua

        Object that represents develop settings from a catalog point of view.
--]]


local DevelopPresets, dbg, dbgf = Object:newClass{ className = "DevelopPresets", register=true }



--- Get 
function DevelopPresets:getDevPresetNames()
    local names = {}
    local folders = LrApplication.developPresetFolders()
    for i, folder in ipairs( folders ) do
        local presets = folder:getDevelopPresets()
        for i,v in ipairs( presets ) do
            names[#names + 1] = v:getName()
        end
    end
    return names
end



return DevelopPresets
