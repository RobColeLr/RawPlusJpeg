--[[================================================================================

        Queue.lua

================================================================================--]]


local Queue, dbg = Object:newClass{ className = 'Queue', register = false }



--- Constructor for extending class.
--
function Queue:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param t consider max
--
function Queue:new( t )
    local o = Object.new( self, t )
    o.items = {}
    o.readIndex = 1
    o.writeIndex = 1
    o.count = 0
    if o.max == nil then
        o.max = math.huge
    end
    return o
end



function Queue:put( item )
    if self.count < self.max then
        self.items[self.writeIndex] = item
        self.writeIndex = self.writeIndex + 1
        self.count = self.count + 1
        return true
    else
        return false, "No room in queue, max is: " .. str:to( self.max )
    end
end


function Queue:peek()
    if self.count > 0 then
        local item = self.items[self.readIndex]
        return item
    else
        return nil, "Queue is empty."
    end
end


function Queue:get()
    if self.count > 0 then
        local item = self.items[self.readIndex]
        self.readIndex = self.readIndex + 1
        self.count = self.count - 1
        return item
    else
        return nil, "Queue is empty."
    end
end


function Queue:clear()
    self.items = {}
    self.count = 0
    self.readIndex = 1
    self.writeIndex = 1
end


function Queue:getCount()
    return self.count
end



return Queue