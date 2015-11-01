--[[
        Intercom.lua
        
        Test Examples:

        Example A, Plugin #1
            local peer = _PLUGIN.id .. "2"
        
            local listenObject = { callback = function( msg )
                Debug.lognpp( msg )
                if msg.content == 'hello' then
                    -- process hello
                elseif msg.content == 'goodbye' then
                    -- process goodbye
                else
                end
                local method = 2
                local reply
                if method == 1 then
                    reply = msg
                    reply.comment = "this is a reply"
                    Debug.lognpp( "Base reply reusing command", reply )
                else
                    reply = intercom:createReply( msg )
                    Debug.lognpp( "Base reply using fresh creation", reply )
                end
                reply.content = msg.content .. " - right back at ya."
                intercom:sendReply( reply )
            end }
        
            local froms = {}
            froms[peer] = true
            intercom:listen( listenObject.callback, listenObject, froms )
        
            local msg = { name="hello", content="world", comment="testing send/receive..." }
            local reply, errm = intercom:sendAndReceive( msg, peer, 5 )
            Debug.lognpp( reply, errm )    
            Debug.showLogFile()

        Example A, Plugin #2
            local peer = _PLUGIN.id:sub( 1, -2 )
            
            local listenObject = { callback = function( msg )
                Debug.lognpp( msg )
                if msg.name == 'hello' then
                    -- process hello
                elseif msg.name == 'goodbye' then
                    -- process goodbye
                else
                end
                local method = 2
                local reply
                if method == 1 then
                    reply = msg
                    reply.comment = "this is a reply"
                    Debug.lognpp( "Base reply reusing command", reply )
                else
                    reply = intercom:createReply( msg )
                    Debug.lognpp( "Base reply using fresh creation", reply )
                end
                reply.name = msg.name .. " - ack"
                reply.content = msg.content .. " - right back at ya."
                intercom:sendReply( reply, msg.from ) -- to address is optional.
            end }
        
            local froms = {}
            froms[peer] = true
            intercom:listen( listenObject.callback, listenObject, froms )
        
            local msg = { name="hello", content="world", comment="testing send/receive..." }
            local reply, errm = intercom:sendAndReceive( msg, peer, 5 )
            Debug.lognpp( reply, errm )    
            Debug.showLogFile()

        
        Example B, Plugin #1
            intercom:broadcast( { content="hello" }, 30 )
            intercom:broadcast( { content="goodbye" }, 30 )
            for i = 1, 5 do
                intercom:broadcast( { content=str:fmt( "bleep ^1", i ) }, 30 - (i * 2) )
                app:sleepUnlessShutdown( 5 )
                if shutdown then return end
            end
        
        Example B, Plugin #2
            local cbObj = Object:new{ className="callbackObject2" } -- create callback object and give it a class-name for to-string purposes.
            function cbObj:callback( msg )
                Debug.lognpp( msg )
                if msg.content == 'hello' then
                    -- process hello
                    app:log( "Hello" )
                elseif msg.content == 'goodbye' then
                    app:log( "goodbye" )
                else
                    app:logVerbose( "Dont understand: ^1", str:to( msg.content ) )
                end
            end
            intercom:listenForBroadcast( cbObj.callback, cbObj, {
                [_PLUGIN.id:sub( 1, -2 )] = true,
            }, 1 ) -- Note: polling interval for broadcast must be shorter than 1/2 the time before msg deleted by sender to be sure it's seen.
            app:sleepUnlessShutdown( 15 )
            intercom:stopBroadcastListening( cbObj )
--]]


local Intercom, dbg = Object:newClass{ className="Intercom" }



--[=[

Anatomy of a message filename:
------------------------------
from-plugin-id timestamp seq-no.txt

from-plugin-id must not have spaces, nor timestamp, nor seq-no (space is delimiter)

Example:

com.robcole.lightroom.MyPlugin 2001-01-07_23-12-34 00001.txt

Note: Incoming directory is for unsolicited "command" messages, which may or may not warrant a response.
("from" address matches filename).
Responses comes to reply directory.

Note: reply filenames are the exact same as original message, but address in filename is
"to" address, not "from" address.


Message structure notes:
------------------------

Note: sender and receivers must agree on message content, these are assigned internally,
some based on send function parameters supplied in calling context, but still...

- version:      (number) may come in handy if message format changes, so old plugin can still talk to new plugin.
(- comment:      (string) just for debugging - comments may help to elaborate message intent in debug log file. Supported internally, but assigned externally)
- to:           (string) to address (plugin id) - not really essential for routing, since inbox defines who its to, again for debugging it is useful.
- from:         (string) from address (plugin id) - ditto: for debugging it is useful...
- filename:     (string) name of file from which this message came. Reminder: message files are deleted immediately after reading, so this may help debugging.


Additional notes:
-----------------

Basic intercom implements conduit, but no message processing (no function code "names" are defined by this module).
That part is up to context.


--]=]




