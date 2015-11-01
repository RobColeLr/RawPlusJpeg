--[[
        App.lua
        
        Design priniciple:
        
        App object methods implement primary API between derived plugin classes and app-framework/system.
        
        The idea is: as much as possible, to have a one-obj interface that will not have to change,
        despite potentially extensive changes in the code that implements the framework.
        
        For example, plugins don't interface directly to the preferences, since the preference object / methods may change,
        The app interface for preferences however should not change (as much...).
--]]


local App = Object:newClass{ className= 'App', register=false }

App.guardNot = 0
App.guardSilent = 1
App.guardVocal = 2
App.verbose = true


--- Constructor for extending class.
--
--  @param      t       initial table - optional.
--
function App:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance object.
--      
--  @param      t       initial table - optional.
--
--  @usage      Called from init-lua once all globals have been initialized.
--  @usage      Reads info-lua and creates encapsulated worker-bee objects.
--
function App:new( t )

    local o = Object.new( self, t )
    
    local vt = LrApplication.versionTable() -- first supported in Lr2.0
    if vt then
        o.lrVerMajor = vt.major
        o.lrVerMinor = vt.minor
    else
        o.lrVerMajor = 1
    end
    
    -- o.guards = {} - *** - seems guarding works better when loading / reloading if guards are global, but I could easily be mistaken - certainly cant justify...
    o.guarded = 0
        
    -- app-wide error/warning stats. Cleared when log cleared, even if no log file.
    -- service saves these to display difference at end-of-service.
    o.nErrors = 0
    o.nWarnings = 0

    -- read info-lua
    local status, infoLua = pcall( dofile, LrPathUtils.child( _PLUGIN.path, "Info.lua" ) )
    if status then
        o.infoLua = infoLua
    else
        error( infoLua )
    end
    
    -- math.randomseed( LrDate.currentTime() ) -- moved to init-framework

    if LogFile ~= nil then -- log file support is optional, but if logging, its first order of business,
        -- so other things can log stuff as they are being constructed / initialized.
        o.logr = objectFactory:newObject( LogFile )
        -- Note: the following is correct logic as long as one hasn't used a version with and without pref mgr and not cleared prefs in between.
        -- If incorrect, you can remedy by clearing all preferences for this plugin.
    end
    if o.logr then
        o.logr:enable{ verbose = ( prefs.logVerbose or prefs._global_logVerbose ) } -- *** could be smoother, but as long as I can search for -global-
            -- I can find all cases where this corner has been cut.
        if o.logr.verbose then
            o.logr:logInfo( "Logger enabled verbosely.\n" )
        else
            o.logr:logInfo( "Logger enabled.\n" )
        end
        o.logr:logInfo( LrSystemInfo.summaryString() )
        o.logr:logInfo( "Number of CPUs: " .. LrSystemInfo.numCPUs() )
        o.logr:logInfo( "Memory size: " .. LrSystemInfo.memSize() / 1000000 .. " MB\n")
        o.logr:logInfo( "Lightroom " .. LrApplication.versionString() .. "\n" )
        o.logr:logInfo( "Plugin name: " .. infoLua.LrPluginName )
        o.logr:logInfo( "Plugin path: " .. _PLUGIN.path )
        o.logr:logInfo( "Plugin version: " .. o:getVersionString() ) -- depends on str
        assert( _PLUGIN.id == infoLua.LrToolkitIdentifier, "ID mixup" )
        o.logr:logInfo( "Toolkit ID: " .. _PLUGIN.id )
        o.logr:logInfo( "Plugin enabled: " .. tostring( _PLUGIN.enabled ) .. "\n" )
    end    
    if Preferences then
        o.prefMgr = objectFactory:newObject( Preferences )
    end
    -- updater is global variable.
    o.user = objectFactory:newObject( User ) -- move to here 19/Aug/2011 2:06
    if o.logr then
        o.logr:logInfo( "Plugin username: " .. o.user:getName() )
    end
    o.os = objectFactory:newObject( 'OperatingSystem' )

    return o

end



--- Synchronous initialization
--
--  @usage      Called from Init.lua - initialization done here should be relatively quick and not yield or sleep, to eliminate race conditions between
--              startup and intiation of asynchronous services. Use background task for asynchronous initialization ( with post-init termination if nothing periodic/in-the-background to do ).
--
function App:init()

    -- supports binding to windows / mac specific things in the UI:
    if WIN_ENV then
        self:setGlobalPref( "Windows", true ) -- for binding to things that depend on platform.
        self:setGlobalPref( "Mac", false )
    else
        self:setGlobalPref( "Mac", true )
        self:setGlobalPref( "Windows", false )
    end
    
    self:switchPreset() -- assures presets are initialized before any asynchronous service accesses them,
        -- and before manager-init-prefs is called.
end



--- Determines if plugin is in release state.
--
--  @usage      Its considered a release state if plugin extension is "lrplugin".
--
function App:isRelease()
    return LrPathUtils.extension( _PLUGIN.path ) == 'lrplugin'
end
App.isReleaseMode = App.isRelease -- synonym



--- Determines if plugin can support Lr3 functionality.
--      
--  @usage          Returns false in Lr1 & Lr2, true in Lr3, will still return true in Lr4 (assuming deprecated items persist for one & only one version), false in Lr5.
--
function App:isLr3()
    return self.lrVerMajor >= 3 and self.lrVerMajor <= 4
end



--- Determines if plugin can support new Lr4 functionality.
--      
--  @usage          Returns false in Lr1, Lr2, & Lr3, true in Lr4, and will still return true in Lr5 (assuming deprecated items persist for one & only one version), false in Lr6.
--
function App:isLr4()
    return self.lrVerMajor >= 4 and self.lrVerMajor <= 5
end



--- Get Lr major version number.
--      
--  @usage          Use this if you need to know exact Lr (major) version.
--
function App:getLrVerMajor()
    return self.lrVerMajor, self.lrVerMinor
end
App.lrVersion = App.getLrVerMajor -- synonym for function App:lrVersion()



--- Is app operating in verbose/debug mode, or normal.
--
function App:isVerbose()
    return app:getGlobalPref( 'logVerbose' )
end



--- To support turning verbosity on/off when plugin manager dialog box is not being displayed.
--
function App:setVerbose( verbose )
    app.logr:enable{ verbose = verbose }
    if verbose then
        app:setGlobalPref( 'infoSynopsis', "Logging verbosely" )
        app:logv( "Logging is now verbose." )
    else
        app:setGlobalPref( 'infoSynopsis', "Logging is limited" )
        app:log( "Logging is now limited." )
    end
end



--- Test mode detection.
--  
--  <p>Test mode was invented to support test-mode plugin operation, and especially file-ops (rc-common-modules), which were guaranteed not to modify any files unless real mode.
--  For better or for worse, this functionality has been dropped from disk file-system class, but could still be used on an app-by-app basis.</p>
--
--  @usage      If test-mode functionality is desired, then set up a UI and bind to test-mode as global pref.
--
function App:isTestMode()
    return app:getGlobalPref( 'testMode' ) -- or false - the 'or false' part commented out (16/Jul/2012 16:37), so uninit can be distinguished from false.
end



--- Real mode detection.
--      
--  <p>Convenience function for readability: opposite of test mode.</p>
--
--  @see        App:isTestMode
--
function App:isRealMode()
    return not self:isTestMode()
end



--- Create a new preference preset.
--
function App:createPreset( props )
    if self.prefMgr then
        self.prefMgr:createPreset( props )
    end
end



--- Switch to another preference preset.
--
function App:switchPreset( props )
    if self.prefMgr then
        self.prefMgr:switchPreset( props )
    end
end



--- Register preset.
--
function App:registerPreset( name, ord )
    if self.prefMgr then
        self.prefMgr:registerPreset( name, ord )
    else
        self:callingError( "Preference manager required." )
    end
end



--- Set global preference.
--
--  @param name pref name
--  @param val pref value
--
--  @usage use this instead of setting directly, to make sure the proper key is used.
--
function App:setGlobalPref( name, val )
    if self.prefMgr then
        self.prefMgr:setGlobalPref( name, val )
    else
        prefs[name] = val -- bypasses global prefix if no pref manager.
    end
end



--- Get global preference.
--
--  @param name pref name
--
--  @usage use this instead of setting directly, to make sure the proper key is used.
--
function App:getGlobalPref( name )
    if self.prefMgr then
        return self.prefMgr:getGlobalPref( name )
    else
        return prefs[name] -- bypasses global prefix if no pref manager.
    end
end



--- Get binding that uses the proper key.
--
--  <p>UI convenience function that combines getting a proper global preference key, with creating the binding...>/p>
--
--  @param name pref name
--  @param val pref value
--
--  @usage use this for convenience, or bind directly to get-global-pref-key if you prefer.
--
function App:getGlobalPrefBinding( name )
    local key = self:getGlobalPrefKey( name )
    return bind( key )
end



--- Get binding that uses the proper key.
--
--  <p>UI convenience function that combines getting a proper preference key, with creating the binding...>/p>
--
--  @param name pref name
--  @param val pref value
--
--  @usage *** One can bind directly to props in plugin manager, since set-pref is wired to prop change<br>
--             this is for prompts outside plugin manager, that will change plugin manager preset pref too.
--  @usage use this for convenience, or bind directly to get-pref-key if you prefer.
--
function App:getPrefBinding( name )
    local key = self:getPrefKey( name )
    return bind( key )
end



--- Init global preference.
--
--  @param name global pref name.
--  @param dflt global pref default value.
--
--  @usage a-kin to init-pref reglar, cept for global prefs...
--
function App:initGlobalPref( name, dflt )
    if not str:is( name ) then
        error( "Global preference name key must be non-empty string." )
    end
    if self.prefMgr then
        self.prefMgr:initGlobalPref( name, dflt )
    elseif prefs then
        if prefs[name] == nil then
            prefs[name] = dflt
        end
    else
        error( "No prefs." )
    end
end



--- Get global preference key for binding.
--
--  @param name global pref name.
--
--  @usage not usually needed since there's get-global-pref-binding function,
--         <br>but this is still needed for binding section synopsis's.
--
function App:getGlobalPrefKey( name )
    if self.prefMgr then
        return self.prefMgr:getGlobalKey( name )
    else
        return name -- bypasses global prefix if no pref manager.
    end
end



--- Get preference key for binding.
--
--  @param name pref name.
--
--  @usage not usually needed since most preset prefs are defined in plugin manager via binding to props wired to set-pref<br>
--         and also there's the get-pref-binding function, but this could be used in unusual circumstances maybe - say if local pref being used in section synopsis.
--
function App:getPrefKey( name )
    if self.prefMgr then
        return self.prefMgr:_getPrefKey( name ) -- they're "friends".
    else
        return name -- bypasses preset prefix if no pref manager.
    end
end



--- Get global preference name given key.
--
--  @param key global pref key.
--
--  @usage not usually needed, but useful for pref change handler functions when handling arrays of keys.
--
function App:getGlobalPrefName( key )
    if self.prefMgr then
        return key:sub( 9 ) -- return part after the '_global_'.
    else
        return key -- bypasses global prefix if no pref manager.
    end
end



--- Get preference name given key.
--
--  @param key pref key.
--
--  @usage not usually needed, but useful for pref change handler functions when handling arrays of keys.
--
function App:getPrefName( key )
    if self.prefMgr then
        local p1, p2 = key:find( "__" )
        if p1 then
            return key:sub( p2 + 1 ) 
        else
            return nil
        end
    else
        return key -- bypasses global prefix if no pref manager.
    end
end



