--[[
        Xmp.lua
--]]


local Xmp, dbg = Object:newClass{ className = "Xmp", register = true }



--- Constructor for extending class.
--
function Xmp:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @return      new image instance, or nil.
--  @return      error message if no new instance.
--
function Xmp:new( t )
    local o = Object.new( self, t )
    return o
end



--- Determine if xmp file has changed significantly, relative to another.
--
--  @usage              both files must exist.
--
--  @return status      ( boolean, always returned ) true => changed, false => unchanged, nil => see message returned for qualification.
--  @return message     ( string, if status = nil or false ) indicates reason.
--
function Xmp:isChanged( xmpFile1, xmpFile2, fudgeFactorInSeconds )

    if fudgeFactorInSeconds == nil then
        fudgeFactorInSeconds = 2
    end

    local t1 = fso:getFileModificationDate( xmpFile1 )
    local t2
    if t1 then
        t2 = fso:getFileModificationDate( xmpFile2 )
        if t2 then
            -- ###3 could use num:isWithin( t1, t2, fudgeFactorInSeconds ) but best to hold off until able to test.
            if t1 > (t2 + fudgeFactorInSeconds) or t2 > (t1 + fudgeFactorInSeconds) then
                -- proceed, to check content.
            else
                return false, "xmp file has not been modified"
            end
        else
            return nil, "file not found: " .. str:to( xmpFile2 )
        end
    else
        return nil, "file not found: " .. str:to( xmpFile1 )
    end
    
    local c1, m1 = fso:readFile( xmpFile1 )
    if str:is( c1 ) then
        -- reminder: raws have elements, rgbs have attributes
        c1 = c1:gsub( 'MetadataDate.-\n', "" )
        local c2, m2 = fso:readFile( xmpFile2 )
        if str:is( c2 ) then
            c2 = c2:gsub( 'MetadataDate.-\n', "" )
            if c1 ~= c2 then
                return true
            else
                return false, str:fmt( "source xmp modification date is ^1 (^2), and destination is ^3 (^4), but there are no significant content changes", t1, LrDate.timeToUserFormat( t1, "%Y-%m-%d %H:%M:%S" ), t2, LrDate.timeToUserFormat( t2, "%Y-%m-%d %H:%M:%S" ) )
            end
        else
            return nil, "No content in file: " .. xmpFile2
        end
    else
        return nil, "No content in file: " .. xmpFile1
    end
        
end



--- Get xmp file: depends on lrMeta, and metaCache recommended.
--
--  @returns    path (string, or nil) nil if xmp-path not supported.
--  @returns    other (boolean, string, or nil) true if path is sidecar, string if path is nil, nil if path is source file.
--
function Xmp:getXmpFile( photo, metaCache )
    assert( photo ~= nil, "no photo" )
    if metaCache == nil then
        app:logv( "No cache" ) -- inefficient.
        metaCache = lrMeta:createCache() -- create default/empty cache.
    end
    local isVirt = lrMeta:getRawMetadata( photo, 'isVirtualCopy', metaCache, true ) -- accept un-cached.
    assert( isVirt ~= nil, "virt?" )
    if isVirt then
        return false, "No xmp file for virtual copy"
    end
    local fmt = lrMeta:getRawMetadata( photo, 'fileFormat', metaCache, true )
    local path = lrMeta:getRawMetadata( photo, 'path', metaCache, true )
    assert( str:is( path ), "no path" )
    if fmt == 'RAW' then
        return LrPathUtils.replaceExtension( path, "xmp" ), true
    elseif fmt == 'VIDEO' then
        return nil, "No xmp for videos"
    else
        return path
    end
end



--- Get photo path and xmp file (path), if applicable.
function Xmp:getSourceFiles( photo, metaCache )
    local photoFile = lrMeta:getRawMetadata( photo, 'path', metaCache, true ) -- accept uncached.
    local xmpFile = self:getXmpFile( photo, metaCache )
    return photoFile, xmpFile
end



