--[[
        Export.lua
--]]

local Export, dbg = Object:newClass{ className = 'Export' }



Export.dialog = nil
Export.exports = {}



--- Constructor for extending class.
--      
function Export:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor to create the export object that represents the export dialog box.
--      
--  <p>One of these objects is created when the export dialog box is presented,
--  if it has not already been.</p>
--
function Export:newDialog( t )
    local o = Object.new( self, t )
    return o
end



--- Create a new export object.
--      
--  <p>One of these objects is created EACH time a new export is initiated,
--  then killed at export completion - supports multiple concurrent exports,
--  without interference (assuming a different set of photos is selected,
--  otherwise all kinds of interference...)</p>
--                          
--  @param t     Parameter table<ul>
--                  <li>exportContext
--                  <li>functionContext</ul>
--                          
--  @return      Export object
--
function Export:newExport( t )

    local o = Object.new( self, t )
	o.exportParams = o.exportContext.propertyTable
	
    --Debug.lognpp( o.exportParams )
    --Debug.showLogFile()
    --Debug.pause()
	
    o.exportSession = o.exportContext.exportSession
    o.functionContext = o.functionContext
    o.exportProgress = nil -- initialized when service gets under way (after renditions have been checked)
    o.nPhotosToExport = 0
    o.nPhotosToRender = 0 -- initialized in service function.
    o.nPhotosRendered = 0 -- counted during service.
    o.nRendFailures = 0
    o.filenamePreset = nil
    o.filenamePresetCache = nil
    --Debug.lognpp( o.exportParams )
    --Debug.showLogFile()
    o.srvc = nil
    
    --intercom:listen( Export.callback, o, { ["com.robcole.lightroom.ExportManager"]=true } ) - works fine, but bad design.
    
    intercom:broadcast{ exportState='ready' } -- reminder: new-export is called each time an export is initiated.
    
    return o
    
end



--- get export settings from an export preset file. ###2 note: does not yet support automatic detection of export preset folder.
--
--  @param params (table) members:
--      <br>    file
--
--  @return export settings, or throws error trying.
--
function Export:getSettingsFromPreset( params )
    app:callingAssert( type( params ) == 'table', "params must be table" )
    local file = params.file or app:callingError( "no file specified in params" )
    local ext = LrPathUtils.extension( file )
    if not ext == "lrtemplate" then
        app:error( "not an export preset (doesn't end with .lrtemplate): ^1", file )
    end
    if LrPathUtils.isRelative( file ) then
        app:error( "file must be absolute path, '^1' isn't.", file )
    end
    if not fso:existsAsFile( file ) then
        app:error( "preset not found: ^1", file )
    end
    pcall( dofile, file )
    app:assert( _G.s ~= nil, "bad preset: ^1", file )
    local exportServiceProvider = _G.s.value["exportServiceProvider"]
    local exportServiceProviderTitle = _G.s.value["exportServiceProviderTitle"]
    local pluginId = _G.s.value["exportServiceProvider"] -- synonym
    local pluginName = _G.s.value["exportServiceProviderTitle"] -- ditto.
    local _exportSettings = {}
    local prefixLen = string.len( exportServiceProvider ) + 2 -- compute amount to skip over in user keys.
    for k, value in pairs(_G.s.value) do
        local is = str:isStartingWith( k, exportServiceProvider )
        if is then -- its an service specific setting (e.g. log-file).
            local key = string.sub( k, prefixLen ) -- remove the extraneous user key prefix.
            _exportSettings[key] = value
            -- app:logV( "Saving User setting, name: ^1, value: ^2", key, str:to( value ) )
        elseif k == 'exportFilters' then
            if not tab:isEmpty( value ) then
                app:error( "Export filters (post-process actions) are not supported, as in '^1'", file ) -- I suppose they could simply be ignored, but it seems one should be picking a preset without filters..
            else
                -- ignore (all export filters were removed).
            end
        else
            local key = 'LR_' .. k -- add the required lightroom key prefix.
            -- app:logV( "Saving Lightroom setting, name: ^1, value: ^2", key, str:to( value ) )
            _exportSettings[key] = value
        end
    end
    return _exportSettings
end