--  Preset name change handler. - *** deprecated.
--
--  @usage  Preferences module may be assumed if preset name is changing.
--
--  @usage  Wrapped externally.
--
--[[ *** save for reference.
function App:presetNameChange( props, name, value )
    if not str:is( value ) then
        Debug.pause()
        self.prefMgr.setGlobalPref( 'Default' ) -- Let entering of blank preset be same as entering 'Default'...
        return -- Change will be processed *after* returning (recursion guard keeps it from happening before returning, but does not keep it from happening ever).
    end
    local presetName = self.prefMgr:getPresetName()
    if presetName ~= 'Default' then
        if self.prefMgr:isPresetExisting( value ) then -- go through App?
            self:switchPreset( props ) -- creates new set with backing file if appropriate then loads into props.
            app:show{ info="Preferences switched to preset: ^1", value, actionPrefKey="Switched to named preset" }
        else
            Debug.pause()
            if dia:isOk( "Create a new preset named '^1'?", presetName ) then
                self:createPreset( props ) -- creates new set with backing file if appropriate then loads into props.
                app:show{ info="New preset created: ^1", value, actionPrefKey="Created new named preset" }
            else
                app.prefMgr:setGlobalPref( 'presetName', 'Default' ) -- gotta get rid of new value, but its been pre-commited (dunno what it used to be).
                self:switchPreset( props )
                app:show{ info="Reloaded default preset.", actionPrefKey="Switched to named preset" }
            end
        end
    else
        -- self.prefMgr:setGlobalPref( 'presetName', '' ) -- in case its not already (will not trigger recursion, since silently guarded).
            -- will however cause a double load if preset name change is being called NOT from a change handler.
        self.prefMgr:setGlobalPref( 'presetName', 'Default' ) -- I think this is OK - keeps the double-change from happening anyway.
        self:switchPreset( props )
        app:show{ info="Reverted to default preset.", actionPrefKey="Switched to named preset" }
    end
end
--]]



--- Clear all preferences for this plugin.
--
--  @usage Generally only called in response to button press when adv-Debug.logn-enabled and prefs are managed.
--         <br>but could be called in init-lua or wherever if you like - for testing and debug only...
--
--  @usage Works for managed as well as un-managed preferences.
--
function App:clearAllPrefs( props )
    for k,v in prefs:pairs() do -- note: nil prefs are not delivered by pairs function.
        prefs[k] = nil
    end
    for k,v in props:pairs() do -- note: nil prefs are not delivered by pairs function.
        props[k] = nil
    end
end



--- Loads (plugin manager) properties from named set or unnamed.
--      
--  @param      props       The properties to load.
--
--  @usage      Handles case when preference preset manager is installed, or not.
--
function App:loadProps( props )

    if self.prefMgr then
        self.prefMgr:loadProps( props )
    else
        -- this stolen from preferences-lua.
        for k,v in prefs:pairs() do
            local p1, p2 = k:find( '__', 1, true )
            if p1 and ( p1 > 1 ) then
                -- ignore manage preferences from previous plugin incarnations.
            else
                -- Debug.logn( "loading unnamed pref into prop: ", str:format( "prop-name: ^1, val: ^2", k, str:to( v ) ) )
                --if k == 'testData' then
                --    Debug.logn( "loading unnamed test data preference into property" )
                --end
                --if k:find( '_global_' ) ~= 1 then
                    -- Note: since the prefs are just for one plugin, there would only be globals if it *previously* was using a preference manager.
                    -- It's a good idea, to clear all prefs when switching from pref-mgr-based plugin to non-managed.
                    props[k] = v -- note: this will pick up all the globals too, but hopefully won't matter, since they won't be on the view.
                --end
            end
        end
    end

end



--- Save properties in preferences.
--      
--  @param      props       The properties to save.
--
--  @usage      file-backing is read-only.
--  @usage      As coded, this only applies to named presets when preset-name property changes.
--
function App:saveProps( props )

    if self.prefMgr then
        self.prefMgr:saveProps( props )
    else
        -- *** presently all are saved in manager using setpref.
    end

end



--- Get number of errors logged since logger was cleared (or app startup).
--
function App:getErrorCount()
    return self.nErrors
end



--- Get number of warnings logged since logger was cleared (or app startup).
--
function App:getWarningCount()
    return self.nWarnings
end



--- Get log file contents as text string.
--
--  <p>Invented to support Dialog function (kluge) to copy log contents to clipboard.</p>
--
function App:getLogFileContents()
    if self.logr then
        return self.logr:getLogContents()
    else
        return nil, "No logger."
    end
end



---     Not usually needed, since show-log-file and send-log-file are both app interfaces.
--      
--      In any case, it may be handy...
--
function App:getLogFilePath()
    if self.logr then
        return self.logr:getLogFilePath()
    else
        return nil
    end
end



---     Determines if advanced debug functionality is present and enabled.
--      
--      May be useful externally before embarking in time consuming loops that are no-op if not enabled.
--
function App:isAdvDbgEna()
    -- if self.advDbg and self:getGlobalPref( 'advDbgEna' ) then
    if self:getGlobalPref( 'advDbgEna' ) then
        return true
    else
        return false
    end
end



--- Shows log file to user by opening in default app for .log.
--      
--  @usage      I assume if no default set up, the OS will prompt user to do so(?)
--  @usage      Non-blocking.
--
function App:showLogFile()

    if self:isLoggerEnabled() then
        local logFile = self.logr:getLogFilePath()
        if fso:existsAsFile( logFile ) then
            LrTasks.startAsyncTask( function() -- to avoid the error that sometimes occurs when asking if can-yield is OK.
                local path = self.logr:getLogFilePath()
                self:openFileInDefaultApp( path, true ) -- ###3 - always start as task, or have non-blocking param?
            end )
        else
            self:show( { info="There are no logs to view (log file does not exist)." } )
        end        
    else
        self:show( { info="There is no log file to show." } )
    end

end



---     Clear the contents of the log file and the logged error/warning counts.
--
function App:clearLogFile()

    self.nErrors = 0
    self.nWarnings = 0

    if self:isLoggerEnabled() then
        self.logr:clear()
    else
        self:show( { info="There is no log file to clear, nevertheless: error+warning counts have been zeroed." } )
    end
    
    app:log( "Log file was cleared" )

end



--- Get name of function or calling function...
--
--  @param      spec (number or string, default=2) 0 for "this" function, 1 for calling function..., or alternate mnemonic for "this" function.
--
--  @usage      for debug message display.
--
--  @return     string - never nil nor empty
--
function App:func( her )
    local level = her or 2
    local funcInfo = debug.getinfo( level, 'n' )
    if funcInfo ~= nil and str:is( funcInfo.namewhat ) then -- name found
        return funcInfo.namewhat .. " function " .. str:to( funcInfo.name )
    end
    if level == 2 then
        return "this function"
    elseif level == 3 then
        return "calling function"
    else
        return "unknown function"
    end
end



