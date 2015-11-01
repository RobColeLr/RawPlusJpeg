--[[================================================================================
        Lightroom/Lightroom
        
        Supplements LrApplication namespace (Lightroom from an app point of view, as opposed to a plugin point of view...).
================================================================================--]]


local Lightroom = Object:newClass{ className="Lightroom", register=false }



--- Constructor for extending class.
--
function Lightroom:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Lightroom:new( t )
    local o = Object.new( self, t )
    return o
end



function Lightroom:getFilenamePresetDir()
    local datDir = LrPathUtils.getStandardFilePath( 'appData' )
    for k, v in pairs( LrApplication.filenamePresets() ) do
        local exists = LrFileUtils.exists( v )
        if exists then
            --Debug.pause( "exists", v )
            return false, LrPathUtils.parent( v ) -- presets not stored with catalog
        end 
        --Debug.pause( v:sub( -60 ) )
    end
    local catDir = cat:getCatDir()
    local lrSets = LrPathUtils.child( catDir, "Lightroom Settings" )
    local fnTmpl = LrPathUtils.child( lrSets, "Filename Templates" )
    if fso:existsAsDir( fnTmpl ) then
        return true, fnTmpl -- presets *are* stored with catalog
    else
        return nil, LrPathUtils.child( datDir, "Filename Templates" ), fnTmpl -- not sure where they're stored: here's both locations.
    end
end



--- Evaluate conditions necessary for successfully restarting Lightroom.
--
--  @return restart function appropriate for OS, or nil.
--  @return status message to explain no restart function.
--
function Lightroom:prepareForRestart( catPath )
    local f, qual
    local s, m = app:call( Call:new{ name="Preparing to Restart Lightroom", async=false, main=function( call ) -- no guarding "should" be necessary.
        local exe
        local opts
        if not str:is( catPath ) then
            catPath = catalog:getPath()
        end
        local targets = { catPath }
        local doPrompt
        if WIN_ENV then
            exe = app:getPref( "lrApp" ) or app:getGlobalPref( "lrApp" ) -- set one of these in plugin manager or the like, to avoid prompt each time.
            opts = "-restart"
            if str:is( exe ) then
                if fso:existsAsFile( exe ) then
                    f = function()
                        return app:executeCommand( exe, opts, targets )
                    end -- no qualifications: if config'd should be good to go.
                else
                    qual = str:fmtx( "Lightroom app does not exist here: '^1' - consider changing pref...", exe )
                end
            else -- no exe config'd
                -- local sts, othr, x  = app:executeCommand( "ftype", nil, "Adobe.AdobeLightroom" )
                local sts, cmdOrMsg, resp  = app:executeCommand( "ftype Adobe.AdobeLightroom", nil, nil, nil, 'del', true )
                if sts then
                    app:logv( cmdOrMsg )
                    local q1, q2 = resp:find( "=", 1, true )
                    if q1 then
                        local p1, p2 = resp:find( ".exe", q2 + 1, true )
                        if p1 then
                            exe = resp:sub( q2 + 1, p2 )
                            if str:is( exe ) then
                                if fso:existsAsFile( exe ) then
                                    f = function()
                                        return app:executeCommand( exe, opts, targets )
                                    end
                                    qual = str:fmtx( "Lightroom executable (obtained by asking Windows): ^1", exe )
                                else
                                    qual = str:fmtx( "Lightroom app should exist here, but doesn't: '^1' - consider setting explicit pref...", exe )
                                end
                            else
                                qual = str:fmtx( "Exe file as parsed from ftype command does not exist: ^1", exe )
                            end
                        else
                            qual = str:fmtx( "Unable to parse exe file from ftype command, which returned: ^1", resp )
                        end
                    else
                        qual = str:fmtx( "Unable to parse exe file from ftype command, which returned '^1'", resp )
                    end
                else
                    qual = str:fmtx( "Unable to obtain lr executable from ftype command - ^1", cmdOrMsg )
                end
            end
        else -- Mac
            f = nil
            qual = "Auto-restart not supported on Mac yet."
            --[[ best not to try programmatic restart on Mac, until tested.
            f = function()
                return app:executeCommand( "open", nil, targets ) -- ###1 test on Mac - @10/May/2013 17:20 - not validated on Mac.
            end -- no qual
            --]]
        end
    end } )
    if s then
        return f, qual
    else
        return nil, m
    end
end



--- Restarts lightroom with current or specified catalog.
--
--  @param catPath (string, default = current catalog) path to catalog to restart with.
--  @param noPrompt (boolean, default = false) set true for no prompting, otherwise user will be prompted prior to restart, if prompt not permanently dismissed that is.
--
--  @usage depends on 'lrApp' pref or global-pref for exe-path in windows environment - if not there, user will be prompted for exe file.
--
function Lightroom:restart( catPath, noPrompt )
    local s, m = app:call( Call:new{ name="Restarting Lightroom", async=false, main=function( call ) -- no guarding "should" be necessary.
        local exe
        local opts
        if not str:is( catPath ) then
            catPath = catalog:getPath()
        end
        local targets = { catPath }
        local doPrompt
        if WIN_ENV then
            exe = app:getPref( "lrApp" ) or app:getGlobalPref( "lrApp" ) -- set one of these in plugin manager or the like, to avoid prompt each time.
            opts = "-restart"
            if not str:is( exe ) or not fso:existsAsFile( exe ) then
                if not str:is( exe ) then
                    app:logVerbose( "Consider setting 'lrApp' in plugin manager or the like." )
                    Debug.pause()
                else
                    app:logWarning( "Lightroom app does not exist here: '^1' - consider changing pref...", exe )
                end
                repeat
                    exe = dia:selectFile{ -- this serves as the "prompt".
                        title = "Select lightroom.exe file for restart.",
                        fileTypes = { "exe" },
                    }
                    if exe ~= nil then
                        if fso:existsAsFile( exe ) then
                            break
                        else
                            app:show{ warning="Nope - try again." }                            
                        end
                    else
                        return false, "user cancelled"
                    end
                until false
            elseif not noPrompt then
                doPrompt = true
            -- else just do it.
            end
            --app:setGlobalPref( "lrApp", exe ) -- not working: seems pref is not commited, even if long sleep.
            --app:sleep( 1 ) -- persist prefs
            --assert( app:getGlobalPref( "lrApp" ) == exe, "no" )
        else
            exe = "open"
            doPrompt = true
        end
        if doPrompt then
            local btn = app:show{ confirm="Lightroom will restart now, if it's OK with you.",
                actionPrefKey = "Restart Lightroom",
            }
            if btn ~= 'ok' then
                return false, "user cancelled"
            end
        -- else don't prompt
        end
        app:executeCommand( exe, opts, targets )
        app:error( "Lightroom should have restarted." )
    end } )
end
   
   
   
return Lightroom 