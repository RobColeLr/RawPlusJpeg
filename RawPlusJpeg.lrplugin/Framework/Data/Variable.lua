--[[================================================================================

        Variable.lua

================================================================================--]]


local Variable, dbg = Object:newClass{ className = 'Variable', register = false }



--- Constructor for extending class.
--
function Variable:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Variable:new( t )
    return Object.new( self, t )
end



function Variable:get( a, ... )
    if a ~= nil then
        return a
    end
    for i, v in ipairs{ ... } do
        if v ~= nil then
            return v
        end            
    end
end



return Variable