--- Show info to user.
--
--  @deprecated in favor of universal show method, which supports formatting, and named parameter passing.
--
--  @usage      See Dialog class for param descriptions.
--
function App:showInfo( info, actionPrefKey, buttons, cancelButton, otherButton )
    -- return dialo g : s how Inf o (  info, actionPrefKey, buttons, cancelButton, otherButton ) - legacy function: deprecated.
    local answer
    local namedParams = { info=info, actionPrefKey=actionPrefKey }
    if buttons then
        local b = {}
        if type( buttons ) == 'string' then
            b[#b + 1] = {label=buttons,verb='ok'}
            if cancelButton then
                namedParams.cancelLabel = cancelButton
            end
            if otherButton then
                b[#b + 1] = {label=otherButton,verb='other'}
            end
        elseif type( buttons ) == 'table' then
            b = buttons
            -- cancel handled in default fashion in this case.
        end
        namedParams.buttons = b
    end
    return app:show( namedParams ) -- formatting not supported.
end



--- Show info to user - supports formatting.
--
--  @usage      See Dialog class for param descriptions.
--  @usage      New calling option (info as table):
--                  local answer = app:show({ info="^1 is a ^2", actionPrefKey="promptOrNot", buttons={ { label="My OK Button", verb="ok" }, { label="3rd Button", verb='othered' } } },
--                                            "Jane", "Doe" ) -- note: buttons still need to be in a table when there's an action-pref.
--                  answer = app:show({ info="^1 is a ^2", okButton="My OK Button", cancelButton="Please Dont Cancel", otherButton="3rd Button" },
--                                     "John", "Buck" ) -- note: buttons are just strings, returns are fixed.
--
function App:show( message, ... )
    return dialog:messageWithOptions( message, ... )
end

App.isOk = Dialog.isOk -- made this mistake too many times ;-}



--- Show warning to user.
--
--  @deprecated in favor of universal show method.
--
--  @usage      See Dialog class for param descriptions.
--
function App:showWarning( info, buttons, cancelButton, otherButton )
    -- return di alo g : s how W arning ( info, b1, b2, b3 ) - obsolete
    local answer
    local namedParams = { warning=info } -- no action-pref-key
    if buttons then
        local b = {}
        if type( buttons ) == 'string' then
            b[#b + 1] = {label=buttons,verb='ok'}
            if cancelButton then
                namedParams.cancelLabel = cancelButton
            end
            if otherButton then
                b[#b + 1] = {label=otherButton,verb='other'}
            end
        elseif type( buttons ) == 'table' then
            b = buttons
            -- ###2 cancel-label?
        end
        namedParams.buttons = b
    end
    return app:show( namedParams ) -- formatting not supported.
end
App.showWarn = App.showWarning -- so its like log method.



--- Show error to user.
--
--  @deprecated in favor of universal show method.
--
--  @usage      See Dialog class for param descriptions.
--
function App:showError( info, buttons, cancelButton, otherButton )
    -- return di al og : s ho wEr r or( info, b1, b2, b3 ) - obsolete
    local answer
    local namedParams = { error=info } -- no action-pref-key
    if buttons then
        local b = {}
        if type( buttons ) == 'string' then
            b[#b + 1] = {label=buttons,verb='ok'}
            if cancelButton then
                namedParams.cancelLabel = cancelButton
            end
            if otherButton then
                b[#b + 1] = {label=otherButton,verb='other'}
            end
        elseif type( buttons ) == 'table' then
            b = buttons
            -- ###2 cancel-label?
        end
        namedParams.buttons = b
    end
    return app:show( namedParams ) -- formatting not supported.
end
App.showErr = App.showError -- so its like log method.



--- Determine if app has a logger that can be used.
--      
--  <p>Purpose is to circumvent log loops or other functionality
--  that only makes sense if there is a logger.</p>
--      
--  <p>Presently it does not indicate if the logger is enabled for logging or not,
--  however, if there is a logger, then it is enabled - for now. - Non-logging plugins
--  are not even supported. But they don't have to log anything they don't want to,
--  so it does not have to slow them down much - still the future may change this.</p>
--
function App:isLoggerEnabled()
    return self.logr ~= nil
end



--- Open file in OS default app.
--
--  @param file     The file to open.
--
--  @usage  Presently supports just one file, but could be enhanced to support multiple files.
--  @usage  throws error if attempt fails.
--  @usage  does NOT pre-check for file existence so do so before calling.
--
--  @return status true iff worked (false means user canceled).
--  @return message non-nil iff didn't work.
--
function App:openFileInDefaultApp( file, prompt )
    local ext = LrPathUtils.extension( file )
    local dotExt = "." .. ext
    --local promptKey2 = 'Opened file in default app for ' .. dotExt - too much
    if prompt and ext ~= 'txt' and ext ~= 'log' then -- it was the 'lua' files that were causing the real problem.
        local promptKey = 'About to open file in default app for ' .. dotExt
        local promptTidbit
        if type( prompt ) == 'string' then
            promptTidbit = "\n \n" .. prompt
        else
            promptTidbit = ""
        end
        local question = "About to open ^1 in default app.\n\nIf no app registered to open ^2 files, this will fail.\n\nNow would be a good time to use your operating system to specify a default for opening ^2 files, if you haven't already.^3\n \nProceed to open?"
        local answer = app:show{ confirm=question, buttons={ dia:btn( "OK", 'ok' ) }, subs={ file, dotExt, promptTidbit }, actionPrefKey=promptKey }
        if answer == 'ok' then
            -- proceed
        else
            return false, "User opted out..."
        end
    end
    local s, anythingQ = LrTasks.pcall( self.os.openFileInDefaultApp, self.os, file )
    if s then
        --if prompt then - too much. it should have worked, and if not, then the error prompt will have to suffice.
        --    local name = LrPathUtils.leafName( file )
        --    app:show( { info="^1 should be open in the default app for ^2 files.", actionPrefKey=promptKey2 }, name, dotExt )
        --end
        return true
    else
        -- assume its an unregistered extension error:
        local m = "Unable to open file in default app - probably because it isn't registered. To remedy, use your operating system to specify an application to open " .. dotExt .. " files."
        error( m )
    end
end



--- Get OS platform name.
--
--  @return     'Windows' or 'Mac'.
--
function App:getPlatformName()
    if WIN_ENV then
        return 'Windows'
    else
        return 'Mac'
    end
end



--- Determine if non-anonymous user.
--      
--  @return     boolean
--
function App:isUser()
    return self.user:is()
end



--- Get name of user.
--      
--  <p>Note: There is no API for entering a user name,
--  however it will be read from shared properties when available.</p>
--      
--  <p>It used to be critical before named preferences came along, now
--  its just there in case you want to alter logic slightly depending
--  on user name - I sometimes customize behavior for myself, that other
--  users will never see...</p>
--      
--  <p>You could make custom versions for a friend or client that does not
--  require a separate plugin nor named preference set.</p>
--
--  @return     user's name: typically "_Anonymous_" if none.
--
function App:getUserName()
    return self.user:getName()
end



--- Executes a shell command.
--
--  <p>Although the format for command/params... is platform independent, the command itself may not be. For example:</p>
--  <blockquote>'exiftool' may be all that is needed to reference a pre-installed version of exiftool on Mac. However, full path may be required on windows,
--  since exiftool installer does not automatically add exiftool to path.</blockquote>
--
--  @param          command         (string, required) A pathed command name, or absolute path to executable.
--  @param          parameters      (string or array, optional) Example string: '-G -p "asdf qwerty"' or table: { "-p", "-it=me" }
--  @param          targets         (string or array, optional) An array of multiple filenames, or single target string.
--  @param          output          (string, optional) Path to file where command output will be re-directed, or nil for let method decide.
--  @param          handling        (string, optional) nil or '' => do nothing with output, 'get' => retrieve output as string, 'del' => retrieve output as string and delete output file.
--  @param          noQuotes        (boolean, optional) set true to keep from over-wrapping with quotes - do code search to see use cases.
--  @param          expectedReturnCode        (number, optional) if not passed, zero is assumed.
--
--  @usage          Quotes will be added where necessary depending on platform. The only exception to this is when something in parameter string needs to be quoted.
--
--  @usage          calling context can choose to alter parameters based on user and/or debug mode in order to keep output file(s) for perusal if desired.
--
--  @return         status (boolean):       true iff successful.
--  @return         command-or-error-message(string):     command if success, error otherwise.
--  @return         content (string):       content of output file, if out-handling > 0.
--
function App:executeCommand( command, parameters, targets, output, handling, noQuotes, expectedReturnCode )
    local _parameters
    if parameters ~= nil and type( parameters ) == 'table' then
        _parameters = table.concat( parameters, " " )
    else -- nil or string.
        _parameters = parameters
    end
    local _targets
    if targets ~= nil then
        if type( targets ) == 'table' then
            _targets = targets
        else -- targets had better be string.
            _targets = { targets }
        end
    end
    return self.os:executeCommand( command, _parameters, _targets, output, handling, noQuotes, expectedReturnCode )
end



--- Touch file(s) with current time or specified time.
--
--  @param path (string, required) file or file-mask.
--  @param time (number, default is current time)
--  @param justDate (boolean, default is false) -- if true, sets the date only, time will be 12:00Am I assume.
--
--  @return status
--  @return message
--  @return content
--
function App:touchFile( path, time, justDate )
    local s, cm, c
    if WIN_ENV then
        local f = LrPathUtils.child( _PLUGIN.path, "FileTouch.exe" ) -- take plugin-specific implementation if present.
        local tried
        if not fso:existsAsFile( f ) then
            tried = { f }
            f = Require.findFile( 'System/Support/FileTouch.exe' ) -- try for framework version.
        end
        if not fso:existsAsFile( f ) then
            -- app:error( "System support file is missing: ^1", f ) -- ###2
            tried[#tried + 1] = f
            return false, str:fmt( "Plugin/System support file is missing, tried:\n^1", table.concat( tried, "\n" ) ) -- perhaps this is a better error messate than execute-command would give.
        end
        local p = "/W" -- last-mod. /C is creation dt.
        if time then
            -- app:callingError( "time not supported yet" )
            local d = LrDate.timeToUserFormat( time, "%m-%d-%Y" )
            p = p ..  " /D " .. d
            if not justDate then
                local t = LrDate.timeToUserFormat( time, "%H:%M:%S" )
                p = p ..  " /T " .. t
            end
        -- else silently don't do time explicitly.
        end
        s, cm, c = self:executeCommand( f, p, { path } )
    else
        if time then
            app:callingError( "time not supported yet" )
        else
            p = ""
        end
        s, cm, m = self:executeCommand( "touch", p, { path } )
    end
    return s, cm, c
end



--- Touch file(s) with current time or specified time.
--
--  @param params (table, required) named parameters:<br>
--      file (string, required) path to file.<br>
--      modifiedTime (number)<br>
--      createdTime (number)<br>
--
--  @usage either modifiedTime or createdTime is required, or both.
--
--  @usage Examples:<br>
--      local s, cm, c = app:changeFileDates{ modifiedTime=LrDate.currentTime() } -- touch last-mod.
--      local s, cm, c = app:changeFileDates{ createdTime=LrDate.currentTime() } -- touch created.
--      local s, cm, c = app:changeFileDates{ modifiedTime=now, createdTime=now } -- touch both ('now' set to current time).
--      local s, cm, c = app:changeFileDates{ modifiedTime=LrDate.currentTime() - 86400 } -- set last mod to 24 hours ago.
--      local s, cm, c = app:changeFileDates{ createdTime=LrDate.currentTime() - 86400 } -- set created to 24hours ago.
--      local s, cm, c = app:changeFileDates{ modifiedTime=now, createdTime=LrDate.currentTime() - 86400 } -- created 24 hours ago, modified now.
--
--  @return status
--  @return message
--  @return content
--
function App:changeFileDates( params )
    local file = app:callingAssert( params.file, "need file param" )
    app:callingAssert( params.modifiedTime or params.createdTime, "need last-mod or created time" )
    local s, cm, c
    if WIN_ENV then
        local f = LrPathUtils.child( _PLUGIN.path, "FileTouch.exe" ) -- take plugin-specific implementation if present.
        local tried
        if not fso:existsAsFile( f ) then
            tried = { f }
            f = Require.findFile( 'System/Support/FileTouch.exe' ) -- try for framework version.
        end
        if not fso:existsAsFile( f ) then
            tried[#tried + 1] = f
            return false, str:fmt( "Plugin/System support file is missing, tried:\n^1", table.concat( tried, "\n" ) ) -- perhaps this is a better error messate than execute-command would give.
        end
        local function changeFileDate( time, p )
            -- Note: although omitting time means touch to now, for simplicity and consistency, touching to now is being handled explicitly.
            if time then
                local d = LrDate.timeToUserFormat( time, "%m-%d-%Y" )
                p = p .. " /D " .. d
                local t = LrDate.timeToUserFormat( time, "%H:%M:%S" )
                p = p .. " /T " .. t
            else
                error( "program failure" ) -- legal for file-touch.exe (would mean touch to now), but not legal for this program.
            end
            s, cm, c = self:executeCommand( f, p, { file } )
        end
        local pb = {}
        if params.modifiedTime and params.createdTime then
            if params.modifiedTime == params.createdTime then
                changeFileDate( params.modifiedTime, "/W /C" )
            else
                changeFileDate( params.modifiedTime, "/W" )
                if s then
                    changeFileDate( params.createdTime, "/C" )
                end
            end
        elseif params.modifiedTime then
            changeFileDate( params.modifiedTime, "/W" ) -- mod-time may be nil
        elseif params.createdTime then
            changeFileDate( params.createdTime, "/C" ) -- mod-time may be nil
        else
            error( "program failure" )
        end
    else -- ###1 test on Mac.
        local f = LrPathUtils.child( _PLUGIN.path, "ChangeFileDates" ) -- take plugin-specific implementation if present.
        local tried
        if not fso:existsAsFile( f ) then
            tried = { f }
            f = Require.findFile( 'System/Support/ChangeFileDates' ) -- try for framework version.
        end
        if not fso:existsAsFile( f ) then
            tried[#tried + 1] = f
            return false, str:fmt( "Plugin/System support file is missing, tried:\n^1", table.concat( tried, "\n" ) ) -- perhaps this is a better error messate than execute-command would give.
        end
        local p = {}
        if params.modifiedTime then
            p[#p + 1] = '-mDate "' ..  LrDate.timeToUserFormat( params.modifiedTime, "%m/%d/%Y %H:%M:%S" ) .. '"'
        end
        if params.createdTime then
            p[#p + 1] = '-cDate "' ..  LrDate.timeToUserFormat( params.createdTime, "%m/%d/%Y %H:%M:%S" ) .. '"'
        end
        if #p > 0 then
            s, cm, c = self:executeCommand( f, p, { file } )
        else
            error( "program failure" )
        end
    end
    return s, cm, c
end



--- Call an operation, with optional variable parameters.
--
--  <p>See 'Call' and 'Service' classes for more information.</p>
--
--  @param      op      Object encapsulating operation to be performed - must extend the 'Call' class.<br><br>
--      
--          Reminder, must include:<br><ul>
--      
--              <li>name
--              <li>main (called as method if object passed)
--              <li>(object - if main is a method)<br><br></ul>
--          
--          Optional:<br><ul>
--          
--              <li>cleanup (also called as method if object passed).
--              <li>async
--              <li>guard</ul><br>
--
--  @param      ...     Passed to main function.
--
--  @usage      Main function call will be wrapped with interactive debug (show-errors) during development,
--              <br>and regular error handling upon production (finale function or default handler - see Call class).
--  @usage      used to return guarded (boolean, default: nil) true iff call did not commence due to guarding.
--
--  @return     status (boolean) true means call OK, false means call error, or nil if guarded. (true only means task started if async).
--  @return     message (string) nil unless status is false, in which case error message is returned.
--
function App:call( op, ... )

    local param = { ... }
    
    if op.guards == nil then
        op.guards = {}
        if op.guardNames then
            for i, name in ipairs( op.guardNames ) do
                op.guards[name] = App.guardVocal
            end
        end
        if op.guard then
            op.guards[op.name] = op.guard
        end
    end
    
    for name, guard in pairs( op.guards ) do
        if (guard ~= nil) and (guard ~= App.guardNot) then
            if guards[name] then
                if guard == App.guardSilent then
                    self.guarded = self.guarded + 1
                    --Debug.logn( "Guarded", name )
                    return nil -- this originally returned 'true', before status/message return values were desired.
                else -- assume vocal guarding...
                    self:show( { warning="^1 already started." }, name )
                    return nil -- this originally returned 'true', before status/message return values were desired.
                end
            else
                guards[name] = true -- record call in progress.
            end
        end
    end

    -- guard MUST be cleared regardless of outcome of guarded call.    
    local function guardCleanup( status, message )
        for name, guard in pairs( op.guards ) do
            guards[name] = nil
        end
    end
    
    
    if op.async then
        LrFunctionContext.postAsyncTaskWithContext( op.name, function( context )
            if tab:isNotEmpty( op.guards ) then -- no reason to cleanup guards if there ain't none.
                context:addCleanupHandler( guardCleanup )
            end
            op.status, op.message = LrTasks.pcall( op.perform, op, context, unpack( param ) )
            -- op:cleanup( op.status, op.message ) - unprotected cleanup handler is how cleanup handlers can propagate errors to outer context, should they choose.
                -- I'm not sure anything is propagating anywhere if the op is asynchronous!? ###3
            local s, m = LrTasks.pcall( op.cleanup, op, op.status, op.message )
            if not s then
                App.defaultFailureHandler( false, m )
            end
            --Debug.pause( s, m )
        end )
        op.status = true
        op.message = nil
        return true, nil
    else
        local status, message = LrFunctionContext.pcallWithContext( op.name, function( context )
            if tab:isNotEmpty( op.guards ) then
                context:addCleanupHandler( guardCleanup )
            end
            op:perform( context, unpack( param ) ) -- main returned values are now stored in a table (returned) in op.
        end )
        if op.status == nil then
            op.status = status
        end
        if op.message == nil then
            op.message = message
        end
        op:cleanup( op.status, op.message ) -- unprotected cleanup handler is how cleanup handlers can propagate errors to outer context, should they choose.
        return op.status, op.message, unpack( op.returned or {} )
    end
    -- reminder: status & message returned are not very meaningful when async=true.
end



--[[ *** save for possible future resurrection
--  Determine if guarded call (specified by name) is in progress.
--
function App:isGuardedCallInProgress( name )
    return guards[name]
end
--]]



--  *** Save just in case...
--  An older obsolete version - suffers from the fact that errors are still propagated to outer context
--  when calls are nested, despite inner call error handling...
--[[function App:____call( op, ... )

    local param = { ... }
    
    if (op.guard ~= nil) and (op.guard ~= App.guardNot) then
        --if self.guards[op.name] then ###2 - see other places like this one.
        if guards[op.name] then
            if op.guard == App.guardSilent then
                self.guarded = self.guarded + 1
                -- Debug.logn( "Guarded", op.name )
                return true
            else
                self:show( { warning="^1 already started." }, op.name )
                return true
            end
        else
            guards[op.name] = true
        end
    end
    
    local cleanup = function( status, message )
        if op.guard then
            guards[op.name] = nil
        end
        LrFunctionContext.callWithContext( "app-call-cleanup", function( context )
            context:addFailureHandler( App.defaultFailureHandler )
            op:cleanup( status, message )
        end )
    end
    
    if op.async then
        LrFunctionContext.postAsyncTaskWithContext( op.name, function( context )
            -- context:addFailureHandler( failure ) - no need for failure handler if you've got a cleanup handler
            context:addCleanupHandler( cleanup )
            op:perform( context, unpack( param ) )
        end )
    else
        LrFunctionContext.callWithContext( op.name, function( context )
            -- context:addFailureHandler( failure ) - no need for failure handler if you've got a cleanup handler
            context:addCleanupHandler( cleanup )
            op:perform( context, unpack( param ) )
        end )
    end
end--]]



--- Start or continue log entry, without terminating it.
--
--  @usage      Useful for starting a log line at the entrance to some code block, then finishing it upon exit, depending on status...
--
function App:logInfoToBeContinued( message, ... )
    if self.logr and message then
        self.logr:logInfoStart( str:fmtx( message, ... ) )
    end
end
App.logStart = App.logInfoToBeContinued



--- Log info (will append to whatever was "to-be-continued").
--
--  @deprecated use log and log-verbose methods instead, since they support formatting.
--  @param message informational message
--  @param verbose set to App.verbose if the message should only be emitted if verbose logging is enabled.
--
function App:logInfo( message, verbose )
    if self.logr then
        self.logr:logInfo( message, verbose )
    end
end



--- Log info, if more than one param, first is assumed to be a format string.
--
function App:log( message, ... )
    if message then
        self:logInfo( str:fmtx( message, ... ) )
    else -- str-fmtr unhappy
        self:logInfo()
    end
end
App.logFinish = App.log



--- Log statistical value, but only if non zero.
--
function App:logStat( fmt, stat, nItemsString )
    if stat == nil then
        Debug.pause()
        return 0
    end
    if type( stat ) ~= 'number' then
        Debug.pause()
        return 0
    end
    if stat == 0 then
        return 0
    end
    local sfx = stat
    if str:is( nItemsString ) then
        sfx = str:nItems( stat, nItemsString )
    end
    app:log( fmt, sfx )
    return stat
end



--- Log verbose info, if more than one param, first is assumed to be a format string.
--
function App:logVerbose( message, ... )
    if self.logr then
        local m = str:fmtx( message, ... )
        self.logr:logInfo( m, true )
    end
end
App.logVerb = App.logVerbose -- terse synonym - *** deprecated.
App.logv = App.logVerbose -- terse synonym - recommended.
App.logV = App.logVerbose -- terse synonym - *** deprecated.



--- Count warning and log it with number - supports LOC-based formatting.
--
function App:logWarning( message, ... )
    self.nWarnings = self.nWarnings + 1
    if self.logr then
        self.logr:logWarning( self.nWarnings, str:fmtx( message, ... ) )
    end
end
App.logWarn = App.logWarning -- synonym.
App.logw = App.logWarning -- synonym - *** deprecated.
App.logW = App.logWarning -- synonym - *** deprecated.


--- Count error and log it with number - supports LOC-based formatting.
--
function App:logError( message, ... )
    self.nErrors = self.nErrors + 1
    if self.logr then
        self.logr:logError( self.nErrors, str:fmtx( message, ... ) )
    end
end
App.logErr = App.logError -- synonym
App.loge = App.logError -- synonym - *** deprecated.
App.logE = App.logError -- synonym - *** deprecated.



-- new method, re-invented 9/Apr/2013 12:39 to handle convenience of non-table params where disp is same as log, albeit condensed.
function App:_dispWarnOrErr( warnOrErr, params, ... )
    if params == nil then
        params = {} -- no log, so no unpacking of disp-args required (disp will default to generic).
    elseif type( params ) ~= 'table' then -- implied: disp to be truncated version of log, which is the param - var args are subs.
        local _params = {}
        _params.log = str:fmtx( str:to( params ), unpack{ ... } )
        _params.disp = _params.log:sub( 1, 55 ) -- truncate - note: no error is thrown if len is less than 55.
        params = _params
    else -- table
        -- may or may not include both disp and log members. In either case, they are specified explicitly.
        if params.log == nil then
            -- Debug.pause( "log message is missing - consider using non-table calling sequence instead." ) - this has to be permitted to support custom disp message with no log.
        else
            local dispArgs = {}
            for i, v in ipairs( params ) do
                dispArgs[#dispArgs + 1] = v
            end
            for i, v in ipairs{ ... } do
                dispArgs[#dispArgs + 1] = v
            end
            params.log = str:fmtx( str:to( params.log ), unpack( dispArgs ) )
        end
        if params.disp == nil then -- no explicit disp
            if params.log == nil then -- nor log, hmm...
                Debug.pause( "display message is missing, so is log message - will use generic display instead - nothing will be logged." ) -- deprecated: use nil param list if generic disp sans log desired.
            else -- implied: disp to be truncated version of log in this case.
                -- Debug.pause( "display message is missing, but log message is not - will truncate log message for display." ) - @9/Apr/2013 13:11, this is no longer a deprecated calling manner.
                params.disp = params.log:sub( 1, 55 )
            end
        else
            params.disp = str:squeezeToFit( str:to( params.disp ), 55 ) -- explicit disp: assure it fits and won't toss an error.
            -- this seemed like a good idea at first, but since char-width varies so much, it may make more sense just to truncate it, or let Lr truncate it ###3.
        end
    end
    if params.log then
        if warnOrErr == 'e' then
            app:logError( params.log ) -- str:to( params.log ), unpack( dispArgs ) )
        else
            app:logWarning( params.log ) -- str:to( params.log ), unpack( dispArgs ) )
        end
    end
    -- something will always be displayed when this method is called.
    local function display( call )
        local disp
        if params.disp == nil then
            disp = "See log file for more info..." -- hopefully error was logged externally, if not internally.
        else
            disp = params.disp -- non-null disps have been prepared above.
        end
        call:setCaption( disp ) -- Note: by default app name (and word: e.g. "Error") will be put at top.
        if warnOrErr == 'e' then -- bezel will only be re-displayable when progress scope is acknowledged.
            LrDialogs.showBezel( str:fmtx( "^1 - Error: ^2", self:getAppName(), disp ), 3 ) -- ###3: could make tmo configurable.
        else
            LrDialogs.showBezel( str:fmtx( "^1 - Warning: ^2", self:getAppName(), disp ), 3 )
        end
        while not call:isQuit() do
            LrTasks.sleep( .2 )
        end
    end
    -- reminder: display call is a no-op if app already has an error or warning up, due to fixed call name and silent guarding.
    -- the log always happens regardless, as does the holdoff.
    if warnOrErr == 'e' then
        app:call( Call:new{ name="Display Error Message", async=true, guard=App.guardSilent, progress={ title=str:fmtx( "^1 - Error (click 'x' to clear)", app:getAppName() ) }, main=display } )
    else
        app:call( Call:new{ name="Display Warning Message", async=true, guard=App.guardSilent, progress={ title=str:fmtx( "^1 - Warning (click 'x' to clear)", app:getAppName() ) }, main=display } )
    end
    if LrTasks.canYield() then
        if params.holdoff == nil then
            params.holdoff = 3 -- take some time before another error is logged / displayed, so user / logger isn't over-run...
        end
        if params.holdoff > 0 then
            app:sleep( params.holdoff )
        elseif params.holdoff == 0 then
            LrTasks.yield()
        -- else set holdoff to any negative value to avoid yielding altogether.
        end
    end
end



--- Display error in progress scope, and optionally include message for log file.
--
--  @param params (table, default={} ) disp/log parameters - see examples.
--
--  @usage Examples:<br>
--             app:displayError() -- displays generic "see log file" message, but logs nothing. (use only if error message logged in calling context).
--             app:displayError( "trouble - ^1", errm ) -- log error and display truncated version of it.
--             app:displayError{ disp="display me" } -- displays custom message, but log nothing.
--             app:displayError{ log="log me" } -- displays custom log message, and generic disp message: "see log file".
--             app:displayError{ disp="display me", log="log ^1", "me" } -- called using table params instead. Note: varargs are intra-table, and apply to log msg (no fmtx subs for disp msg).
--
--  @usage @24/May/2013 21:05, this message will be displayed until user acknowledges it (cancels scope), so only appropriate for background tasks, not foreground services.
--
function App:displayError( params, ... )
    self:_dispWarnOrErr( 'e', params, unpack{ ... } )
end



--[[ *** Save in case I change my mind... - Display a tossed error message (does not log it).
--
function App:dispErr( errm )
    self:displayError { -- note: when disp is explicit and log is absent, there will be no log.
        disp = app:parseErrorMessage( errm ),
    }
end
--]]



--- Display warning in progress scope, and optionally include message for log file.
--
--  @param params (table, default={} ) disp/log parameters - see examples.
--
--  @usage Examples:<br>
--             app:displayWarning() -- displays generic "see log file" message, but logs nothing. (use only if warning message logged in calling context).
--             app:displayWarning( "potential trouble - ^1", msg ) -- log warning and display truncated version of it.
--             app:displayWarning{ disp="display me" } -- displays custom message, but log nothing.
--             app:displayWarning{ log="log me" } -- displays custom log message, and generic disp message: "see log file".
--             app:displayWarning{ disp="display me", log="log ^1", "me" } -- called using table params instead. Note: varargs are intra-table, and apply to log msg (no fmtx subs for disp msg).
--
function App:displayWarning( params, ... )
    self:_dispWarnOrErr( 'w', params, unpack{ ... } )
end



--- Attempts to break an error message (obtained via lua debug object) into pure text message component, filename, and line number as string.
--
--  @param message (string, required) original error message
--
--  @return error-message sans filename/line-no
--  @return filename or nil
--  @return line number string or nil
--
function App:parseErrorMessage( message )
    local filename, line
    local c1  = message:find( ":", 1, true )
    if c1 then
        filename = message:sub( 1, c1 - 1 )
        if str:is( filename ) then
            local f = filename:match( "%[string \"(.-)\"%]" )
            if str:is( f ) then
                filename = f
            end
        end
        message = message:sub( c1 + 1 )
        c1 = message:find( ":", 1, true )
        if c1 then
            line = message:sub( 1, c1 - 1 )
            message = message:sub( c1 + 2 ) -- skip 1-char space separator.
        end
    end
    return message, filename, line
end



--- Returns a single string containing filename, line number, and error message - in a pretty format.
--
function App:formatErrorMessage( message ) 
    local msg, filename, line = app:parseErrorMessage( message )
    return str:fmtx( "^1 #^2: ^3", filename, line, msg )
end



--  Background:             How Lightroom handles errors in plugins:<br><br>
--      
--                          - if error occurs, then check if there is a registered handler,<br>
--                            if so, then call it, if not - do nothing.<br><br>
--                            
--                          - button handlers operate in contexts that do not have error handlers<br>
--                            registered.<br><br>
--
--  Notes:                  - This default failure handler, should be used "instead" of a pcall, in cases<br>
--                            where you you just want to display an error message, instead of croaking<br>
--                            with the default lightroom error message (e.g. normal plugin functions),<br>
--                            or dieing siliently (e.g. button handlers).<br></p>
--
--- Failure handler which can be used if nothing better springs to mind.
--      
--  @param      _false      First parmameter is always false and can be safely ignored.
--  @param      errMsg      Error message.
--
--  @usage                  Generally only used when there is no cleanup handler.
--  @usage                  Note: This is NOT a method.
--
function App.defaultFailureHandler( _false, errMsg )
    local msg = tostring( errMsg or 'program failure' ) .. ".\n\nPlease report this problem - thank you in advance..."
    local plugin
    if rawget( _G, 'app' ) then
        plugin = app:getPluginName()
    else
        plugin = "Plugin"
    end
    LrDialogs.message( LOC( "$$$/X=^1 has encountered a problem.", plugin), "Error message: " .. msg, 'critical' )
end



--- Get app name, which in general is a close derivative of the plugin name.
--
--  @usage I use different plugin names for distinguishing test/dev version and release version,
--         but same appname for both.
--
function App:getAppName()
    if self.infoLua.appName then
        return self.infoLua.appName
    else
        return self:getPluginName()
    end
end



--- Get plugin version number as a string.
--
--  <p>Preferrably without the build suffix, but manageable even with...</p>
--
--  @usage       Correct functioning depends on compatible VERSION format, which is either:
--
--               <p>- major/minor/revision, or
--               <br>- {version-number-string}{white-space}{build-info}</p>
--
--               <p>Plugin generator & releasor generate compatible version numbers / string format.
--               <br>If you are using an other build/release tool, just make sure the xml-rpc-server recognizes
--               <br>the value returned by this method and all should be well.</p>
--               
--               <p>Even if build is tossed in with version number due to omission of expected white-space
--               <br>it will still work as long as xml-rpc-server understands this...</p>
--               
--  @usage       It is up to the xml-rpc-server implementation to make sure if there is a version mismatch
--               between client version and server version, that the server version is always considered "newest".
--
--               <p>In other words, a string equality comparison is done, rather than a numerical version comparison,
--               <br>to determine whether the server version shall be considered "newer".</p>
--
--  @return      Unlike some similarly named app methods, the value returned by this one is used
--               <br>not only for UI display but for checking version number on server via xml-rpc.
--
--               <p>Returns "unknown" if not parseable from info-lua-VERSION...</p>
--
function App:getVersionString()
    local ver
    if self.infoLua.VERSION then
        if self.infoLua.VERSION.major then -- minor + revision implied.
            ver = '' .. self.infoLua.VERSION.major .. '.' .. self.infoLua.VERSION.minor
            if self.infoLua.VERSION.revision > 0 or self.infoLua.VERSION.build > 0 then
                ver = ver .. '.' .. self.infoLua.VERSION.revision
            end
            if self.infoLua.VERSION.build > 0 then
                ver = ver .. '.' .. self.infoLua.VERSION.build
            end
        else -- display is mandatory if no major/minor/revision.
            local split = str:split( self.infoLua.VERSION.display, " " )
            ver = split[1]
        end
    end
    if ver then
        return ver
    else
        return "unknown"
    end
end 



--- Get friendly Lr compatibility display string.
--
--  @return              string: e.g. Lr2+Lr3
--
function App:getLrCompatibilityString()

    local infoLua = self.infoLua    
    
    local lrCompat = "Lr" .. infoLua.LrSdkMinimumVersion
    if infoLua.LrSdkVersion ~= infoLua.LrSdkMinimumVersion then
        lrCompat = lrCompat .. " to Lr" .. infoLua.LrSdkVersion
    else
        -- lrCompat = lrCompat .. " only" -- trying to say too much - may make user think it won't work with dot versions.
        -- Note: an older version of Lightroom won't load it if min ver too high, so the "only" would never show in that case anyway.
        -- Only value then would be on more advanced version of Lightroom. So, its up to the plugin developer to bump that number
        -- once tested on the higher version of Lightroom. Users of higher Lr versions should rightly be concerned until then.
    end
    
    return lrCompat
    
end



--- Get plugin author's name as specified in info-lua.
--
--  @return string: never nil, blank only if explicitly set to blank in info-lua, otherwise something like "unknown".
--
function App:getAuthor()
    return self.infoLua.author or "Unknown" -- new way: set author in info.lua.
end



--- Get plugin author's website as specified in info-lua.
--
--  @return string: never nil, blank only if explicitly set to blank in info-lua, otherwise something like "unknown".
--
function App:getAuthorsWebsite()
    return self.infoLua.authorsWebsite or "Unknown"
end



--- Get plugin url as specified in info-lua.
--
--  @return string: never nil, blank only if explicitly set to blank in info-lua, otherwise something like "unknown".
--
function App:getPluginUrl()
    return self.infoLua.LrPluginInfoUrl or "Unknown"
end



--- Get plugin name as specified in info-lua.
--
--  @return string: required by Lightroom.
--
function App:getPluginId()
    if self.infoLua.pluginId then
        return self.infoLua.pluginId -- overridden.
    else
        return _PLUGIN.id -- standard.
    end
end 



--- Get plugin name as specified in info-lua.
--
--  @return string: required by Lightroom.
--
function App:getPluginName()
    return self.infoLua.LrPluginName or error( "Plugin name must be specified in info-lua." ) -- I don't think we could get this far without it, still...
end 



--- Get friendly string for displaying Platform compatibility - depends on platform support array defined in info-lua.
--
--  @return string: never nil. e.g. Windows+Mac
--
function App:getPlatformString()
    local infoLua = self.infoLua
    if not tab:isEmpty( infoLua.platforms ) then
        return table.concat( infoLua.platforms, "+" )
    else
        return ""
    end
end 



--- Determine if plugin supports Windows OS.
--
--  @return true if definitely yes, false if definitely no, nil if unspecified.
--
function App:isWindowsSupported()
    local infoLua = self.infoLua
    if not tab:isEmpty( infoLua.platforms ) then
        -- if str:isEqualIgnoringCase( infoLua.platforms[1], 'Windows' ) or str:isEqualIgnoringCase( infoLua.platforms[2], 'Windows' ) then - commented out 13/Jul/2013 18:07
        -- added 13/Jul/2013 18:07
        local set = tab:createSet( infoLua.platforms )
        if set['Windows'] then -- Note: case sensitive now
            return true
        else
            return false
        end
    else
        return nil
    end
end



--- Determine if plugin supports Mac OS.
--
--  @return true if definitely yes, false if definitely no, nil if unspecified.
--
function App:isMacSupported()
    local infoLua = self.infoLua
    if not tab:isEmpty( infoLua.platforms ) then
        -- if str:isEqualIgnoringCase( infoLua.platforms[1], 'Mac' ) or str:isEqualIgnoringCase( infoLua.platforms[2], 'Mac' ) then - commented out 13/Jul/2013 18:07
        -- added 13/Jul/2013 18:07
        local set = tab:createSet( infoLua.platforms )
        if set['Mac'] then -- Note: case sensitive now.
            return true
        else
            return false
        end
    else
        return nil
    end
end



--- Determine if plugin supports current platform.
--
--  @return true if definitely yes, false if definitely no, nil if unspecified.
--
function App:isPlatformSupported()
    local is
    if WIN_ENV then
        is = self:isWindowsSupported()
    else
        is = self:isMacSupported()
    end
    return is
end



--- Determine if plugin supports current Lightroom version.
--
--  @return true iff definitely yes.
--
function App:isLrVersionSupported()
    local infoLua = self.infoLua
    
    if self.lrVerMajor <= infoLua.LrSdkVersion then
        -- actual version less than specified version: note this is always OK, since LR would not load if actual version was less than minimimum.
        return true
    else -- lrVerMajor > infoLua.LrSdkVersion 
        -- here's where there is potential for a rub: Lightroom assumes backward compatibility, but I don't - i.e. if Lr is 5 and max Lr is 3, do we really want to run it?
        -- maybe so, and maybe not, but this is what this check is all about...
        return false
    end
end



--- Get Lightroom version name.
--
--  @return e.g. Lightroom 3
--
function App:getLrVersionName()
    return 'Lightroom ' .. self.lrVerMajor
end



--- Check if platform (OS) is supported, and if version of Lightroom is supported. Offer user opportunity to bail if not.
--
--  @usage      Returns nothing - presents dialog if plugin lacks pre-requisite support, and throws error if user opts not to continue.
--  @usage      It is intended that this be called WITHOUT being wrapped by an error handler, so error causes true abortion.
--              <br>Init.lua is a good candidate...
--
function App:checkSupport()
    local op = Call:new{ name='check support', async=false, main=function( call )
        local is = self:isPlatformSupported()
        if is ~= nil then
            if is then
                -- good to go - be silent.
                -- app:show( "Good to go..." )
                self:log( "Platform support verified - certified for " .. self:getPlatformString() )
            else
                local answer = self:show{ info="Plugin not officially supported on ^1, want to try your luck anyway?",
                    subs = self:getPlatformName(),
                    actionPrefKey = "Platform incompatibility warning"
                }
                if answer == 'ok' then
                    -- continue
                else
                    call:abort( self:getPlatformName() .. " platform not supported." )
                end
            end
        else
            if dialog:isOk( str:fmt( "Plugin author has not specified whether ^1 runs on ^2, want to try your luck anyway?", self:getPluginName(), self:getPlatformName() ) ) then
                -- continue
                self:log( "Continuing without explicitly specified platform support..." )
            else
                call:abort( self:getPlatformName() .. " platform not supported." )
            end
        end
        is = self:isLrVersionSupported()
        if is ~= nil then
            if is then
                -- good to go - be silent.
                -- app:show( "Good to go..." )
                self:log( "Lightroom version support verified - certified for " .. self:getLrCompatibilityString() )
            else
                local answer = self:show{ info="Plugin not officially supported on ^1, want to try your luck anyway?",
                    subs = self:getLrVersionName(),
                    actionPrefKey = "Lightroom version incompatibility warning"
                }
                if answer == 'ok' then
                    -- continue
                else
                    call:abort( str:fmt( "Lightroom version ^1 not supported.", LrApplication.versionString() ) )
                end
            end
        else
            if dialog:isOk( str:fmt( "Plugin author has not specified whether ^1 runs on ^2, want to try your luck anyway?", self:getPluginName(), self:getLrVersionName() ) ) then
                -- continue
                self:logInfo( "Continuing without explicitly specified lightroom version support..." )
            else
                call:abort( str:fmt( "Lightroom version ^1 not supported.", LrApplication.versionString() ) )
            end
        end
    end }
    self:call( op )
    -- the following code depends on async=false.
    if op:isAborted() then
        LrErrors.throwUserError( op:getAbortMessage() )
    end
end



--- Returns string for displaying Platform & Lightroom compatibility.
--
--  <p>Typically this is used in the plugin manager for informational purposes only.
--  Info for program logic best obtained using other methods, since format returned
--  by this function is not guaranteed.</p>
--
--  @return         string: e.g. "Windows+Mac, Lr2 to Lr3"
--
function App:getCompatibilityString()

    local compatTbl = {}
    local platforms = self:getPlatformString()
    if str:is( platforms ) then
        compatTbl[#compatTbl + 1] = platforms
    end
    compatTbl[#compatTbl + 1] = self:getLrCompatibilityString() -- always includes standard stuff
    local compatStr = table.concat( compatTbl, ", " )
    return compatStr

end



--- Does debug trace action provided supporting object has been created, and master debug is enabled.
--
--  <p>Typically this is not called directly, but instead by way of the Debug.logn function returned
--  by the class constructor or object registrar. Still, it is available to be called directly if desired.</p>
--
--  @usage      Pre-requisite: advanced debug enabled, and logger enabled (@2010-11-22 - the latter always is).
--  @usage      See advanced-debug class for more information.
--
function App:debugTrace(...)
    --if self:isAdvDbgLogOk() then -- debug object created and debug enabled and logr available.
    if self:isAdvDbgEna() then -- advanced debug enabled - probably redundent, since dbgr-pause only pauses when enabled, oh well.
        -- self.advDbg:debugTrace( name, id, info )
        -- Debug.pause(...)
        Debug.logn( ... ) -- ###2
    -- else deep-6.
    end
end



--- Output debug info for class if class enabled for debug.
--
--  @usage      Typically this is not called directly, but instead by way of the Debug.logn function returned
--              by the class constructor or object registrar. Still, it is available to be called directly if desired.
--  @usage      Pre-requisite: advanced debug enabled, and logger enabled (@2010-11-22 - the latter always is).
--  @usage      See advanced-debug class for more information.
--
function App:classDebugTrace( name, ...)
    if self:isClassDebugEnabled( name ) then
        Debug.logn( "class '" .. name .. "':", ... )
    end
end



--- Output debug info, formatted, for class if class enabled for debug.
--
--  @usage      Typically this is not called directly, but instead by way of the Debug.logn function returned
--              by the class constructor or object registrar. Still, it is available to be called directly if desired.
--  @usage      Pre-requisite: advanced debug enabled, and logger enabled (@2010-11-22 - the latter always is).
--  @usage      See advanced-debug class for more information.
--
function App:classDebugTraceFmt( name, fmt, ...)
    if self:isClassDebugEnabled( name ) then
        local msg = "class '" .. name .. "': " .. str:fmtx( fmt, ... )
        Debug.logn( msg )
    end
end



--- Determine if advanced debug support and logger enabled to go with.
--
--  @usage        Typical use for determining whether its worthwhile to embark on some advanced debug support activity.
--  @usage        Consider using Debug proper instead.
--
--  @return       boolean: true iff advanced debug functionality is "all-systems-go".
--
function App:isAdvDbgLogOk() -- ###2 - Really using Debug logr for advanced debugging now.
    return self:isAdvDbgEna() and self.logr
end



--- Determine if class-filtered debug mode is in effect, and class of executing method is specifically enabled.
--
--  <p>Typically not called directly, but indirectly by Debug.logn function, although it can be called directly if desired...</p>
--  
--  @param      name        Full-class-name, or pseudo-class-name(if not a true class) as registered.
--
function App:isClassDebugEnabled( name )
    if self:isAdvDbgEna() then
        if self:getGlobalPref( 'classDebugEnable' ) then -- limitations are in effect
            local propKey = Object.classRegistry[ name ].propKey
            if propKey then
                return self:getGlobalPref( propKey )
            else
                return true -- default to enabled if object not registered for limitation.
            end
        else
            return true
        end
    else
        return false
    end
end



-- Force class debug enable - intended for testing only, otherwise, enabling should be done via UI.
--
function App:_classDebugEnable( name, value )
    local propKey = Object.classRegistry[ name ].propKey
    if propKey then
        if value == nil then
            value = true
        end
        self:setGlobalPref( propKey, value )
        return true
    else
        return false, "Not registered"
    end
end



--- Determine if basic app-wide debug mode is in effect.
--      
--  <p>Synonymous with log-verbose.</p>
--
function App:isDebugEnabled()
    return self:getGlobalPref( 'logVerbose' )
end



--- Determine if metadata-supporting plugin is enabled.
--
--  @deprecated in favor of _PLUGIN.enabled instead.
--
--  @param      name (string, default dummy_) name of alternative plugin metadata item (property) to be used.
--  @param      photo (lr-photo, default 1st photo of all) photo to use to check.
--
--  @usage      This method presently only works when a metadata item is defined. Maybe one day it will also work even with no plugin metadata defined.
--  @usage      Only works from an async task.
--
--  @return     enabled (boolean) true iff valid property name and plugin is enabled. Throws error if not called from async task.
--  @return     error message indicating property name was bad or plugin is disabled.
--
function App:isPluginEnabled( name, photo )
    return _PLUGIN.enabled -- there used to be a lot more in this method ;-}
end



--- Get property from info-lua.
--
--  @param      name     The name of the property to get.
--
function App:getInfo( name )

    return self.infoLua[name] -- return nil if nil.

end



--- Logs a rudimentary stack trace (function name, source file, line number).
--
--  @usage      No-op when advanced debugging is disabled.
--      
function App:debugStackTrace()
    --if not self:isAdvDbgLogOk() then -- debug object created and debug enabled and logr available.
    if not self:isAdvDbgEna() then -- advanced debug enabled - now uses independent logger. this is probably redundent.
        return
    end
    -- self.advDbg:debugStackTrace( 3 ) -- skip level 1 (Debug.logn-func) and level 2 (this func).
    Debug.stackTrace( 3 )
end



--- Get the value of the specified preference.
--      
--  @param      name        Preference property name (format: string without dots).
--
--  @usage      Preference may be a member of a named set, or the un-named set.
--  @usage      See Preferences class for more info.
--
--  @return     preference value corresponding to name.
--
function App:getPref( name, presetName, expectedType, default )
    if type( name ) == 'table' then -- called with named parameter table.
        presetName = name.presetName
        expectedType = name.expectedType
        default = name.default
        name = name.name
    end
    if default ~= nil and expectedType == nil then
        expectedType = type( default )
    end
    self:callingAssert( type( name ) == 'string', "Name must be string, not '^1'", type( name ) ) -- assures against nil too.
    self:callingAssert( name ~= "", "Unable to obtain preference - name is empty string." )
    local rawValue
    if self.prefMgr then
        rawValue = self.prefMgr:getPref( name, presetName )
    elseif prefs then
        rawValue = prefs[name]
    else
        error( "No prefs." )
    end
    if rawValue == nil then
        return default -- may also be nil - note: not passed through type-checking.
    end
    local value = rawValue
    if expectedType then
        if expectedType == 'number' then
            -- try to convert to number
            local s, num = pcall( tonumber, rawValue )
            if s then
                assert( num ~= nil and type( num ) == 'number', "not number" )
                value = num
            else
                self:error( "^1 pref is not a number", name )
            end
        elseif expectedType == 'string' then
            -- should *be* a string - do not convert to string
            if type( rawValue ) == 'string' then
                value = rawValue
            else
                self:error( "^1 pref is not a string", name )
            end
        elseif expectedType == 'boolean' then
            -- try to convert to boolean
            if type( rawValue ) == 'boolean' then
                -- ok
            elseif type( rawValue ) == 'string' then
                if rawValue == 'true' then
                    value = true
                elseif rawValue == 'false' then
                    value = false
                else
                    self:error( "^1 pref was expected to be boolean, but was string, and neither 'true' nor 'false'", name )
                end
            else
                self:error( "^1 pref is not a number", name )
            end
        elseif expectedType == 'function' then
            if type( rawValue ) == 'function' then
                -- ok
            else
                self:error( "^1 pref was expected to be a function, but was a '^1'", name, type( rawValue ) )
            end
        elseif expectedType == 'table' then
            if type( rawValue ) == 'table' then
                -- ok
            else
                self:error( "^1 pref was expected to be a table, but was a '^1'", name, type( rawValue ) )
            end
        else
            Debug.pause( "Expected type not supported:", expectedType )
        end
    end
    return value
end 



--- Set the specified preference to the specified value.
--      
--  @param      name        Preference property name (format: string without dots).
--  @param      value       Preference property value (type: simple - string, number, or boolean).
--
--  @usage      Preference may be a member of a named set, or the un-named set.
--  @usage      See Preferences class for more info.
--
function App:setPref( name, value, presetName )
    if not str:is( name ) then
        error( "Preference name key must be non-empty string." )
    end
    if self.prefMgr then
        self.prefMgr:setPref( name, value, presetName )
    elseif prefs then -- preset-name not applicable.
        prefs[name] = value
    else
        error( "No prefs." )
    end
end 



--- Make sure support preference is initialized.
--
--  <p>Because of the way all this pref/prop stuff works,
--  uninitialized prefs can be a problem, since they are
--  saved into props via pairs() function that won't recognize
--  nil items, thus items that should be blanked, may retain
--  bogus values.</p>
--      
--  @usage      Pref value set to default only if nil.</p>
--      
--  @usage      Make sure init-props is being called to init the props
--              from the prefs afterward.
--
function App:initPref( name, default, presetName, values )
    if not str:is( name ) then
        error( "Preference name key must be non-empty string." )
    end
    if self.prefMgr then
        self.prefMgr:initPref( name, default, presetName, values ) -- only managed prefs are supporting
    elseif prefs then
        -- preset-name ignored in this case.
        if prefs[name] == nil then
            prefs[name] = default
        elseif values then
            local v = prefs[name]
            for i, v2 in ipairs( values ) do
                local value
                if v2.value then
                    value = v2.value
                else
                    value = v2
                end
                if tab:isEquivalent( v, value ) then
                    --Debug.pause( name, value ) 
                    prefs[name] = value
                    v = nil
                    break
                else
                    --Debug.pause( name, key, v, value )
                end
            end
            if v ~= nil then
                prefs[name] = default
            end
        end
    else
        error( "No prefs." )
    end
end 



--- Get global preference iterator.
--
--  @param      sortFunc (boolean or function, default false) pass true for default name sort, or function for custom name sort.
--
--  @usage      for iterating global preferences, without having to wade through non-globals.
--
--  @return     iterator function that returns name, value pairs, in preferred name sort order.
--              <br>Note: the name returned is not a key. to translate to a key, call get-global-pref-key and pass the name.
-- 
function App:getGlobalPrefPairs( sortFunc )

    if self.prefMgr then
        return self.prefMgr:getGlobalPrefPairs( sortFunc )
    else
        if sortFunc then
            error( "Preference manager required for sorting global preference pairs." ) -- this limitation could be lifted by some more coding.
        end
        return prefs:pairs()
    end
    
end



--- Get local preference iterator.
--
--  @param      sortFunc (boolean or function, default false) pass true for default name sort, or function for custom name sort.
--
--  @usage      for iterating local preferences, without having to wade through globals.
--
--  @return     iterator function that returns name, value pairs, in preferred name sort order.
--              <br>Note: the name returned is not a key. to translate to a key, call get-global-pref-key and pass the name.
-- 
function App:getPrefPairs( sortFunc )

    if self.prefMgr then
        return self.prefMgr:getPrefPairs( sortFunc )
    else
        if sortFunc then
            error( "Preference manager required for sorting preference pairs." ) -- this limitation could be lifted by some more coding.
        end
        return prefs:pairs() -- locals and globals share same space when not managed.
    end
    
end



--- Delete preference preset.
--
--  @param props - get re-loaded from defaults, or if default set is being "deleted" (reset), then they're reloaded from saved default values.
--
--  @usage which is governed by global preset name pref.
--
function App:deletePrefPreset( props )
    self.prefMgr:deletePreset( props )
end



--- Log a simple key/value table.
--      
--  @usage      *** Deprecated - use Debug function instead.
--  @usage      No-op unless advanced debug enabled.
--  @usage      Does not re-curse.
--      
function App:logTable( t ) -- indentation would be nice - presently does not support table recursion.
    self:logWarning( "app:logTable is deprecated - please use debug function instead." )
    if not self:isAdvDbgLogOk() then
        return
    end
    if t == nil then
        self:logInfo( "nil" )
        return
    end    
    for k,v in pairs( t ) do
        self:logInfo( "key: " .. str:to( k ) .. ", value: " .. str:to( v ) )
    end
end



--- Log any lua variable, including complex tables with cross links. - debug only
--      
--  <p>It could use a little primping, but it has served my purpose so I'm moving on.</p>
--
--  @usage          *** Deprecated - please use Debug function instead.
--  @usage          Can not be used to log _G, everything else thrown at it so far has worked.
--  @usage          Example: app:logObject( someTable )
--      
function App:logObject( t )
    self:logWarning( "app:logObject is deprecated - please use Debug function instead." )
    --if not self:isAdvDbgLogOk() then
    --    return
    --end
    if self:isAdvDbgEna() then
        --self.advDbg:logObject( t, 0 )
        Debug.pp( t ) -- test this
    end
end



--- Log an observable property table. - debug only
--      
--  @usage          No-op unless advanced debug logging is enabled.
--
function App:logPropertyTable( t, name )
    if not self:isAdvDbgLogOk() then
        return
    end
    if t == nil then
        Debug.logn( "property table is nil" )
        return
    end
    if t.pairs == nil then
        Debug.logn( str:to( name ) .. " is not a property table" )
        return
    end
    for k,v in t:pairs() do
        Debug.logn( k , " = ", v )
    end
end



--- Send unmodified keystrokes to lightroom.
--
--  <p>Unmodified meaning not enhanced by Ctrl/Cmd/Option/Alt/Shift...</p>
--      
--  @param      text            (string or table, required) if string: e.g. "p" or "u", maybe "g"...<br>
--                                                          if table, text.win and/or text.mac keystroke sequences, and maybe a hint: text.mod.<br>
--                                                                    noYield can be passed as text member or separate parameter.
--  @param      noYield         (boolean or number, default is true) -- yield or msec to sleep after sending keys.
--      
--  @usage      Platform agnostic (os specific object does the right thing).
--  @usage      Direct keystrokes at Lightroom proper, NOT dialog boxes, nor metadata fields, ...
--
--  @return     status(boolean): true iff command to send keys executed without an error.
--  @return     message(string): if status successful: the command issued, else error message (which includes command issued).
--
function App:sendKeys( text, noYield )

    if text == nil then
        self:callingError( "text must not be nil" )
    end
    local s, m
    if type( text ) == 'string' then
        s, m = self.os:sendUnmodifiedKeys( text )
    elseif type( text ) == 'table' then
        if noYield == nil then
            noYield = text.noYield
        end
        if WIN_ENV then
            if text.win then
                local mod = text.mod == true or text.win:find( "{Ctrl" ) or text.win:find( "{Alt" ) or text.win:find( "{Shift" ) -- could include win-key, but hasn't been used so far... ###3
                if mod then
                    s, m = self.os:sendWinAhkKeys( text.win )
                else
                    s, m = self.os:sendUnmodifiedKeys( text.win )
                end
            else
                self:callingError( "win text must be included if windows platform" )
            end
        else
            if text.mac then
                local mod = text.mod == true or text.mac:find( "Cmd" ) or text.mac:find( "Option" ) or text.mac:find( "Ctrl" ) or text.mac:find( "Shift" ) -- to send these strings unmodified, use vanilla send-keys or set mod to false.
                if mod then
                    s, m = self.os:sendMacEncKeys( text.mac )
                else
                    s, m = self.os:sendUnmodifiedKeys( text.mac )
                end
            else
                self:callingError( "mac text must be included if mac platform" )
            end
        end
    else
        self:callingError( "text must not be table" )
    end
    if not noYield then
        LrTasks.yield()
    elseif type( noYield ) == 'number' then
        LrTasks.sleep( noYield ) -- had better be short
    elseif type( noYield ) == 'boolean' then
        -- it's 'true'.
    else
        error( "bad arg type" )
    end
    return s, m
end



--- Send windows modified keystrokes to lightroom in AHK encoded format.
--
--  @deprecated - call sendKeys with a table param instead.
--
--  @param      keys    i.e. mash the modifiers together (any order, case sensitive), followed by a dash, followed by the keystrokes mashed together (order matters, but case does not).
--  @param      yieldSpec I've found, more times than not, a yield helps the keystrokes take effect. If yielding after sending the keys is causing more harm than good, set this arg to true.
--    <br>          Set to numeric value for sleep before returning.
--
--  @usage      e.g. '{Ctrl Down}s{Ctrl Up}' - note: {Ctrl}s doesn't cut it - probably whats wrong with vbs/powershell versions.
--  @usage      Direct keystrokes at Lightroom proper, NOT dialog boxes, nor metadata fields, ...
--      
--  @return     status(boolean): true iff command to send keys executed without an error.
--  @return     message(string): if status successful: the command issued, else error message (which includes command issued).
--
function App:sendWinAhkKeys( keys, yieldSpec )

    if WIN_ENV then
        local s, m = self.os:sendUnmodifiedKeys( keys ) -- all keystrokes go through ahk.exe file now.
        if not yieldSpec then -- yield-spec is nil, or false
            LrTasks.yield() -- ok not done in loop.
        elseif type( yieldSpec ) == 'boolean' then -- no-yield is true
            return -- yield/sleep-ing to be handled externally, if need be.
        else -- type had better be numeric.
            LrTasks.sleep( yieldSpec )
        end
        return s, m
    else
        self:callingError( "Don't send windows keys on mac." )
    end
end



--  Could have emulated ahk format until ahk works well enough on Mac.
--  For now, plugin author is tasked with issuing two different sequences of things
--  depending on platform.
--      
--- Send mac modified keystrokes to lightroom, in proprietary encoded format as follows:
--      
--  @deprecated - call sendKeys with a table param instead.
--
--  @param      keys    i.e. mash the modifiers together (any order, case sensitive), followed by a dash, followed by the keystrokes mashed together (order matters, but case does not).
--  @param      yieldSpec I've found, more times than not, a yield helps the keystrokes take effect. If yielding after sending the keys is causing more harm than good, set this arg to true.
--    <br>          Set to numeric value for sleep before returning.
--
--  @usage      e.g. 'CmdOptionCtrlShift-FS'
--  @usage      Direct keystrokes at Lightroom proper, NOT dialog boxes, nor metadata fields, ...
--
--  @return     status(boolean): true iff command to send keys executed without an error.
--  @return     message(string): if status successful: the command issued, else error message (which includes command issued).
--
function App:sendMacEncKeys( keys, yieldSpec )
    if MAC_ENV then
        local s, m = self.os:sendModifiedKeys( keys )
        if not yieldSpec then -- yield-spec is nil or false.
            LrTasks.yield()
        elseif type( yieldSpec ) == 'boolean' then -- no-yield is true.
            return -- yield/sleep-ing to be handled externally, if need be.
        else -- type had better be numeric.
            LrTasks.sleep( yieldSpec )
        end
        return s, m
    else
        error( "Don't send mac keys on windows." )
    end
end



--- Checks for new version of plugin to download.
--
--  @param      autoMode        (boolean) set true if its an auto-check-upon-startup mode, so user isn't bothered by version up-2-date message.
--
--  @usage      Requires global xmlRpc object constructed with xml-rpc service URL.
--  @usage      Does not return anything - presents dialog if appropriate...
--
function App:checkForUpdate( autoMode )
    self:call( Call:new{ name = 'Check for Update', async=true, main=function( call )
        local id = self:getPluginId()
        local status, msgOrValues = xmlRpc:sendAndReceive( "updateCheck", id )
        if status then
            local values = msgOrValues
            local currVer = self:getVersionString()
            assert( currVer ~= nil, "no ver" )
            if #values ~= 2 then
                app:show{ error="Wrong number of values (^1) returned by server when checking for update", #values }
                return
            end
            if type( values[1] ) ~= 'string' then
                app:show{ error="1st return value bad type: ^1", type( values[1] ) }
                return
            end
            if type( values[2] ) ~= 'string' then
                app:show{ error="2nd return value bad type: ^1", type( values[2] ) }
                return
            end
            local latest = values[1]
            local download = values[2]
            if not str:is( download ) then
                download = self:getPluginUrl()
            end
            local name = self:getPluginName()
            if currVer ~= latest then
                -- Debug.logn( "new ver: ", str:format( "^1 from ^2", latest, download ) )
                if dialog:isOk( str:fmt( "There is a newer version of '^1' (current version is ^2).\n \nNewest version is ^3 - click 'OK' to download.", name, currVer, latest ) ) then
                    LrHttp.openUrlInBrowser( download )
                end
            elseif not autoMode then
                app:show{ info="^1 is up to date at version: ^2", name, currVer }
            else
                self:logInfo( str:fmt( "Check for update result: ^1 is up to date at version: ^2", name, currVer ) )
            end
        else
            local msg = msgOrValues
            app:show( "Unable to check for newer version of '^1' - ^2", app:getPluginName(), msg )
        end
    end } )
end



--- Updates plugin to new version (must be already downloaded/available).
--
function App:updatePlugin()
    if gbl:getValue( 'upd' ) then
        upd:updatePlugin() -- returns nothing.
    else
        self:show( { error="Updater not found - please report this problem - thanks." } )
    end
end



--- Updates plugin to new version (must be already downloaded/available).
--
function App:uninstallPlugin()
    self:call( Call:new{ name = 'Uninstall Plugin', async=true, guard=App.guardVocal, main=function( call )
        -- plugin need not be enabled to be uninstalled.
        local id = self:getPluginId()
        local appData = LrPathUtils.getStandardFilePath( 'appData' )
        local pluginFolderName = LrPathUtils.leafName( _PLUGIN.path )
        local modulesPath = LrPathUtils.child( appData, "Modules" ) -- may or may not already exist.
        local path = LrPathUtils.child( modulesPath, pluginFolderName )
        local name = LrPathUtils.leafName( path )
        local base = LrPathUtils.removeExtension( name )
        if path == _PLUGIN.path then
            if not dia:isOk( str:fmt( "Are you sure you want to remove ^1 from ^2?", app:getPluginName(), path ) ) then
                app:show{ info="Plugin has not been uninstalled - nothing has changed." }
                return
            end
            local answer = app:show{ info="Remove plugin preferences too? *** If unsure, then answer 'No'.",
                                     buttons={ dia:btn( "Yes, permanently remove all plugin preferences", 'ok' ), dia:btn( "No, I'm not sure this is a good idea", 'no' ) } }
            if answer == 'cancel' then
                app:show{ info="^1 has not been uninstalled - nothing has changed.", app:getPluginName() }
                return
            end
            local s, m = fso:moveToTrash( path )
            if s then
                -- prompt comes later (below).
            else
                app:show{ error="Unable to remove plugin, error message: ^1", m }
                return 
            end            
            if answer == 'ok' then
                for k, v in prefs:pairs() do
                    prefs[k] = nil
                end
                app:show{ info="^1 has been uninstalled and its preferences have been wiped clean - restart Lightroom now.", app:getPluginName() }
            elseif answer == 'no' then
                app:show{ info="^1 has been uninstalled, but preferences have been preserved in case of later re-install - restart Lightroom now.", app:getPluginName() }
            else
                error( "bad answer" )
            end
        else
            app:show{ warning="You must use the plugin manager's 'Remove' button to uninstall this plugin." }
        end
    end } )
end



--- Sleep until times up, or global shutdown flag set.
--
--  @usage      Called by background tasks primarily, to sleep in 100 msec (or specified increments up to 1 second), checking shutdown flag each increment.
--              <br>Returns when time elapsed or shutdown flag set.
-- 
function App:sleepUnlessShutdown( time, incr, doneFunc )
    if time == nil then
        app:callingError( "can't sleep for nil" )
    elseif time == 0 then
        LrTasks.yield()
        return
    end
    local startTime = LrDate.currentTime()
    incr = math.min( incr or .1, 1 ) -- 1 second is minimum increment (to honor shutdown), 100msec or shorter (for short intervals) is recommended.
    repeat
        LrTasks.sleep( incr )
        local elapsedTime = LrDate.currentTime() - startTime
        if elapsedTime < time then
            if doneFunc and doneFunc( elapsedTime ) then
                return true -- returned due to done-func
            end
        else
            break
        end
    until shutdown
    -- nothing returned - check shutdown flag in calling context, if desired.
end
App.sleep = App.sleepUnlessShutdown -- function App:sleep( ... )



--- Sleep until times up, or global shutdown flag set.
--
--  @param      timer (App.Timer, required) will be auto-started.
--
--  @usage      Called by background tasks primarily, to sleep in 100 msec (or specified increments up to 1 second), checking shutdown flag each increment.
--              <br>Returns when time elapsed or shutdown flag set.
-- 
function App:sleepTimer( timer, interval )
    app:callingAssert( timer ~= nil, "can't sleep for nil timer" )
    timer:start( interval )
    repeat
        timer:nod()
        if timer:isElapsed() then
            return true -- convenience return var.
        end
    until shutdown
    -- nothing returned - check shutdown flag in calling context, if desired.
end



--- Sleep for a moment if time remaining.
--
function App:waitUnlessShutdown( start, t, incr )
    incr = incr or .1
    -- assert( time ~= nil, "no time" )
    local t2 = LrDate.currentTime() - start
    if t2 > t then -- no more time
        return true
    elseif not shutdown then
        LrTasks.sleep( incr )
        return false -- not timeout.
    else
        return true
    end
end
App.wait = App.waitUnlessShutdown



--- Yield unless too soon.
--
--  @param      count (number, required) initialize to zero before loop, then pass return value back in, in loop.
--  @param      maxCount (number, default 20 ) number of calls to burn before actually yielding
--
--  @usage      Use instead of lr-tasks-yield in potentially lengthy loops, to avoid poor performance.
--
--  @return     count to be passed back in next call.
--
function App:yield( count, maxCount )
    count = count + 1
    if not maxCount then
        maxCount = 20
    end
    if count >= maxCount then
        LrTasks.yield()
        return 0
    else
        return count
    end
end



--- Yield if called from task.
--
function App:yieldIfPossible()
    if LrTasks.canYield() then
        LrTasks.yield()
    end
end



--- Get name of explorer or finder.
--
function App:getShellName()
    return self.os:getShellName()
end    



--- Get control-modified keystroke string for display purposes only.
--
--  <p>Purpose is so Mac users don't have to be bothered with Windows syntax, nor vice versa.</p>
--
--  @usage      Not for issuing keystrokes but for prompting user.
--  @usage      For example: str:format( 'Press ^1 to save metadata first...', app:getCtrlKeySeq( 's' ) )
--  @usage      Sorry about the Windows bias to the method name.
--
function App:getCtrlKeySeq( key )
    if WIN_ENV then
        return "Ctrl-" .. key
    else
        return "Cmd-" .. key
    end
end



--- Get control keyboard sequence for running platform.
--
--  <p>Purpose is so Mac users don't have to be bothered with Windows syntax, nor vice versa.</p>
--
--  @usage      Not for issuing keystrokes but for prompting user.
--  @usage      For example: str:format( 'Press ^1 to save metadata first...', app:getCtrlKeySeq( 's' ) )
--  @usage      Sorry about the Windows bias to the method name.
--
function App:getAltKeySeq( key )
    if WIN_ENV then
        return "Alt-" .. key
    else
        return "Opt-" .. key
    end
end



--- Asserts (synchronous) initialization is complete.
--
--  @usage Call at end of plugin's Init.lua module.
--
--  @usage Dumps declared globals to debug log, if advanced debug enabled.
--
function App:initDone()

    --self._initDone = true
    app:log()
    app:log( "Plugin synchronous initialization has completed.\n" )
    if not self:isAdvDbgEna() then return end
    
    Debug.logn( "Globals (declared):" )
    local g = getmetatable( _G ).__declared or {}
    local c = 0
    for k, v in tab:sortedPairs( g ) do
        local value = gbl:getValue( k )
        local className
        if value ~= nil and type( value ) == 'table' and value.getFullClassName then
            className = value:getFullClassName()
            if className == k then
                className = 'Class'
            end
        else
            className = type( value )
        end
        Debug.logn( str:to( k ), str:to( '(' .. className .. ')' ) )
        c = c + 1
    end
    Debug.logn( "Total:" .. c, '\n' )
    Debug.logn( "Undeclared globals:" )
    local c2 = 0
    for k, v in tab:sortedPairs( _G ) do
        if not g[k] then
            Debug.logn( str:to( k ) )
            c2 = c2 + 1
        end
    end
    
    Debug.logn( "Total undeclared globals:" .. c2, '\n' )

    --[[ *** this takes a really long time, for some plugins, like ChangeManager, so uncomment on an as-needed basis.
    if self:isVerbose() then
        local globalsByFile = Require.newGlobals() -- now cleared.
        Debug.logn( "Global details by file: ", Debug.pp( globalsByFile ) )
    end
    --]]
    
end



--- Open debug log in default app for viewing.
--
--  @usage wrapped internally
--
function App:showDebugLog()
    self:call( Call:new { name='Show Debug Log', async=not LrTasks.canYield(), main=function( call )
        local logFile = Debug.getLogFilePath()
        if fso:existsAsFile( logFile ) then
            local ext = LrPathUtils.extension( logFile )
            self:openFileInDefaultApp( logFile, true )
        else
            self:show( { info="No debug log file: ^1" }, logFile )
        end
    end } )
end



--- Clear debug log by moving to trash.
--
--  @usage wrapped internally
--
function App:clearDebugLog()
    self:call( Call:new { name='Clear Debug Log', async=true, guard=App.guardSilent, main=function( call )
        local logFile = Debug.getLogFilePath()
        if fso:existsAsFile( logFile ) then
            local s, m = fso:moveToTrash( logFile )
            if s then
                self:show( { info="Debug log cleared." } )
            else
                self:show( { error=m } )
            end
        else
            self:show( { info="No debug log file: ^1" }, logFile )
        end
    end } )
end



--- Find framework resource reference.
--
--  @usage      Only use I know of at present is for displaying a vf-picture.
--  @usage      Supports png - Lr doc says what else...
--  @usage      Assures resource comes from framework and not user plugin resource.
--
--  @return     abs path or nil if no resource. If Adobe changes type, so will this function.
--
function App:findFrameworkResource( name )
    assert( Require.frameworkDir ~= nil, "No framework dir." )
    local path
    if LrPathUtils.isAbsolute( Require.frameworkDir ) then
        path = LrPathUtils.child( Require.frameworkDir, 'Resources' )
    else
        local dir = LrPathUtils.child( _PLUGIN.path, 'Framework' )
        path = LrPathUtils.child( dir, 'Resources' )
    end
    local file = LrPathUtils.child( path, name )
    if fso:existsAsFile( file ) then
        return file
    else
        return nil -- picture component deals with this OK.
    end
end



--- Get framework resource reference.
--
--  @usage      Only use I know of at present is for displaying a vf-picture.
--  @usage      Supports png - Lr doc says what else...
--  @usage      Assures resource comes from framework and not user plugin resource.
--
--  @return     abs path or nil if no resource. If Adobe changes type, so will this function.
--
function App:getFrameworkResource( name )
    local rsrc = self:findFrameworkResource( name )
    if rsrc then
        return rsrc
    else
        self:logErr( "Missing framework resource: ^1", name )
        return nil -- picture component deals with this by displaying a "blank" picture.
    end
end



--- Get find plugin or framework resource reference.
--
--  @usage      Only use I know of at present is for displaying a vf-picture.
--  @usage      Supports png - Lr doc says what else...
--  @usage      Resource will be searched for in all require-paths, so plugin resources take priority (as long as they are in folder called 'Resource').
--              but will also return framework resources.
--
--  @return     abs path or nil if no resource. If Adobe changes type, so will this function.
--
function App:findResource( name )
    local file = Require.findFile( str:fmt( 'Resources/^1', name ) ) -- searches '.' first, then framework...
    if fso:existsAsFile( file ) then
        return file
    else
        return nil -- picture component deals with this by displaying a "blank" picture.
    end
end



--- Get plugin or framework resource reference.
--
--  @usage      Only use I know of at present is for displaying a vf-picture.
--  @usage      Supports png - Lr doc says what else...
--  @usage      Resource will be searched for in all require-paths, so plugin resources take priority (as long as they are in folder called 'Resource').
--              but will also return framework resources.
--
--  @return     abs path or nil if no resource. If Adobe changes type, so will this function.
--
function App:getResource( name )
    local rsrc = self:findResource( name )
    if rsrc then
        return rsrc
    else
        self:logErr( "Missing resource: ^1", name ) -- if you don't wan't an error logged, use find-resource instead.
        return nil -- picture component deals with this by displaying a "blank" picture.
    end
end



--- Reset Lightroom warning dialogs and custom warning dialogs.
--
--  @usage      Be sure to call this instead of the lr-dialogs one.
--
function App:resetWarningDialogs()
    LrDialogs.resetDoNotShowFlag() -- Take care of anything that did NOT go through the framework API, just in case.
    for k, v in self:getGlobalPrefPairs() do
        if str:isStartingWith( k, 'actionPrefKey_' ) then
            self:setGlobalPref( k, false )
        end
    end
end



--- Throw an error in executing context, with built-in formatting.
--
--  @param          m (string, required) error message.
--  @param          ... formating substitutions.
--
--  @usage          Example: if var == nil then app:error( "var ^1 must not be nil", varNumber )
--
function App:error( m, ... )
    if m == nil then
        m = 'unknown error'
    else
        m = str:fmtx( str:to( m ), ... ) -- assure m is string, so no error is thrown creating the error message.
        if m == "" then -- assure something better than the empty string to throw.
            m = "invalid error message"
        end
    end
    error( m, 2 ) -- throw in caller of this function.
end



--- formatted assertion.
--
function App:assert( c, m, ... )
    if c then
        return c
    else
        error( str:fmtx( "Assertion failed - " .. ( m or "???" ), ... ), 2 )
    end
end



--- formatted calling assertion.
--
function App:callingAssert( c, m, ... )
    if c then
        return c
    else
        error( str:fmtx( "Assertion failed - " .. ( m or "???" ), ... ), 3 )
    end
end



--- Throw an error in calling context, with built-in formatting.
--
--  @param          m (string, required) error message.
--  @param          ... formating substitutions.
--
--  @usage          Example: if param[1] == nil then app:callingError( "param ^1 must not be nil", paramNumber )
--
function App:callingError( m, ... )
    if m == nil then
        m = 'unknown error'
    else
        m = str:fmtx( m, ... )
    end
    error( m, 3 ) -- throw in context of function calling caller of this function.
end



--- Get path separator, appropriate for OS.
function App:getPathSep()
    return WIN_ENV and "\\" or "/"
end
App.pathSep = App.getPathSep -- Synonym: App:pathSep



--- Get (root) settings key, format undefined, and name.
--
function App:getSettingsKey( name )
    -- name = name or app:getGlobalPref( 's e t t i n g s N a m e' )
    name = name or app:getGlobalPref( 'presetName' )
    if not str:is( name ) then
        name = 'Default' -- this pref is currently not being initialized ###2 - ?
    end
    if gbl:getValue( 'systemSettings' ) then
        return systemSettings:getKey( 'settings', name ), name
    else
        self:callingError( "No system settings" )
    end
end



--- Get preset names in popup-menu-compatible items format.
--
function App:getPresetNameItems()
    assert( self.prefMgr, "no pref mgr" )
    local names = self.prefMgr:getPresetNames()
    local it = {}
    for i, name in ipairs( names ) do
        it[#it + 1] = { title=name, value=name }
    end
    return it
end



--- Get array of preset names, sorted alphabetically.
--
function App:getPresetNames()
    assert( self.prefMgr, "no pref mgr" )
    return self.prefMgr:getPresetNames()
end



--- Get active preset name.
--
function App:getPresetName()
    if self.prefMgr then
        return self.prefMgr:getPresetName()
    else
        return "" -- check for this if need be.
    end
end



--- Assure pref support file, if managed presets.
--
function App:assurePrefSupportFile( presetName )
    if self.prefMgr then
        self.prefMgr:assurePrefSupportFile( presetName )
    end
end



--- Make folder link.
--
function App:makeFolderLink( linkPath, folderPath )
    return self.os:makeFolderLink( linkPath, folderPath )
end
    
    

--- Make file link.
--
function App:makeFileLink( linkPath, folderPath )
    return self.os:makeFileLink( linkPath, folderPath )
end
    


--- Get number of times this plugin has been reloaded, or number times Lr has been restarted since prefs were reset.
--
function App:getRunCount()
    local v = self:getGlobalPref( 'runCount' )
    if type( v ) == 'number' then
        return v
    else
        return 0
    end
end



--- Determine if this is the first time the plugin has been run, since init, or since prefs cleared.
--
function App:isFirstRun()
    local rc = self:getRunCount()
    return rc == 1
end    
   


-- Get's both maximum and minimum display dimensions, as table { max = { width=..., height=... }, min = { width=..., height=... } }
--
function App:getDisplayDimensions()
    local max = { width=0, height=0 }
    local min = { width=math.huge, height=math.huge }
    local dispInfo = LrSystemInfo.displayInfo()
    for i, disp in ipairs( dispInfo ) do
        max.width = math.max( disp.width, max.width )
        max.height = math.max( disp.height, max.height )
        min.width = math.min( disp.width, min.width )
        min.height = math.min( disp.height, min.height )
    end
    return { max=max, min=min }
end
   
   
    
return App