--- Constructor for extending class.
--
function Intercom:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param t (table) initial object members, all optional, including:<br>
--           - pollingInterval (number) seconds between polling for incoming messages and/or replies.<br>
--                             faster means more responsive but more disk wear. Default is .1 second - seems a nice balanced value.
--                             - you can go down to .01 second (windows base clock frequency), for ultra-fast messaging,
--                             - or up to a half second if speed is not a concern, to save disk wear.
--
function Intercom:new( t )
    local o = Object.new( self, t )
    local dir = cat:getCatDir()
    o.mainDir = LrPathUtils.child( dir, "ElareMessages" )
    o.inDir = LrPathUtils.child( o.mainDir, "Incoming" )
    o.toMeDir = LrPathUtils.child( o.inDir, _PLUGIN.id )
    o:_initDir( o.toMeDir )
    dir = LrPathUtils.child( o.mainDir, "Replies" )
    o.replyDir = LrPathUtils.child( dir, _PLUGIN.id )
    o:_initDir( o.replyDir )
    o.bcastDir = LrPathUtils.child( o.mainDir, "Broadcast" )
    o:_initDir( o.bcastDir ) -- Note: unlike reglar, its the sender that defines plugin subfolder in bcast dir, not the receiver.
    o.seqNum = 1
    o.pollingInterval = o.pollingInterval or .1 -- better not be negative. not sure what happens if zero.
    if o.pollingInterval > .5 then
        app:callingError( ".5 second max" )
    end
    o.broadcastLifetime = o.broadcastLifetime or 10
    if o.broadcastLifetime < 1 then
        app:callingError( "1 second minimum" )
    end
    o.listeners = {}
    return o
end