--- Get export destination directory
--
--  @usage consider disallowing "Choose Later" option if you are planning to use this function as is - it will prompt for the folder, but so will Lightroom making for an obnoxious double-prompt: probably not what you want.
--
function Export:getDestDir( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local typ = props.LR_export_destinationType
    local mainDir = props.LR_export_destinationPathPrefix -- path
    local subDir = props.LR_export_destinationPathSuffix -- name
    local typ = props.LR_export_destinationType
    local useSub = props.LR_export_useSubfolder 
    if typ == 'specificFolder' then
        if useSub then
            return LrPathUtils.child( mainDir, subDir )
        else
            return mainDir
        end
    elseif typ == 'sourceFolder' then
        local srcDir = LrPathUtils.parent( lrMeta:getRawMetadata( photo, 'path', cache, true ) )
        if useSub then
            return LrPathUtils.child( srcDir, subDir )
        else
            return srcDir
        end
    elseif typ == 'chooseFolderLater' then
        if self.destDirChosen then
            return self.destDirChosen
        else
            self.destDirChosen = dia:selectFolder{
                title = "Choose export destination folder",
                canCreateDirectories = true,
            }
            if self.destDirChosen == nil then
                app:error( "Unable to obtain export directory." )
            end
            return self.destDirChosen
        end
    else
        app:error( "Unable to compute destination dir when 'Export To' is set to '^1'", typ )
    end
end



--- Get export destination extension - with correct case.
--
--  @usage consider disallowing "Choose Later" option if you are planning to use this function as is - it will prompt for the folder, but so will Lightroom making for an obnoxious double-prompt: probably not what you want.
--
function Export:getDestExt( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local fmt = lrMeta:getRawMetadata( photo, 'fileFormat', cache, true )
    local ext
    if props.LR_format == 'ORIGINAL' then
        ext = LrPathUtils.extension( lrMeta:getRawMetadata( photo, 'path', cache, true ) )
    elseif fmt == 'VIDEO' then
        if app:lrVersion() >= 4 then
            --Debug.pause( props.LR_export_videoFormat, props.LR_export_videoPreset )
            if props.LR_export_videoFormat == 'original' or props.LR_export_videoPreset == 'original' then -- I think it's just the format, not the preset, which will be 'original', but hey...
                ext = LrPathUtils.extension( lrMeta:getRawMetadata( photo, 'path', cache, true ) )
            elseif props.LR_export_videoFormat ==  "3f3f3f3f-4450-5820-fbfb-fbfbfbfbfbfb" then -- ###2 not sure if this will be the same in all Lr copies, so better to check using some other means if possible.
                app:error( "dpx video exports to a directory, not a file, therefore file extension does not make sense." )
            else
                for i, vp in ipairs( LrExportSettings.videoExportPresets() ) do
                    local name = LrStringUtils.lower( vp:name() )
                    if props.LR_export_videoPreset:find( name, 1, true ) then -- e.g. "SIZE_max" 
                        ext = vp:extension()
                        break
                    end
                end
                if not ext then -- not present in standard presets
                    -- try custom presets for this plugin.
                    for i, vp in ipairs( LrExportSettings.videoExportPresetsForPlugin( _PLUGIN ) ) do
                        --local name = LrStringUtils.lower( vp:name() )
                        --if props.LR_export_videoPreset:find( name, 1, true ) then -- e.g. "SIZE_max" 
                            ext = vp:extension()
                            if ext then
                                break
                            end
                        --end
                    end
                end
                if not ext then
                    app:error( "Unable to determine destination video extension from video-preset code: ^1", props.LR_export_videoPreset )
                end
            end
        else
            ext = LrPathUtils.extension( photo:getRawMetadata( 'path' ) )
        end
    elseif str:is( props.LR_format ) then
        ext = LrExportSettings.extensionForFormat( props.LR_format ) -- seems to be lower case regardless of case setting, at least when "rename" is disabled,
        if not ext then
            app:error( "Unable to compute destination extension for format: ^1", props.LR_format )
        end
    else
        app:error( "No lr-format in props" )
    end
    if props.LR_extensionCase == 'lowercase' then
        ext = LrStringUtils.lower( ext )
    else
        ext = LrStringUtils.upper( ext )
    end
    return ext
end



function Export:_isSeqNum( tokens )
    if tokens:find( "sequenceNumber" ) then -- example: {{naming_sequenceNumber_1Digit}}.
        return true
    end
end



--- Process change to export-to export param - for cases when export location may have some restrictions.
--
function Export:processExportLocationChange( props, name, value )
    local checkSubfolder
    if name == 'LR_export_useSubfolder' then
        checkSubfolder = value and props.LR_export_destinationPathSuffix
    elseif name == 'LR_export_destinationPathPrefix' then
        Debug.pause( "No handling in base class for path prefix" )
    elseif name == 'LR_export_destinationPathSuffix' then
        checkSubfolder = value
    elseif name == 'LR_destinationType' then
        if value == 'chooseFolderLater' then
            app:show{ 'Export location can not be chosen later - please choose another option.' }
            props.LR_export_destinationType = 'specificFolder'
        else
            Debug.pause( "No handling in base class for normal destination types." )
        end
    else
        Debug.pause( "Unrecognized property name - ignored", name, value )
        return
    end
    if checkSubfolder then
        Debug.pause( "No handling in base class for subfolder" )
    else
        Debug.pause( "Not checking subfolder" )
    end
end



function Export:_getVerifiedPreset( tokens )
    local presets = self.filenamePresetLookup[tokens]
    if presets then
        for i, p in ipairs( presets ) do
            if p.verified then
                return p
            end
        end
    end
end




--- Process change to export-filenaming property - for cases when export filenaming may have some restrictions.
--
function Export:processExportFilenamingChange( props, name, value )
    self.filenamePreset = nil -- assume nothing about chosen preset
    local photo = cat:getAnyPhoto() -- prefers most-sel, but accepts filmstrip[1] or all[1].
    if photo == nil then
        app:show{ warning="You must have at least one photo in catalog to assure filenaming is copacetic", actionPrefKey="Filenaming pre-check" }
        return
    end
    self:_assurePresetCache( props, photo ) --  true ) -- true => freshen for each change, since preset could be added - UPDATE: added presets don't work anyway, so may as well handled as non-existent.
    local checkTokens
    if name == 'LR_renamingTokensOn' then
        checkTokens = value and props.LR_tokens
    elseif name == 'LR_tokens' then
        checkTokens = value
    elseif name == 'LR_extensionCase' then
        --Debug.pause( "No handling in base class for extension case change." )
    elseif name == 'LR_tokenCustomString' then
        --Debug.pause( "No handling in base class for custom text change." )
    elseif name == 'LR_initialSequenceNumber' then
        --Debug.pause( "No handling in base class for start number change." )
    else
        --Debug.pause( "Unrecognized property name - ignored", name, value )
        return
    end
    if checkTokens then
        local filenamePreset = self:_getVerifiedPreset( checkTokens ) -- note: not a true preset object, but a reference to some harvested info...
        if filenamePreset then
            if self:_isSeqNum( filenamePreset.tokenString ) then
                --Debug.pause( "No handling in base classe for filenaming presets with sequence number." )
            end
            assert( checkTokens == filenamePreset.tokenString, "token mismatch" )
            --Debug.pause( checkTokens )
            local s, t = LrTasks.pcall( self.getDestBaseName, self, props, photo, nil ) -- nil => no cache.
            if s then
                --Debug.pause( t )
                app:logv( "Example file base-name: ^1", t )
            else
                app:show{ warning="There are some issues with the chosen filenaming preset - ^1", t }
            end
        else
            --Debug.pause( checkTokens )
            app:show{ warning="You may need to save filenaming preset and/or restart Lightroom to use the chosen filenaming scheme." }
            return
        end
    else
        -- Debug.pause( "not checking tokens" )
    end
end



function Export:_assurePresetCache( props, photo )
    if self.filenamePresetCache == nil then
        local cust
        local seq
        if str:is( props['LR_tokenCustomString'] ) then
            cust = props.LR_tokenCustomString
        else
            cust = "custom-text"
        end
        if props['LR_initialSequenceNumber'] then
            seq = props.LR_initialSequenceNumber
        else
            seq = ""
        end
        self.filenamePresetCache = {}
        self.filenamePresetLookup = {}
        -- populate filenamePresetCache - tokenString only is required.
        local dir = LrPathUtils.getStandardFilePath( 'appData' )
        local fdir = LrPathUtils.child( dir, 'Filename Templates' )
        gbl:initVar( "ZSTR", LOC, true )
        for de in LrFileUtils.files( fdir ) do -- I assume lightroom will not find templates in subfolders - certainly you can't put them there using native UI.
            repeat
                if LrPathUtils.extension( de ) ~= 'lrtemplate' then
                    break
                end
                local name = LrPathUtils.removeExtension( LrPathUtils.leafName( de ) )
                local sts, ret = pcall( dofile, de ) -- global 's'.
                if not sts then
                    app:logErr( "Invalid filename template file: ^1 - ret: ^2", de, ret )
                    break
                end
                if not s or not s.deflated then
                    app:logErr( "Invalid filename template file: ^1", de )
                    break
                end
                if not s.deflated[1] then
                    app:logWarning( "No tokens in: ^1", de )
                    break
                end
                if not s.id then
                    app:logv( "no id for filename preset '^1'", name ) -- not sure why this is happening now, but can't use it without an ID.
                    break
                end
                local tokens = {}
                for i, v in ipairs( s.deflated[1] ) do
                    local token
                    if type( v ) == 'table' then
                        if v.value ~= nil then
                            tokens[#tokens + 1] = "{{" .. v.value .. "}}"
                        else
                            --Debug.pause( v )
                        end
                    else
                        tokens[#tokens + 1] = v
                    end
                end
                if #tokens > 0 then
                    --Debug.pause( name )
                    local tokenString = table.concat( tokens, "" )
                    self.filenamePresetCache[name] = { tokenString = tokenString, path=de, id=s.id, name=name }
                    app:logv( "Adding preset to cache, name=^1, for tokens=^2", name, tokenString )
                    if not self.filenamePresetLookup[tokenString] then
                        self.filenamePresetLookup[tokenString] = { self.filenamePresetCache[name] } -- there can be more than one.
                    else
                        local a = self.filenamePresetLookup[tokenString]
                        a[#a + 1] = self.filenamePresetCache[name]
                    end
                else
                    --Debug.pause( s )
                end
            until true
        end
        
        if not photo then
            photo = cat:getAnyPhoto()
            if not photo then
                app:logWarning( "Unable to validate presets in cache since there are no photos in the catalog to use for trial." )
                -- note: no presets will be verified.
                return
            end
        end
        for name, id in pairs( LrApplication.filenamePresets() ) do
            repeat
                if not id then
                    app:logv( "no id for filename preset '^1' - skipped", name )
                    break
                end
                if not self.filenamePresetCache[name] then
                    app:logv( "not cached - skipped" )
                    break
                end
                local sts, filename = LrTasks.pcall( photo.getNameViaPreset, photo, id, cust, seq )
                if sts then
                    app:logv( "yep: ^1, ^2", name, id )
                    self.filenamePresetCache[name].verified = true
                    self.filenamePresetCache[name].id = id -- use true ID from filename-preset, rather than internal uuid.
                else
                    app:logv( "nope (^4): ^1, ^2 - tokens: ^3", name, id, self.filenamePresetCache[name].tokenString, filename )
                    self.filenamePresetCache[name].verified = false
                end
                --if filename == "custom-text" then - custom-name only is actually a perfectly valid naming preset in some cases.
                --    app:logv( '    - "^1" preset may be not worth having, in any case consider entering something more interesting for custom text.', name )
                --end
            until true
        end
        
    else
        --Debug.pause()
    end
end




--- Get export destination filename.
--
function Export:getDestBaseName( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local srcBase = LrPathUtils.removeExtension( LrPathUtils.leafName( lrMeta:getRawMetadata( photo, 'path', cache, true ) ) )
    local basename
    if not props.LR_renamingTokensOn then -- universal:
        basename = srcBase
    else -- rename
        self:_assurePresetCache( props, photo )
        if not self.filenamePreset then
            self.filenamePreset = self:_getVerifiedPreset( props.LR_tokens )
            if not self.filenamePreset then
                app:error( "You must restart Lightroom in order to be able to use selected filenaming preset" )
            end
        else
            --Debug.pause( self.filenamePreset.name )
        end
        if self.filenamePreset then
            --Debug.lognpp( props )
            --Debug.showLogFile()
            local s
            if self.seqNum == nil then
                self.seqNum = props.LR_initialSequenceNumber or 1
            else
                self.seqNum = self.seqNum + 1
            end
            if not self.filenamePreset.id then
                app:error( "how's there a preset with no ID? named '^1'", self.filenamePreset.name )
            end
            s, basename = LrTasks.pcall( photo.getNameViaPreset, photo, self.filenamePreset.id, props.LR_tokenCustomString or "", self.seqNum )
            if s then
                if basename then
                    if #basename > 0 then
                        --Debug.pause( self.filenamePreset['name'], self.filenamePreset.tokenString )
                        app:logv( "File base-name based on preset (^2) : ^1 (tokens in preset=^3)", basename, self.filenamePreset.name, self.filenamePreset.tokenString )
                    else
                        app:error( "Invalid file base-name (^1) from preset - must be at least 1 characters, preset name: ^2, tokens in preset: ^3", basename, self.filenamePreset.name, self.filenamePreset.tokenString )
                    end
                else
                    app:error( "Unable to obtain filename from preset." )
                end
            else
                --Debug.pause( self.filenamePreset.name )
                app:error( "Unable to get filename via preset - id: ^1, error message: ^2", self.filenamePreset.id, basename )
            end
        else
            app:error( "Unable to obtain preset for filenaming - you must use a saved preset for filenaming, custom/unsaved won't cut it - also you may have to restart Lightroom if it's a newly created preset." )
        end
    end
    assert( basename ~= nil, "no file basename" )
    return basename
end



--- Get export destination filename.
--
function Export:getDestFilename( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local basename = self:getDestBaseName( props, photo, cache )
    local ext = self:getDestExt( props, photo, cache ) -- requires special handling for original formats.
    assert( ext ~= nil, "no ext" )
    assert( basename ~= nil, "no file basename" )
    return LrPathUtils.addExtension( basename, ext )
end



--- Get export destination path for photo.
--
function Export:getDestPath( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    
    -- local dir = self:getDestDir( photo, cache ) -- this till 28/Aug/2013 0:25 which is wrong ###4 - but, it seems no plugin was calling it, so if no problems come 2015, delete this comment.
    local dir = self:getDestDir( props, photo, cache ) -- this @28/Aug/2013 0:26
    
    local filename = self:getDestFilename( props, photo, cache )
    assert( dir ~= nil, "no dir" )
    assert( filename ~= nil, "no filename" )
    local path = LrPathUtils.child( dir, filename )
    return path
end



--[[ *** works, but I really don't want my export plugins listening 24/7 when only exporting relatively briefly.

    Not only that, but I really don't like export-manager's id being hardcoded and essential for correct functioning.

function Export:callback( msg )
    if msg.query == 'Are you managed?' then
        Debug.lognpp( "I'm managed", msg )
        msg.answer = "Yes I am"
        intercom:sendReply( msg )
    else
        Debug.lognpp( "huh?", msg )
        app:logVerbose( "huh?" )
    end
end
--]]


--- Method version of like-named static function.
--      
--  @usage      Base class implementation simply calls the export service method wrapped in an app call.
--  @usage      Derived export class can certainly override this method, but consider overriding the service & finale methods instead.
--  @usage      Called immediately after process-rendered-photos static "boot-strap" function.
--
function Export:processRenderedPhotosMethod()

    dbg( "Export class: ", str:to( self ) )

    local service = Service:new{
         name = app:getAppName() .. ' export',
         object = self,
         main = self.service,
         finale = self.finale,
    }
    
    self.srvc = service
    app:call( service )

end



--- Perform export service wrap-up.
--
--  @usage    Override this method in derived class to log stats...
--  @usage    *** IMPORTANT: This method is critical to export integrity.
--            Derived export class must remember to call it at end of special
--            export finale method.
--
function Export:finale( service, status, message )
    -- assert( self == Export.exports[self.exportContext], "whoami?" )
    -- app:logInfo( str:format( "^1 finale, ^2 rendered.", name, str:plural( self.nPhotosRendered, "photo" ) ) )
    if status then
        app:log( "^1 finished.", service.name ) -- log added 9/Dec/2011. ###2 - not sure if this is kosher here.
        intercom:broadcast{ exportState = 'finished', exportMessage = service.name .. " completed successfully."  } -- default lifetime of 10 seconds should be fine.
    else
        --app:logErr( "^1 terminated due to error - ^2", service.name, str:to( message ) ) - results in a duplicate, since service class itself logs a service error.
        intercom:broadcast{ exportState = 'finished', exportMessage = service.name .. " terminated due to error."  } -- default lifetime of 10 seconds should be fine.
    end    
    Export.exports[self.exportContext] = nil -- *** kill self reference, garbage collection runs later... this is not the cause of ftp reliability problems.
end



-- Determine if export is finished.
--
--[[
function Export:isFinished()
    if self.exportContext then
        if Export.exports[self.exportContext] then
            return false
        end
    end
    return true
end
--]]


--- Called when export is initiated.
--
--  @usage This method helps export manager track managed exports (all exports based on this class are managed).
--
function Export:initiate( service )
    -- fprops:setPropertyForPlugin( _PLUGIN, "exportState", 'running' ) -- ### remove comments in 2013 if no problems.
    -- fprops:setPropertyForPlugin( _PLUGIN, "exportMessage", service.name .. ' in progress' )
    fprops:setPropertyForPlugin( _PLUGIN, "exportState", nil ) -- kill this property for future.
    fprops:setPropertyForPlugin( _PLUGIN, "exportMessage", nil ) -- kill this property for future.
    Debug.logn( "export in progress" )
    intercom:broadcast{ exportState = 'running', exportMessage = service.name .. " in progress"  } -- default lifetime of 10 seconds should be fine.
end



--[[ this needs more thought - problems with managed exports could cause unmanaged exports not to run - not cool.
-- note: can be very time consuming if exporting thousands of photos and not much inherent delay,
-- maybe best to tie to yield counter or something in that case.
-- note: checks for user cancelation via progress scope as well as managed cancelation via export-manager.
function Export:isCanceled()
    if self.srvc.scope and self.srvc.scope:isCanceled() then
        return true
    end
    local exportCanceled = fprops:getPropertyForPlugin( 'com.robcole.lightroom.export.ExportManager', 'exportCanceled', true ) -- re-reading nearly always required when reading a propterty to be set by a different plugin.
    if exportCanceled == nil then
        if self.notManaged == nil then
            self.notManaged = true
            app:logInfo( "Export appears not to be executing in managed environment." )
        end
        return false
    end
    if exportCanceled == 'yes' then
        return true
    elseif exportCanceled == 'no' then
        return false
    else
        app:logError( "bad cancel property value: " .. str:to( exportCanceled ) )
        return false
    end
    -- save for pausterity I guess:
    --app:logInfo( "Export paused." )
    --while exportEnabled == 'no' and not shutdown do
    --    LrTasks.sleep( 1 )
    --    exportEnabled = fprops:getPropertyForPlugin( 'com.robcole.lightroom.export.ExportManager', 'exportEnabled', true ) -- re-reading nearly always required when reading a propterty to be set by a different plugin.
    --end
    --app:logInfo( "Export resuming from pause." )
    --return true -- did pause
end
--]]



--- Service function of base export - processes renditions.
--      
--  <p>You can override this method in its entirety, OR just:</p><ul>
--      
--      <li>checkBeforeRendering
--      <li>processRenderedPhoto
--      <li>processRenderingFailure
--      <li>(and finale maybe)</ul>
--
function Export:service( service )

    if app:isAdvDbgEna() then
        app:logInfo( "Export Params:")
        app:logPropertyTable( self.exportParams ) -- no-op unless advanced debugging is enabled.
        app:logInfo()
    end

    self.nPhotosToExport = self.exportSession:countRenditions()
    self:checkBeforeRendering() -- remove photos not to be rendered.

    app:logInfo( "Exporting " .. str:plural( self.nPhotosToExport, "selected photo" ) )
    app:logInfo( "Rendering " .. str:plural( self.nPhotosToRender, "exported photo" ) )
    app:logInfo( "Export Format: " .. str:to( self.exportParams.LR_format ) )
    app:logInfo()
    
    local title = app:getAppName() .. " rendering " .. str:plural( self.nPhotosToRender, "photo" )
    self.exportProgress = self.exportContext:configureProgress{ title = title }
    
    -- export seems to be canceled just fine, but export filters keep on going.
    -- so an independent progress-scope must be used for cancelable export filters.
    
    for i, rendition in self.exportContext:renditions{ stopIfCanceled = true, progressScope = self.exportProgress } do
    
        -- self:pauseOrNot() -- make sure you call this in the processing loop(s) if you override the service method.
    
        local status, other = rendition:waitForRender()
        if status then
            local photoPath = other
            -- hard to imagine, but status may be OK despite no rendered file, if source photo is corrupt - check added 19/Oct/2012 9:12.
            if fso:existsAsFile( photoPath ) then
                self:processRenderedPhoto( rendition, photoPath )
            else
                self:processRenderingFailure( rendition, str:fmtx( "Lightroom was unable to render photo: ^1", rendition.photo:getRawMetadata( 'path' ) ) )
            end
        else
            local message = other
            self:processRenderingFailure( rendition, message )
        end
        
    end
    
end



--   E X P O R T   D I A L O G   B O X



--- Handle change to properties under authority of base export class.
--      
--  <p>Presently there are none - but that could change</p>
--
--  @usage        Call from derived class to ensure base property changes are handled.
--
function Export:propertyChangeHandlerMethod( props, name, value )
end



--- Do whatever when dialog box opening.
--      
--  <p>Nuthin to do so far - but that could change.</p>
--
--  @usage        Call from derived class to ensure dialog is initialized according to base class.
--
function Export:startDialogMethod( props )
end



--- Do whatever when dialog box closing.
--      
--  <p>Nuthin yet...</p>
--
--  @usage        Call from derived class to ensure dialog is ended properly according to base class.
--
function Export:endDialogMethod( props )
end



--- Standard export sections for top of dialog.
--      
--  <p>Presently seems like a good idea to replicate the plugin manager sections.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically...
--
function Export:sectionsForTopOfDialogMethod( vf, props )
    return Manager.sectionsForTopOfDialog( vf, props ) -- instantiates the proper manager object via object-factory.
end



--- Standard export sections for bottom of dialog.
--      
--  <p>Reminder: Lightroom supports named export presets.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically - presently there are none.
--
function Export:sectionsForBottomOfDialogMethod( vf, props )
end



--   E X P O R T   S U B - T A S K   M E T H O D S


--- Remove photos not to be rendered, or whatever.
--
function Export:checkBeforeRendering()
    self.nPhotosToRender = self.nPhotosToExport
end



--- Process one rendered photo.
--
function Export:processRenderedPhoto( rendition, photoPath )
    self.nPhotosRendered = self.nPhotosRendered + 1
end



--- Process one photo rendering failure.
--
--  @param      message         error message generated by Lightroom.
--
function Export:processRenderingFailure( rendition, message )
    self.nRendFailures = self.nRendFailures + 1
    app:logError( str:fmt( "Photo rendering failed, photo path: ^1, error message: ^2", rendition.photo:getRawMetadata( 'path' ) or 'nil',  message or 'nil' ) )
end



--- Export parameter change handler proper - static function
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.propertyChangeHandler( id, props, name, value )
    if Export.dialog == nil then
        return
    end
    --assert( Export.dialog ~= nil, "No export dialog to handle change." ) - not sure whether the potential for dialog
    -- box to not be created has disappeared or not, hmmm...... ###3 - hasn't been happening though...
    Export.dialog:propertyChangeHandlerMethod( props, name, value )
end



--- Called when dialog box is opening - static function as required by Lightroom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.startDialog( props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog to start." )
    Export.dialog:startDialogMethod( props )
end



--- Called when dialog box is closing.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.endDialog( props )
    if Export.dialog == nil then
        return
    end -- ###3 ditto
    assert( Export.dialog ~= nil, "No export dialog to end." )
    Export.dialog:endDialogMethod( props )
end



--- Presently, it is imagined to just replicate the manager's top section in the export.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function Export.sectionsForTopOfDialog( vf, props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog for top sections." )
    return Export.dialog:sectionsForTopOfDialogMethod( vf, props )
end



--- Presently, there are no default sections imagined for the export bottom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function Export.sectionsForBottomOfDialog( vf, props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog for bottom sections." )
    return Export.dialog:sectionsForBottomOfDialogMethod( vf, props )
end



--- Called to process render(ing) photos.
--      
--  <p>Photos have not started rendering when this is first called.
--  Once started, they will be rendered in an asynchronous task within Lightroom.
--  Rendering may be started implicitly by invoking the renditions iterator of the export context,
--  or explicitly by calling export-context - start-rendering.</p>
--      
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      1st: creates derived export object via object factory,
--              <br>then calls corresponding method of actual (i.e derived class) export object.
--  @usage      Rendering order is not guaranteed, however experience dictates they are in order.
--
function Export.processRenderedPhotos( functionContext, exportContext )

    if Export.exports[exportContext] ~= nil then
        app:logError( "Export not properly terminated." ) -- this should never happen provided derived class remembers to call base class finale method.
        Export.exports[exportContext] = nil -- terminate improperly...
    end
    Export.exports[exportContext] = objectFactory:newObject( 'Export', { functionContext = functionContext, exportContext = exportContext } )
    Export.exports[exportContext]:processRenderedPhotosMethod()
    
end

-- Note: 'Export' class does not need to explicitly inherit anything.



return Export