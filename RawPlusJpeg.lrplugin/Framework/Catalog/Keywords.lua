--[[
        Keywords.lua
--]]

local Keywords, dbg, dbgf = Object:newClass{ className = 'Keywords' }



--- Constructor for extending class.
--
function Keywords:newClass( t )
    return Object.newClass( self, t )
end


local kwFromPath




--- Constructor for new instance.
--
function Keywords:new( t )
    local o = Object.new( self, t )
    return o
end



--- Init keyword cache.
--
function Keywords:initCache()
    kwFromPath = {}
    local function initKeywords( path, keywords )
        for i, v in ipairs( keywords ) do
            local name = v:getName()
            kwFromPath[path .. name] = v
            initKeywords( path .. name .. "/", v:getChildren() )
        end
    end
    initKeywords( "/", catalog:getKeywords() )
end



--- Refresh display of recently changed photo (externally changed).
--
function Keywords:getKeywordFromPath( path, permitReinit )
    if not kwFromPath or ( permitReinit and not kwFromPath[path] ) then -- will be reinitialized upon first use, or if keyword expected but not found in cache.
        self:initCache()
    end
    --Debug.lognpp( kwFromPath )
    --Debug.showLogFile()
    return kwFromPath[ path ]
end



return Keywords

