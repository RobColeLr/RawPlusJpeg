--[[
        Gate.lua
        
        Permits one-at-a-time entry to code, provided not too many in line already.
--]]


local Gate, dbg, dbgf = Object:newClass{ className = "Gate", register=false }



--- Constructor for class extension.
--
function Gate:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance objects.
--
function Gate:new( t )
    local o = Object.new( self, t )
    o.max = o.max or 1 -- simple mutex if max == 1.
    o.cnt = 0
    o.sts = nil
    o.ival = math.min( o.ival or .1, 1 ) -- max 1 second polling interval, so won't sleep too long in the face of shutdown. - not using app-sleep, for efficiency reasons.
    return o
end



--- Enter immediately, if possible, else wait for those ahead, if not too many.
--
function Gate:enter()
    assert( LrTasks.canYield(), "for async tasks only" )
    if self.cnt >= self.max then
        return false, "try again later..."
    end
    self.cnt = self.cnt + 1
    while self.sts and not shutdown do -- callers responibility to assure those who enter also exit.
        LrTasks.sleep( self.ival )
    end
    if shutdown then return false, "shutdown" end
    self.sts = true
    return true
end



--- Release hold for next in line to enter.
--
function Gate:exit()
    if self.cnt > 0 then
        self.cnt = self.cnt - 1
    end
    self.sts = nil
end



return Gate