-- private method to initialize plugin's incoming or reply directory.
-- assures its creation, and purges all expired messages.
-- does not purge unexpired messages, in case a peer plugin has already
-- sent this plugin a message before it has finished initialization.
function Intercom:_initDir( dir )
    if not fso:existsAsDir( dir ) then
        local s, m, c = fso:assureAllDirectories( dir )
        if not s then
            app:error( m )
        end
    else
        local now = LrDate.currentTime()
        local purge = {}
        for file in LrFileUtils.recursiveFiles( dir ) do
            local s, m = pcall( dofile, file )
            if s then
                if m then
                    if m.expires then
                        if now > m.expires then
                            purge[#purge + 1] = file
                        else
                            app:logVerbose( "Unexpired message" )
                        end    
                    else
                        purge[#purge + 1] = file
                        app:logVerbose( "No expiry" )
                    end
                else
                    purge[#purge + 1] = file
                    app:logVerbose( "Invalid message." )
                end
            else
                purge[#purge + 1] = file
                app:logVerbose( "Invalid file." )
            end
        end
        if #purge > 0 then
            for i, v in ipairs( purge ) do
                app:logVerbose( "Purging '^1'.", v )
                LrFileUtils.delete( v )
            end
        else
            app:logVerbose( "Nothing to purge in '^1'.", dir )
        end
    end
end



-- private method to serialize message and place in specified file.
function Intercom:_send( msg, path )
    local dir = LrPathUtils.parent( path )
    if not fso:existsAsDir( dir ) then
        local s, m = fso:assureAllDirectories( dir ) -- may be sending before receiver has prepared receptacle, but still want send to succeed.
        if s then
            app:logVerbose( "Receiver was not setup for receiving messages - receptacle directory created: ^1", dir )
        else
            app:error( "Receiver is not setup for receiving messages - directory can not be created: ^1, error message: ^2", dir, m )
        end
    -- else good to go...
    end
    local ser = "return " .. luaText:serialize( msg )
    local s, m = fso:writeFile( path, ser )
    if not s then
        app:error( m )
    end
end



-- private method to get filename for outgoing message,
-- and perform other common msg prep...
-- bumps seq-num for next time.
function Intercom:_prepareToSend( msg, to, time, expireTime )
    --if msg.name == nil then
    --    app:callingError( "Need msg name." )
    --end
    msg.version = 1 -- not used yet, but may be useful in future for old plugin to be able to talk to new plugin.
    if time == nil then
        time = LrDate.currentTime()
    end
    if expireTime == nil then
        expireTime = time + 60 -- give message a full minute to be picked up, by default. Hopefully way overkill, but not critical...
    end
    msg.from = _PLUGIN.id
    msg.to = to -- not required for functioning, but is comforting when it matches...
    msg.expires = expireTime
    if msg.filename then
        -- reply
    else
        local timeFmt = LrDate.timeToUserFormat( time, "%Y-%m-%d_%H-%M-%S" )
        msg.filename = string.format( "%s %s %05u.txt", msg.from, timeFmt, self.seqNum )
        self.seqNum = self.seqNum + 1
        if self.seqNum >= 100000 then
            self.seqNum = 1
        end
    end
end



--- Broadcast a messsage.
--
--  @param      msg (table, required) message to be broadcast.
--  @param      lifetime (number, optional) lifetime in seconds, else defaults to whatever was initialized when intercom object created (e.g. 10 seconds).
--
--  @usage      message will exist for specified time for any broadcast listeners to hear, then it's deleted (by sender - listeners just make note to not reprocess).
--  @usage      broadcast messages do not warrant replies, but receiver is free to send message to broadcaster when broadcast message is received...
--
function Intercom:broadcast( msg, lifetime )
    self:_prepareToSend(    -- does not encode to-dir
        msg,                -- message
        "broadcast",        -- to address
        nil,                -- time
        nil                 -- expire time is not used, but doesn't hurt.
    )
    local dir = LrPathUtils.child( self.bcastDir, msg.from )
    local file = LrPathUtils.child( dir, msg.filename )
    self:_send( msg, file )
    app:call( Call:new{ name="broadcast msg", async=true, guard=nil, main=function( call ) -- specifically re-entrant.
        app:sleepUnlessShutdown( lifetime or self.broadcastLifetime )
        LrFileUtils.delete( file )
    end } )
end



--- Optional method to initialize a fresh message for replying.<br>
--  The other possibility is just to reuse the received message for replying.
--
function Intercom:createReply( msg )
    return { from=msg.from, filename = msg.filename, comment=str:fmt( "this is a reply" ) }
end



--- Send message to specified plugin and wait for reply.
--
-- @usage must be called from a task.
--
-- @return reply (table) or nil if no reply
-- @return errm (string) error message if no reply.
--
function Intercom:sendAndReceive( msg, to, tmo )
    if tmo == nil then
        tmo = 10
    end
    -- content is optional.
    local reply, errm
    local s, m = app:call( Call:new{ name="send and receive", async=false, main=function( call )
        local time = LrDate.currentTime()
        self:_prepareToSend( msg, to, time, time + tmo )
        local dir = LrPathUtils.child( self.inDir, to )
        local file = LrPathUtils.child( dir, msg.filename )
        self:_send( msg, file )
        local replyPath = LrPathUtils.child( self.replyDir, msg.filename )
        Debug.logn( replyPath )
        while not shutdown do
            app:sleepUnlessShutdown( self.pollingInterval )
            -- LrTasks.sleep( self.pollingInterval )
            if fso:existsAsFile( replyPath ) then
                Debug.logn( "Reply received at: " .. replyPath )
                local s, m = pcall( dofile, replyPath )
                --Debug.pause( s, m )
                if s then
                    reply = m
                    LrFileUtils.delete( replyPath )
                    return
                else
                    errm = m
                    app:error( "bad reply: ^1", replyPath )
                end
            else
                local t2 = LrDate.currentTime()
                if t2 - time > tmo then
                    app:error( "tmo" )
                end
            end
        end
    end } )
    if s then
        return reply, errm
    else
        return nil, m
    end
end



--- Send message that is the reply to an inbound (unsolicited "command" message).
--
--  @param msg (table, required) 'name' is only required member, but 'content' may be nice...
--  @param to (string, required) destination plugin id - often msg.from
--
--  @usage Maybe best to recompute message content, then resend original message (since it already has some members assigned as needed) - but its your call...
--  @usage presently throws error if problems sending, but that may change - note: need not be called from task, although typically is.
--
function Intercom:sendReply( msg, to )

    -- Note: seq-num is not bumped when sending reply, only new messages.
    if to then
        if msg.from then
            assert( to == msg.from, "why not reply to sender?" )
        else
            Debug.logn( "No from field in message, must be a newly created message." )
        end
    else
        if msg.from then
            to = msg.from
        else
            app:callingError( "Dunno who to send reply to." )
        end
    end
    local dir = LrPathUtils.child( self.mainDir, "Replies" )
    local replyDir = LrPathUtils.child( dir, to )
    self:_prepareToSend( msg, to )
    local path = LrPathUtils.child( replyDir, msg.filename )
    self:_send( msg, path )

end



--- Send message to destination (unsolicited-inbox), and do not expect nor wait for reply.
--
--  @param msg (table, required) 'name' is only required member, but 'content' may be nice...
--  @param to (string, required) destination plugin id.
--
--  @usage Not for internal use - use private methods instead.
--
--  @return status (boolean) true => sent.
--  @return message (string) error message if not sent.
--
function Intercom:sendMessage( msg, to )
    local s, m = app:call( Call:new{ name="send message", async=false, main=function( call )
        self:_prepareToSend( msg, to )
        local dir = LrPathUtils.child( self.inDir, to )
        local file = LrPathUtils.child( dir, msg.filename )
        self:_send( msg, file )
    end } )
    return s, m
end



--  Private method for listening to messages from specified plugins.
--
--  @param functionOrMethod (function, required) callback function, or object method.
--  @param objectOrNil (Class instance object, optional) if provided, the aforementioned callback will be called as object method.
--  @param fromList (table as set, required) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param dir (string, required) inbox dir - typically to-me-dir or broadcast-dir.
--  @param ival (number, optional) polling interval. Often coarser for broadcast messages, since response time tends to be less critical.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--  @usage technically speaking, if not listening for broadcasts, and not planning on stopping the listener, object/method calling is not required,
--         <br>(i.e. could be function with no object) but its not really supported either.
--
function Intercom:_listen( functionOrMethod, objectOrNil, fromList, dir, ival )
    ival = ival or self.pollingInterval
    local listener
    local broadcast = (dir == self.bcastDir) 
    local objectName = str:to( objectOrNil )
    if broadcast then -- broadcast listener
        if ival > ( ( self.broadcastLifetime / 2 ) - .4 ) then
            ival = ( self.broadcastLifetime / 2 ) - .4 -- min bcast lifetime is 1, min bcast ival is .1
        end
        listener = objectName .. "_broadcast" -- must match stop-listen method.
    else
        listener = objectName -- ditto.
    end
    self.listeners[listener] = true
    app:call( Call:new{ name="Intercom listener", async=true, guard=nil, main=function( call )
        local s, m = app:call( Call:new{ name="Intercom message processor", async=false, main=function( call )
            Debug.logn( str:fmt( "listening object: ^1", listener ) )
            Debug.logn( str:fmt( "listening dir: ^1", dir ) )
            Debug.lognpp( "listening from-list", fromList )
            while not shutdown and self.listeners[listener] do
                for file in LrFileUtils.recursiveFiles( dir ) do
                    repeat
                        local filename = LrPathUtils.leafName( file )
                        if broadcast then -- non-broadcast messages are deleted after first seen.
                            if objectOrNil then
                                if not objectOrNil.__seen then
                                    objectOrNil.__seen = {}
                                elseif objectOrNil.__seen[file] then
                                    --Debug.logn( "Message seen: " .. filename )
                                    break
                                else
                                    -- Debug.logn( "Message being marked as seen: " .. filename .. ", file: " .. file)
                                end
                                objectOrNil.__seen[file] = true
                            else
                                --Debug.logn( "Intercom incoming (no object): " .. filename )
                                app:error( "broadcast requires object, no?" )
                            end
                        else
                            --Debug.logn( "Intercom incoming message: " .. filename )
                        end
                        local split = str:split( filename, " " )
                        local from
                        if #split > 1 then
                            from = split[1]
                        end
                        if not str:is( from ) then
                            app:logError( "Invalid message received" )
                            Debug.pause( file )
                            break
                        end                        
                        if from == _PLUGIN.id then
                            --Debug.logn( "Ignoring message from self: " .. _PLUGIN.id )
                            break
                        elseif not fromList[from] then
                            --Debug.logn( "Ignoring message from " .. from )
                            break
                        end
                        local sts, msg = pcall( dofile, file )
                        if sts then
                            if msg.version ~= nil then
                                if broadcast then
                                    Debug.logn( str:to( objectOrNil ), file )
                                    Debug.logn( str:fmt( "Broadcast message accepted: ^1", filename ) ) -- from address came from filename, so is redundent.
                                else
                                    Debug.logn( str:fmt( "Incoming message accepted: ^1", filename ) ) -- ditto
                                end
                                -- the following is not true for replies, but this is for listening to unsolicited "command" messages,
                                -- in which case from address in messages should match filename.
                                if msg.from then
                                    if from ~= msg.from then
                                        app:error( "bad from address" )
                                    else
                                        --
                                    end
                                else
                                    app:error( "No from address" )
                                end
                                if msg.filename then
                                    if filename ~= msg.filename then
                                        app:error( "Bad filename in message" )
                                    else
                                        -- ok
                                    end
                                else
                                    app:error( "no filename in message" ) -- @msg v1, all "proper" channels for msg prep are including filename as message member.
                                end
                                if objectOrNil then -- call function as method.
                                    functionOrMethod( objectOrNil, msg )
                                else
                                    functionOrMethod( msg )
                                end
                            else
                                app:logError( "Message missing version: ^1", msg )
                            end
                        else
                            --app:logVerbose( "Message file error: ^1", msg )
                            Debug.logn( str:fmt( "Message file read error (^1) - presumably message was \"cleaned up\"(?)", msg ) )
                        end
                    until true
                    if not broadcast then
                        LrFileUtils.delete( file ) -- it is OK to delete file being iterated.
                    end
                end  -- end-of for loop
                app:sleepUnlessShutdown( ival )
                --[[for k, v in pairs( objectOrNil.__seen ) do
                    if not fso:existsAsFile( k ) then
                        objectOrNil.__seen[k] = nil
                    end
                end ###3 - not sure what this was about now, but it's been this way for several months now @10/Oct/2012. - delete in 2014...
                --]]
            end
        end } )
        if shutdown then
            -- done
            return
        end
        if s then
            if broadcast then
                app:logVerbose( "^1 stopped listening to broadcasts.", objectName )
            else
                app:logVerbose( "^1 stopped listening to messages.", objectName )
            end
        else
            app:logError( "Intercom listening error: '^1'. Taking 5...", m )
            app:sleepUnlessShutdown( 5 )
        end
    end } )
end



--- Listen to messages from specified plugins, to me.
--
--  @param method (function, required) callback function - must be method.
--  @param object (Class instance object, optional) object containing callback method. - must not be closed object, or must contain __seen member table.
--  @param fromList (table as set, required) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param ival (number, optional) polling interval, else accept default.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--  @usage object may be nil, and method may be function, as long as plugin will never try to stop listening.
--
function Intercom:listen( method, object, fromList, ival )
    self:_listen( method, object, fromList, self.toMeDir, ival )
end



--- Listen to broadcast messages from specified plugins, to anyone.
--
--  @param method (function, required) callback function - must be method.
--  @param object (Class instance object, optional) object containing callback method. - must not be closed object, or must contain __seen member table.
--  @param fromList (table as set, required) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param ival (number, optional) polling interval, else accept default.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--
function Intercom:listenForBroadcast( method, object, fromList, ival )
    if object == nil then
        app:callingError( "Object must not be nil when listening for broadcast messages." )
    end
    self:_listen( method, object, fromList, self.bcastDir, ival )
end



--- Stop listener tied to specified object.
--
--  @param object Must be same object as passed to listen function.
--
function Intercom:stopListening( object )
    local listener = str:to( object )
    if self.listeners[listener] ~= nil then
        self.listeners[listener] = nil
    else
        app:logVerbose( "^1 is not listening.", listener )
    end
end



--- Stop broadcast listener tied to specified object.
--
--  @param object Must be same object as passed to listen-for-broadcast function.
--
function Intercom:stopBroadcastListening( object )
    local listener = str:to( object ) .. "_broadcast"
    if self.listeners[listener] ~= nil then
        self.listeners[listener] = nil
    else
        app:logVerbose( "^1 is not listening for broadcasts.", str:to( object ) )
    end
end



-- Optional: use Listener as base class for listening callback object.
-- Doesn't do much except assure listener has a unique name via to-string method
-- so multiple listeners in the same plugin won't conflict.
local Listener = Object:newClass{ className="IntercomListener", register=false }
function Listener:newClass( t )
    return Object.newClass( self, t )
end
function Listener:new( t )
    local o = Object.new( self, t )
    if not str:is( o.name ) then
        o.name = LrUUID.generateUUID() -- listener must have unique name if more than one object will be listening simultaneously.
    end
    return o
end
function Listener:toString()
    return self.name
end



return Intercom, Listener