--- Assure the specified photos have settings in xmp, without changing settings significantly.
--
--  ###3 It seems this function is not being called anywhere - certainly xmp-crop could call it, but isn't (I'm guessing I forgot to retrofit or decided not to or something).
--
function Xmp:assureSettings( photo, xmpPath, ets )
    -- get tag from xmp file.
    local function getItem( itemName )
        local itemValue
        ets:addArg( "-S" ) -- short
        ets:addArg( "-" .. itemName )
        ets:addTarget( xmpPath )
        local rslt, errm = ets:execute()
        if str:is( errm ) then
            app:logErr( errm )
            return nil, errm
        end
        if not str:is( rslt ) then
            return nil
        end
        Debug.lognpp( rslt, errm )
        local splt = str:split( rslt, ":" )
        if #splt == 2 then
            if splt[1] == itemName then
                itemValue = splt[2] -- trimmed.
            else
                app:logErr( "No label" )
                return nil -- , "No label"
                --app:error( "No label" )
            end
        else
            --app:logErr( "Bad response (^1 chars): ^2", #rslt, rslt )
            return nil -- , str:fmt( "Bad response (^1 chars): ^2", #rslt, rslt )
        end
        if itemValue ~= nil then
            app:logVerbose( "From xmp, name: '^1', value: '^2'", itemName, itemValue )
            return itemValue
        else
            return nil -- no err.
        end
    end
    for i = 1, 2 do
        local exp = getItem( 'Exposure2012' ) -- always present if there have been saved adjustments.
        if exp then
            return true, ( i == 2 ) and "after adjustment"
        end
        local exp = getItem( 'Exposure' ) -- always present if there have been saved adjustments.
        if exp then
            return true, ( i == 2 ) and "after adjustment"
        end
        if i == 2 then
            return false, "Unable to see applied adjustments reflected in xmp."
        end
        local dev = { noAdj=true }
        local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, "No Adjustment", dev )
        if not preset then error( "no preset" ) end
        local s, m = cat:update( 10, "No Adjustment", function( context, phase )
            -- apply preset
            photo:applyDevelopPreset( preset, _PLUGIN )
        end )
        if s then
            s, m = cat:savePhotoMetadata( photo )
            if s then
                -- loop
            else
                return false, m
            end 
        else
            return false, m
        end
    end
end



--- Transfer develop settings and/or metadata from one image file to another, via xmp.
--
--  @usage *** Calling context MUST assure xmp source file is fresh before calling this function, otherwise data will be lost.
--  @usage *** Likewise, dest xmp file must exist. It need not be so fresh, since it will be mostly redone, but probably a good idea to freshen it too before calling.
--  @usage ###3 It could be that source and/or dest settings need to be pre-assured for dev transfer - not sure atm.
--  @usage The reason this function does not assure-settings is because it's supposed to be callable even if one (or both) photos are not in the catalog - thus only file paths (not photo objects) are available.
--  @usage Does some verbose logging, but offers no captions, so display in calling context, and log result upon return.
--  @usage The code upon which this is based was developed for raw+jpeg plugin. It has since been adapted to (hopefully) cover all file types, and whether files are in catalog or not. But since fresh xmp must be pre-assured, one would need to invoke exiftool to "save metadata" if src or dest file is not photo in catalog.
--
--  @param params (table, required) named parameters:
--      <br>    xmpSrcFile (string, required) source xmp file (will be xmp sidecar or rgb file).
--      <br>    xmpDestFile (string, required) destination xmp file (will be xmp sidecar or rgb file).
--      <br>    xfrDev (boolean, default=true) iff true transfer develop settings.
--      <br>    xfrMeta (boolean, default=true) iff true transfer (other) metadata.
--      <br>    metadataCache (LrMetadata::Cache, optional).
--      <br>    exifToolSession (ExifTool::Session, required) ets.
--
function Xmp:transferMetadata( params )
    local savedXmpFile
    local s, m = app:call( Call:new{ name="Transfer Metadata", main=function( call )

        local srcPhotoFile, destPhotoFile
        local xmpSrcFile, xmpDestFile, xfrDev, xfrMeta, cache, exifToolSession -- , orientRawsToo
        if type( params ) == 'table' then
            --assureSettings = bool:booleanValue( params.assureSettings, true )
            exifToolSession = params.exifToolSession or error( "no exiftool session" )
            xfrMeta = bool:booleanValue( params.xfrMeta, true )
            xfrDev = bool:booleanValue( params.xfrDev, true )
            srcPhotoFile = app:assert( params.srcPhotoFile, "no src photo file" )
            destPhotoFile = app:assert( params.destPhotoFile, "no dest photo file" )
            xmpSrcFile = app:assert( params.xmpSrcFile, "no src xmp file" )
            xmpDestFile = app:assert( params.xmpDestFile, "no dest xmp file" )
            --orientRawsToo = bool:booleanValue( params.orientRawsToo, true )
        else
            app:callingError( "params must be table" )
        end
        
        app:logV( "Transferring develop settings and/or metadata from '^1' to '^2'", xmpSrcFile, xmpDestFile )
    
        local saved
        local srcExt = LrPathUtils.extension( srcPhotoFile ) or "" -- not sure what this returns if no extension.
        local jpgToRaw
        if #srcExt >= 2 then
            local destIsRaw = str:isEqualIgnoringCase( LrPathUtils.extension( xmpDestFile ), 'xmp' ) -- or str:isEqualIgnoringCase( LrPathUtils.extension( srcPhotoFile ), 'dng' )
            if destIsRaw then
                jpgToRaw = str:isEqualIgnoringCase( srcExt:sub( 1, 2 ), 'jp' )
            end
        end
        
        if xfrMeta and xfrDev then
            app:logVerbose( "Transfering all develop settings and metadata" )
            exifToolSession:addArg( "-overwrite_original" )
            exifToolSession:addArg( "-all=" ) -- strip all tags from dest file (note: this makes sense if target is xmp sidecar or jpg being sync'd from raw partner, but if one jpg being sync'd from another: only if the other has it all..
            exifToolSession:addArg( "-tagsFromFile" ) -- this introduces the path of file which will be the source of tags to be added back, but says nothing about which tags.
            exifToolSession:addArg( xmpSrcFile ) -- tags from file..
            exifToolSession:addArg( '-xmp' ) -- see comment below - this part required for "unknown" but critical xmp tags, like brush-strokes.
            exifToolSession:addArg( '-all:all' ) -- updates all "known" tags (xmp and non-xmp), perhaps overlap is inefficient - maybe should use P.H.'s options: "-xmp:all>all:all" ??? ###3
            exifToolSession:addTarget( xmpDestFile ) -- target of transfer.
            local s, m = exifToolSession:execWrite()
            if s then
                app:logv( "metadata and dev settings transferred" )
            else
                app:error( "Unable to transfer metadata and dev settings - ^1", m )
            end
            if jpgToRaw then
                local orientation
                exifToolSession:addArg( "-b" )
                exifToolSession:addArg( "-exif:Orientation" )
                exifToolSession:addTarget( xmpSrcFile )
                local data, errm, more = exifToolSession:execRead()
                if data then
                    orientation = num:numberFromString( data )
                    if orientation then
                        app:logv( "orientation saved" )
                    else
                        app:logVerbose( "*** no orientation in src xmp" ) -- jpg?
                    end
                else
                    Debug.pause( more )
                    app:error( "unable to extract orientation - ^1", errm )
                end
                if orientation then
                    exifToolSession:addArg( "-overwrite_original" ) -- this line added 11/Sep/2013 19:11 - raw+jpeg probably needs it added too, or be retrofitted to use this method. ###1
                    exifToolSession:addArg( str:fmtx( "-xmp-tiff:Orientation=^1", orientation ) )
                    exifToolSession:addArg( "-n" )
                    exifToolSession:addTarget( xmpDestFile )
                    local s, m = exifToolSession:execWrite()
                    if s then
                        app:logv( "orientation updated via exiftool" )
                    elseif m then -- not updated with reason.
                        app:error( "Unable to update orientation - ^1", m )
                    end
                end
            --else - be quiet.
            --    app:logV( "Destination is not raw, so no special orientation handling." )
            end
        else
            savedXmpFile = LrPathUtils.addExtension( xmpDestFile, "xmp" ) -- kinda tacky.
            exifToolSession:addArg( "-overwrite_original" )
            exifToolSession:addArg( "-tagsFromFile" )
            exifToolSession:addArg( xmpDestFile )
            exifToolSession:addArg( "-xmp" )
            exifToolSession:addTarget( savedXmpFile )
            local s, m = exifToolSession:execWrite()
            if s then
                assert( fso:existsAsFile( savedXmpFile ), "exiftool was unable to save xmp metadata" )
            else
                if LrFileUtils.isWritable( xmpDestFile ) then
                    app:assert( LrFileUtils.isReadable( savedXmpFile ), "Not readable: ^1", savedXmpFile )
                    app:error( "unable to save xmp - ^1", m )
                else
                    app:error( "unable to save xmp - '^1' is not writable", xmpDestFile )
                end
            end
            if xfrMeta then
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-all=' )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( xmpSrcFile )
                -- exifToolSession:addArg( "-xmp" ) - can't do this here, or it brings the develop settings too, at least when xfr is raw -> jpg.
                exifToolSession:addArg( "-all:all" )
                exifToolSession:addArg( '--xmp-crs:all' )
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logv( "xmp updated via exiftool" )
                else
                    app:error( "Unable to update xmp - ^1", m )
                end
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( savedXmpFile )
                --exifToolSession:addArg( "-xmp" )
                exifToolSession:addArg( '-xmp-crs:all' )
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logv( "xmp updated" )
                elseif m then -- not updated with reason.
                    app:error( "Unable to update xmp - ^1", m )
                end
            elseif xfrDev then -- can't seem to get orientation jpg->raw correct no matter what I do, so: done for now... ###2
                               -- note: I put that comment there at some point in the past, but @11/Sep/2013 5:35 (Lr5.2RC) orientation is coming from jpg->raw just fine. Hmm..
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-all=' )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( xmpSrcFile )
                exifToolSession:addArg( "-xmp" ) -- must be here for unrecognized paint settings..., but stomps on orientation - verified.
                exifToolSession:addArg( '-xmp-crs:all' )
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logv( "xmp updated" )
                elseif m then
                    app:error( "Unable to update xmp - ^1", m )
                end
                -- special handling of orientation in the case jpg to raw, since it's an exif tag in jpg (ifd0), but needs to be an xmp-tiff tag in raw's xmp sidecar.
                local orientation
                if jpgToRaw then
                    exifToolSession:addArg( "-b" )
                    exifToolSession:addArg( "-exif:Orientation" )
                    exifToolSession:addTarget( xmpSrcFile )
                    local data, errm, more = exifToolSession:execRead()
                    if data then
                        orientation = num:numberFromString( data )
                        if orientation then
                            app:logv( "orientation saved" )
                        else
                            app:logVerbose( "*** no orientation in src xmp" ) -- jpg?
                        end
                    else
                        Debug.pause( more )
                        app:error( "unable to extract orientation - ^1", errm )
                    end
                --else - be quiet
                --    app:logV( "Destination is not raw, so no special orientation handling." )
                end
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( savedXmpFile )
                -- exifToolSession:addArg( "-xmp" ) -- must not be here, else stomps on odd paints - verified.
                exifToolSession:addArg( '-all:all' )
                if jpgToRaw then
                    exifToolSession:addArg( '--exif:Orientation' ) -- required for jpg->raw, not vice versa.
                end
                exifToolSession:addArg( '--xmp-crs:all' )
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logv( "xmp updated via exiftool" )
                elseif m then -- not updated with reason.
                    app:error( "Unable to update xmp - ^1", m )
                end
                if orientation then
                    exifToolSession:addArg( "-overwrite_original" ) -- this line added 11/Sep/2013 19:11 - raw+jpeg probably needs it added too, or be retrofitted to use this method. ###1
                    exifToolSession:addArg( str:fmtx( "-xmp-tiff:Orientation=^1", orientation ) )
                    exifToolSession:addArg( "-n" )
                    exifToolSession:addTarget( xmpDestFile )
                    local s, m = exifToolSession:execWrite()
                    if s then
                        app:logv( "orientation updated via exiftool" )
                    elseif m then -- not updated with reason.
                        app:error( "Unable to update orientation - ^1", m )
                    end
                end
            else
                app:callingError( "xfr-dev or xfr-meta needs to be set" )
            end            
            
        end -- xfr type clauses.
        
    end, finale=function( call )
        if str:is( savedXmpFile ) then
            if fso:existsAsFile( savedXmpFile ) then
                LrFileUtils.delete( savedXmpFile )
            end
        end
        savedXmpFile = nil
    end } )

    return s, m
        
end -- end of transfer metadata method.



return Xmp
