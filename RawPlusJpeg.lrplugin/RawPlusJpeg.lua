--[[
        RawPlusJpeg.lua
--]]


local RawPlusJpeg, dbg, dbgf = Object:newClass{ className = "RawPlusJpeg", register = true }



--- Constructor for extending class.
--
function RawPlusJpeg:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function RawPlusJpeg:new( t )
    local o = Object.new( self, t )
    return o
end



-- stuff for common handling of jpeg signature (base filename suffix) UI.
local exbase = 'XYZ_1234'
local props
local function chgHdlr( id, _props, key, value )
    props['example'] = exbase .. app:getGlobalPref( 'jpgSig' ) .. '.JPG'
end
local function initJpgSig( _props, main, space )
    props = _props
    app:initGlobalPref( 'jpgSig', "" ) -- substring to identify jpeg partner.
    main[#main + 1] = vf:spacer { height = space }
    chgHdlr( nil, props, app:getGlobalPrefKey( 'jpgSig' ), app:getGlobalPref( 'jpgSig' ) )
    view:setObserver( prefs, app:getGlobalPrefKey( 'jpgSig' ), RawPlusJpeg, chgHdlr )
    
    main[#main + 1] = vf:row {
        vf:static_text {
            title = "Jpeg suffix",
            width = share 'label_width',
        },
        vf:edit_field {
            bind_to_object = prefs,
            value = app:getGlobalPrefBinding( 'jpgSig' ),
            width_in_chars = 16,
            immediate = true,
            tooltip = "Suffix that must be present in subject jpeg's base filename, otherwise jpeg will be ignored. Leave blank if subject jpegs have no such suffix (i.e. they have same base filename as raws)",
        },
    }
    
    main[#main + 1] = vf:spacer { height = 10 }
    main[#main + 1] = vf:row {
        vf:static_text {
            title = "Example raw filename:",
            width = share 'label_width',
        },
        vf:static_text {
            title = str:fmtx( "^1.ABC", exbase )
        },
    }
    main[#main + 1] = vf:row {
        vf:static_text {
            title = "Expected jpeg filename:",
            width = share 'label_width',
        },
        vf:static_text {
            bind_to_object = props,
            title = bind 'example',
            fill_horizontal = 1,
        },
    }
end

-- init'lz jpeg matching criteria (qualification) - UI & global pref.
local function initJpgQual( _props, ttl, main, space )
    app:initGlobalPref( 'jpgQual', 'inCat' ) -- 'inCat', 'both', 'sidecar' 

    main[#main + 1] = vf:spacer{ height=space }        
    main[#main + 1] = vf:row {
        vf:static_text {
            title = ttl,
            width = share 'jpg_qual_width',
        },
        vf:radio_button {
            title = "If in catalog separately",
            bind_to_object = prefs,
            value = app:getGlobalPrefBinding( 'jpgQual' ),
            checked_value = 'inCat',
        },
        vf:radio_button {
            title = "If *not* in catalog",
            bind_to_object = prefs,
            value = app:getGlobalPrefBinding( 'jpgQual' ),
            checked_value = 'sidecars',
        },
        vf:radio_button {
            title = "Both",
            bind_to_object = prefs,
            value = app:getGlobalPrefBinding( 'jpgQual' ),
            checked_value = 'both',
        },
    }
end
-- get jpeg qualification for external consumption. Logs criteria as a side-effect.
local function getJpgQual()
    app:log()
    local inCat
    local sidecars
    local what = app:getGlobalPref( 'jpgQual' )
    if what == 'inCat' then
        inCat = true
        app:log( "Considering jpegs in catalog (separately), only." )
    elseif what == 'sidecars' then
        sidecars = true
        app:log( 'Considering jpegs "sidecars" (i.e. not in catalog separately), only.' )
    elseif what == 'both' then
        inCat = true
        sidecars = true
        app:log( "Considering jpegs whether in catalog separately or not." )
    else
        error( "bad what" )
    end
    app:log()
    return inCat, sidecars   
end



-- Common function for rounding up info about raw/jpeg pairs.
-- rawPhotos is an array of all subject raw photos (having a jpeg which matches the qualifying criteria).
-- rawPaths is an array of all subject raw paths (having a jpeg which matches the qualifying criteria), parallel to rawPhotos. At the moment, this is not evern used, but it may be in the future...
-- jpgPhotos and jpgPaths arrays are (non-overlapping) and not necessarily parallel to anything, although one or the other might be, depending on jpeg qualification.
-- jpgPhotos is an array of corresponding to some or all subject photos that are in the catalog.
-- jpgPaths is an array of paths correponsding to some or all subject photos that are *not* in the catalog.
-- jpgItems is an array of items for all subject photos. If photo member is present, they were in the catalog, else not.
-- Note: jpgItems array is parallel to rawPhotos array.
function RawPlusJpeg:_getSubjectPhotoTable( photos, inCat, sidecars, sfx, cache, xdng, xraw, xoverwrite )
    local rawPhotos={}
    local jpgItems={}
    local jpgPhotos={}
    local rawPaths={}
    local jpgPaths={}
    local allJpgPaths={}
    local mostSelIndex
    local targetPhoto = catalog:getTargetPhoto()
    local function record( raw, jpg, rp, jp, ix )
        if jpg then
            assert( str:is( jp ), "no jpg path" )
            jpgPhotos[#jpgPhotos + 1] = jpg
            jpgItems[#jpgItems + 1] = { photo=jpg, path=jp }
            allJpgPaths[#allJpgPaths + 1] = jp
            -- note: no jpg-path
        elseif jp then
            jpgPaths[#jpgPaths + 1] = jp
            jpgItems[#jpgItems + 1] = { path = jp }
            allJpgPaths[#allJpgPaths + 1] = jp
            -- note: no jpg-photo
        else
            error( "bad" )
        end
        rawPhotos[#rawPhotos + 1] = raw
        rawPaths[#rawPaths + 1] = rp
        if raw == targetPhoto then -- all of this is driven from raw selection.
            mostSelIndex = ix
        end
    end
    local nRaws = 0
    local nDngs = 0
    local nJpgs = 0
    if xdng == nil then
        xdng = true
    end
    if xraw == nil then
        xraw = true
    end
    for i, photo in ipairs( photos ) do
        repeat
            local photoPath = cache:getRawMetadata( photo, 'path' )
            local photoName = cat:getPhotoNameDisp( photo, cache )
            app:logv( "Considering ^1", photoName )
            local fmt = cache:getRawMetadata( photo, 'fileFormat' )
            if fmt == 'RAW' then
                if xraw then
                    nRaws = nRaws + 1
                else
                    app:logv( "Not doing proprietary raws - ignored." )
                    break
                end
            elseif fmt == 'DNG' then
                if xdng then
                    nDngs = nDngs + 1
                else
                    app:logv( "Not doing DNGs - ignored." )
                    break
                end
            else
                if fmt == 'JPG' then
                    nJpgs = nJpgs + 1
                end
                app:logv( "^1 file selected - ignored.", fmt )
                break
            end
            local virt = cache:getRawMetadata( photo, 'isVirtualCopy' )
            if virt then
                app:logv( "virtual copy selected - ignored." )
                break
            end
            if not fso:existsAsFile( photoPath ) then
                app:logWarning( "Photo source file is missing" )
                break
            end
            local base = LrPathUtils.removeExtension( photoPath )
            local jpgPath = LrPathUtils.addExtension( base .. sfx, 'JPG' )
            if fso:existsAsFile( jpgPath ) then
                if xoverwrite == nil or xoverwrite == true then
                    local _jpgPhoto = cat:isFileInCatalog( jpgPath )
                    if not _jpgPhoto then
                        local _jpgPath = LrPathUtils.replaceExtension( jpgPath, 'jpg' )
                        _jpgPhoto = cat:isFileInCatalog( _jpgPath )
                        if not _jpgPhoto then
                            app:logVerbose( "Jpeg is not in catalog, therefore it is considered a sidecar: ^1", jpgPath )
                        end
                    end
                    if xoverwrite then
                        jpgPath = LrPathUtils.replaceExtension( jpgPath, 'jpg' ) -- extractions are always lower-case (never "original" files).
                    end
                    if _jpgPhoto then -- in catalog
                        app:logVerbose( "Jpeg with same base name as raw exists on disk and in catalog, it is therefore not considered a sidecar: ^1", jpgPath )
                        if inCat then
                            record( photo, _jpgPhoto, photoPath, jpgPath, i )
                        else
                            app:log( "Ignoring since it's in the catalog." )
                        end
                    else -- not in catalog
                        if sidecars then
                            record( photo, nil, photoPath, jpgPath, i ) -- jpg-photo is nil.
                        else
                            app:log( "Ignoring since it's not in the catalog." )
                        end
                    end
                elseif xoverwrite == false then
                    app:log( "Ignoring since jpeg already exists on disk and overwrite not being permitted." )
                else
                    app:error( "bad xoverwrite value" )
                end
            elseif xoverwrite ~= nil then -- not existing on disk, and overwrite is explicitly specified as false (extraction).
                jpgPath = LrPathUtils.replaceExtension( jpgPath, 'jpg' ) -- extractions are always lower-case (never "original" files).
                record( photo, nil, photoPath, jpgPath, i )
            else
                app:logVerbose( "Does not exist on disk: ^1", jpgPath )
            end
        until true
    end
    if #rawPhotos == 0 and nRaws == 0 and nDngs == 0 and nJpgs > 0 then
        app:show{ info="Reminder: selected jpegs are ignored - select their raw counterpart instead.",
            actionPrefKey = "Select raws not jpegs",
        }
    end
    return { rawPhotos=rawPhotos, jpgItems=jpgItems, jpgPhotos=jpgPhotos, rawPaths=rawPaths, jpgPaths=jpgPaths, allJpgPaths=allJpgPaths, mostSelIndex=mostSelIndex, nRaws=nRaws, nDngs=nDngs }
end



-- menu handler
function RawPlusJpeg:findRawsWithJpegs( title )
    app:call( Service:new{ name=title, async=true, progress=true, main=function( call )

        call:initStats{ 'found' }
        
        local photos = cat:getSelectedPhotos()
        
        local subs
        local msg
        local main={}
        local acc
        local buttons
        
        local props = LrBinding.makePropertyTable( call.context )
        initJpgQual( props, "Find jpegs", main, 5 )
        initJpgSig( props, main, 10 )

        if #photos == 0 then
            msg = "Find all raws with associated jpegs, throughout the entire catalog?"
            photos = catalog:getAllPhotos()
        else
            msg = "Find raws with associated jpegs amongst ^1?"
            subs = str:nItems( #photos, "selected photos" )
        end
        
        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            buttons = buttons,
            viewItems = main,
            accItems = acc,
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'fileName', 'copyName' } }
        local inCat, sidecars = getJpgQual()
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local subj = self:_getSubjectPhotoTable( photos, inCat, sidecars, sfx, cache )
        call:setStat( 'found', #subj.rawPhotos )
        if #subj.rawPhotos > 0 then
            app:logVerbose( "Found: ^1", #subj.rawPhotos )
        else
            app:show{ info="No such jpegs are present amongst the photos that were considered - no action has been taken." }
            --call:cancel() - may be worth reviewing the log file, if verbose anyway.
            return
        end
        
        local coll = cat:assurePluginCollection( "Raws with associated jpegs" )
        local s, m = cat:update( 30, "Collecting Raws with Jpegs", function( context, phase )
            if phase == 1 then
                coll:removeAllPhotos()
                return false -- continue to next phase.
            elseif phase == 2 then
                coll:addPhotos( subj.rawPhotos )
                if #subj.jpgPhotos > 0 then
                    coll:addPhotos( subj.jpgPhotos )
                end
            else
                app:error( "Catalog update phase out of range: ^1", phase )
            end
        end )
        
        local msg
        local subs
        if #subj.jpgPhotos > 0 then
            msg = "You should be viewing a collection containing the ^1 which have associated jpegs, as well as ^2 (those in the catalog separately)."
            subs = { str:nItems( #subj.rawPhotos, "raw photos" ), str:nItems( #subj.jpgPhotos, "associated jpegs" ) }
        else
            msg = "You should be viewing a collection containing the ^1, which have associated jpegs (that are not in the catalog separately)."
            subs = str:nItems( #subj.rawPhotos, "raw photos" )
        end
        
        if s then
            catalog:setActiveSources( coll )
            app:show{ info=msg,
                subs = subs,
                actionPrefKey = "Raws with jpegs collected",
            }
        else
            app:logErr( m )
            return
        end
        
    
    end, finale=function( call )
    
        app:log()
        app:log( "Total found: ^1", call:getStat( 'found' ) )
        app:log()
    
    end } )
end



--- Menu handler
function RawPlusJpeg:deleteJpegs( title )
    app:call( Service:new{ name=title, async=true, progress=true, main=function( call )

        call:initStats{ 'delInCat', 'delSidecar' }
        
        local photos = cat:getSelectedPhotos()
        
        local subs
        local msg
        local main={}
        local acc
        local buttons
        
        local props = LrBinding.makePropertyTable( call.context )
        initJpgQual( props, "Delete jpegs", main, 0 ) 
        initJpgSig( props, main, 10 )

        if #photos == 0 then
            -- msg = "Delete jpegs (corresponding to raws in catalog) from the entire catalog? (photos without such jpegs will not be affected)\n \n*** Consider canceling, then do a folder-sync and import any stray jpegs with same basename as raw (if you haven't already), unless you want them to be subject to deletion as well.\n \nNote: You will be presented with a complete list of files subject to deletion, for you to approve, before the deed is done.\n \nAlso, consider running 'Find Raws with Jpeg Sidecars' first."
            msg = "Delete jpegs corresponding to the raws that are present in entire catalog? (be sure to specifiy 'Delete jpegs' finding criteria below)\n \nNote: You will be presented with a complete list of files subject to deletion, for you to approve, before the deed is done.\n \nAlso, consider running 'Find Raws with Jpeg Sidecars' first. - it's not necessary since such finding will be done automatically prior to deletion, but nevertheless it may help you achieve some peace of mind before embarking on deletion."
            photos = catalog:getAllPhotos()
        else
            -- msg = "Delete jpegs with raw counterpart in catalog (subject to the constraints below) amongst ^1? (photos without such jpegs will not be affected)\n \n*** Consider canceling, then do a folder-sync and import any stray jpegs with same basename as raw (if you haven't already), unless you want them to be subject to deletion as well.\n \nNote: You will be presented with a complete list of files subject to deletion, for you to approve, before the deed is done.\n \nAlso, consider running 'Find Raws with Jpeg Sidecars' first."
            msg = "Delete jpegs corresponding to the raws that are present in catalog amongst ^1? (be sure to specify 'Delete jpegs' finding criteria below)\n \nNote: You will be presented with a complete list of files subject to deletion, for you to approve, before the deed is done.\n \nAlso, consider running 'Find Raws with Jpeg Sidecars' first. - it's not necessary since such finding will be done automatically prior to deletion, but nevertheless it may help you achieve some peace of mind before embarking on deletion."
            subs = str:nItems( #photos, "selected photos" )
        end
        
        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            buttons = buttons,
            viewItems = main,
            accItems = acc,
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'fileName', 'copyName' } }
        local inCat, sidecars = getJpgQual()
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local subj = self:_getSubjectPhotoTable( photos, inCat, sidecars, sfx, cache )
        if #subj.jpgItems > 0 then
            app:log()
            app:log( "Subject to deletion:" )
            app:log( "====================" )
            if #subj.jpgPhotos > 0 then
                app:log( "Jpegs in catalog:" )
                app:log( "-----------------" )
                for i, photo in ipairs( subj.jpgPhotos ) do
                    local path = cache:getRawMetadata( photo, 'path', true ) -- reminder: this must be done like this - there is no parallel array of jpg-paths...
                    app:log( path )
                end
                app:log( "-----------------" )
            else
                app:log( "Note: no jpegs will be deleted that are in the catalog." )
            end
            if #subj.jpgPaths > 0 then
                app:log( "Jpegs not in catalog:" )
                app:log( "---------------------" )
                for i, path in ipairs( subj.jpgPaths ) do
                    app:log( path )
                end
                app:log( "---------------------" )
            else
                app:log( "Note: all jpegs subject to deletion are in the catalog." )
            end
        else
            app:show{ info="No such jpegs are present amongst selected photos - no action taken..." }
            return
        end
        
        repeat
            call:setCaption( "Dialog box needs your attention..." )
            local button = app:show{ confirm="Confirm that you want to delete the files as indicated in the log file.",
                buttons = { dia:btn( "Show Log File", 'other' ), dia:btn( "Yes (delete jpegs)", 'ok' ), dia:btn( "No (do not delete any files)", 'cancel' ) },
            }
            if button == 'other' then
                app:showLogFile()
            elseif button == 'cancel' then
                call:cancel()
                return
            else
                app:log()
                app:log( "User approved deletion." )
                break
            end
        until false
        
        local c = 0
        local function _delete( file, statName )
            call:setPortionComplete( c, #subj.jpgItems )
            c = c + 1
            local s, m = fso:moveToTrash( file )
            if s then
                app:log( file .. " - deleted, or moved to trash." )
                call:incrStat( statName )
            else
                app:logWarning( "Unable to delete '^1', or move to trash - ^2.", file, m )
            end
            if call:isQuit() then
                return
            end
        end
        
        if #subj.jpgPhotos > 0 then
            app:log()
            app:log( "Deleting jpegs that are in catalog:" )
            app:log( "-----------------------------------" )
            for i, photo in ipairs( subj.jpgPhotos ) do
                local path = cache:getRawMetadata( photo, 'path', true )
                _delete( path, 'delInCat' )
            end
            app:log( "-----------------------------------" )
        else
            app:log( "Note: no jpegs will be deleted that are in the catalog." )
        end
        if #subj.jpgPaths > 0 then
            app:log()
            app:log( "Deleting jpegs that are not in catalog:" )
            app:log( "---------------------------------------" )
            for i, path in ipairs( subj.jpgPaths ) do
                _delete( path, 'delSidecar' )
            end
            app:log( "---------------------------------------" )
        else
            app:log( "Note: all jpegs subject to deletion are in the catalog." )
        end
        app:log()
        
        call:setPortionComplete( 1 )

        local msg
        local apk
        if call:getStat( 'delInCat' ) > 0 and call:getStat( 'delSidecar' ) > 0 then
            msg = "You have 2 things to consider doing, after clicking 'OK':\n \n1. Invoke 'Find Missing Photos' (Library Menu) so you can remove from catalog.\n \n2. Re-synchronizing folders to extinguish the +JPEG from the RAW+JPEG on the lib-grid thumb (note: although database is updated promptly, the UI may lag)."
            apk = "Deletion of both kinds of jpegs - in catalog, and not in catalog"
        elseif call:getStat( 'delInCat' ) > 0 then
            msg = "After clicking 'OK', consider invoking 'Find Missing Photos' (Library Menu), so you can remove from catalog."
            apk = "Deletion of jpeg files in catalog"
        elseif call:getStat( 'delSidecar' ) > 0 then
            msg = "After clicking 'OK' consider re-synchronizing folders, so Lightroom updates image status - e.g. will extinguish the +JPEG from the RAW+JPEG on the lib-grid thumb (note: although database is updated promptly, the UI may lag)."
            apk = "Deletion of jpeg files not in catalog"
        else
            app:logErr( "bad statistical value encountered" )
            return
        end
        
        call:setCaption( "Dialog box needs your attention..." )
        app:show{ info=msg,
            actionPrefKey=apk,
        }
            
    
    end, finale=function( call )
    
        app:log()
        app:log( "jpegs (present in catalog) deleted: ^1", call:getStat( 'delInCat' ) )
        app:log( "jpeg sidecars (not in catalog) deleted: ^1", call:getStat( 'delSidecar' ) )
        app:log()
    
    end } )
end



--- Transfer selected metadata items, from one set of photos to another (parallel) set.
--
function RawPlusJpeg:_transfer( subj, rawToJpg, sidecars, cache, call )

    local xfrDev
    local xfrMeta
    local tb
    local what = app:getGlobalPref( 'xfrWhat' )
    if what == 'meta' then
        xfrMeta = true
        tb = "xmp metadata"
    elseif what == 'dev' then
        xfrDev = true
        tb = "develop settings via xmp"
    elseif what == 'both' then
        xfrMeta = true
        xfrDev = true
        tb = "xmp metadata and develop settings"
    else
        error( "bad dev what" )
    end

    -- transfer xmp from source to target photo.
    local function transfer3( fromXmpFile, toXmpFile )
    
        local savedXmpFile
        local saved
        local s, m = app:call( Call:new{ name="transfer", main=function( icall )
            
            if xfrMeta and xfrDev then
                app:logVerbose( "raw to jpg both" )
                call.ets:addArg( "-overwrite_original" )
                call.ets:addArg( "-all=" )
                call.ets:addArg( "-tagsFromFile" )
                call.ets:addArg( fromXmpFile )
                call.ets:addArg( '-xmp' )
                call.ets:addArg( '-all:all' )
                call.ets:addTarget( toXmpFile )
                local s, m = call.ets:execWrite()
                if s then
                    app:logv( "metadata and dev settings transferred" )
                else
                    app:error( "Unable to transfer metadata and dev settings - ^1", m )
                end
            else
                savedXmpFile = LrPathUtils.addExtension( toXmpFile, "xmp" ) -- kinda tacky.
                call.ets:addArg( "-overwrite_original" )
                call.ets:addArg( "-tagsFromFile" )
                call.ets:addArg( toXmpFile )
                call.ets:addArg( "-xmp" )
                call.ets:addTarget( savedXmpFile )
                local s, m = call.ets:execWrite()
                if s then
                    assert( fso:existsAsFile( savedXmpFile ), "exiftool was unable to save xmp metadata" )
                else
                    if LrFileUtils.isWritable( toXmpFile ) then
                        app:assert( LrFileUtils.isReadable( savedXmpFile ), "Not readable: ^1", savedXmpFile )
                        app:error( "unable to save xmp - ^1", m )
                    else
                        app:error( "unable to save xmp - '^1' is not writable", toXmpFile )
                    end
                end
                if xfrMeta then
                    call.ets:addArg( "-overwrite_original" )
                    call.ets:addArg( '-all=' )
                    call.ets:addArg( '-tagsFromFile' )
                    call.ets:addArg( fromXmpFile )
                    -- call.ets:addArg( "-xmp" ) - can't do this here, or it brings the develop settings too, at least when xfr is raw -> jpg.
                    call.ets:addArg( "-all:all" )
                    call.ets:addArg( '--xmp-crs:all' )
                    call.ets:addTarget( toXmpFile )
                    local s, m = call.ets:execWrite()
                    if s then
                        app:logv( "xmp updated via exiftool" )
                    else
                        app:error( "Unable to update xmp - ^1", m )
                    end
                    call.ets:addArg( "-overwrite_original" )
                    call.ets:addArg( '-tagsFromFile' )
                    call.ets:addArg( savedXmpFile )
                    --call.ets:addArg( "-xmp" )
                    call.ets:addArg( '-xmp-crs:all' )
                    call.ets:addTarget( toXmpFile )
                    local s, m = call.ets:execWrite()
                    if s then
                        app:logv( "xmp updated" )
                    elseif m then -- not updated with reason.
                        app:error( "Unable to update xmp - ^1", m )
                    end
                elseif xfrDev then -- can't seem to get orientation jpg->raw correct no matter what I do, so: done for now... ###2
                    call.ets:addArg( "-overwrite_original" )
                    call.ets:addArg( '-all=' )
                    call.ets:addArg( '-tagsFromFile' )
                    call.ets:addArg( fromXmpFile )
                    call.ets:addArg( "-xmp" ) -- must be here for unrecognized paint settings..., but stomps on orientation - verified.
                    call.ets:addArg( '-xmp-crs:all' )
                    call.ets:addTarget( toXmpFile )
                    local s, m = call.ets:execWrite()
                    if s then
                        app:logv( "xmp updated" )
                    elseif m then
                        app:error( "Unable to update xmp - ^1", m )
                    end
                    -- special handling of orientation in the case jpg to raw, since it's an exif tag in jpg (ifd0), but needs to be an xmp-tiff tag in raw's xmp sidecar.
                    local orientation
                    if not rawToJpg then
                        call.ets:addArg( "-b" )
                        call.ets:addArg( "-exif:Orientation" )
                        call.ets:addTarget( fromXmpFile )
                        local data, errm, more = call.ets:execRead()
                        if data then
                            orientation = num:numberFromString( data )
                            if orientation then
                                app:logv( "orientation saved" )
                            else
                                app:logVerbose( "*** no orientation in jpg" )
                            end
                        else
                            Debug.pause( more ) -- more (response) only returned if no data.
                            app:error( "unable to extract orientation - ^1", errm )
                        end
                    end
                    call.ets:addArg( "-overwrite_original" )
                    call.ets:addArg( '-tagsFromFile' )
                    call.ets:addArg( savedXmpFile )
                    -- call.ets:addArg( "-xmp" ) -- must not be here, else stomps on odd paints - verified.
                    call.ets:addArg( '-all:all' )
                    if not rawToJpg then
                        call.ets:addArg( '--exif:Orientation' ) -- required for jpg->raw, not vice versa, but doesn't hurt??
                    end
                    call.ets:addArg( '--xmp-crs:all' )
                    call.ets:addTarget( toXmpFile )
                    local s, m = call.ets:execWrite()
                    if s then
                        app:logv( "xmp updated via exiftool" )
                    elseif m then -- not updated with reason.
                        app:error( "Unable to update xmp - ^1", m )
                    end
                    if not rawToJpg and orientation then
                        call.ets:addArg( "-overwrite_original" )
                        call.ets:addArg( str:fmtx( "-xmp-tiff:Orientation=^1", orientation ) )
                        call.ets:addArg( "-n" )
                        call.ets:addTarget( toXmpFile )
                        local s, m = call.ets:execWrite()
                        if s then
                            app:logv( "orientation updated via exiftool" )
                        elseif m then -- not updated with reason.
                            app:error( "Unable to update orientation - ^1", m )
                        end
                    end
                else
                    app:error( "program failure" )
                end            
                
            end -- xfr classes
        
        end, finale=function( call )
            if savedXmpFile and fso:existsAsFile( savedXmpFile ) then
                LrFileUtils.delete( savedXmpFile )
            end
        end } ) 
        if str:is( m ) then
            app:logErr( m )
        end
        return s 
    end -- function

    local s, m = exifTool:isUsable()
    app:log()
    if s then
        if m then
            app:log( "exiftool may be usable - ^1", m )
        else
            app:log( "exiftool to be used - ^1", exifTool:getExe() )
        end
    else
        app:show{ warning="exiftool not config - ^1", m }
        call:cancel()
        return
    end
    
    -- use session regardless of photo count
    call.ets = exifTool:openSession( call.name )
    local ver, m = call.ets:getVersionString()
    if str:is( ver ) then
        app:log( "Exiftool version: ^1", ver )
    else
        app:show{ warning="exiftool not config - ^1", m }
        call:cancel()
        return
    end
    app:log()

    call:setCaption( "Transferring Lr Metadata" )
    
    local saveFrom   -- from photos, for saving metadata, before transfer.
    local saveTo     -- to photos, for saving metadata, before transfer.

    if rawToJpg then
        saveFrom = subj.rawPhotos
        saveTo = subj.jpgPhotos -- portion in catalog, if any
    else
        saveTo = subj.rawPhotos
        saveFrom = subj.jpgPhotos -- partial
    end

    local s, m    
    if #saveFrom > 0 then
        if #saveFrom == 1 then
            s, m = cat:savePhotoMetadata( saveFrom[1], nil, nil, call, false ) -- ( photo, photoPath, targ, call, noVal )
        else
            s, m = cat:saveMetadata( saveFrom, true, false, false, call ) -- ( photos, preSelect, restoreSelect, alreadyInGridMode, service )
        end
    else
        s = true
    end
    if s and #saveTo > 0 then
        if #saveTo == 1 then
            s, m = cat:savePhotoMetadata( saveTo[1], nil, nil, call, false ) -- ( photo, photoPath, targ, call, noVal )
        else
            s, m = cat:saveMetadata( saveTo, true, false, true, call ) -- ( photos, preSelect, restoreSelect, alreadyInGridMode, service )
        end
    end
    if s then
        app:logVerbose( "xmp metadata prepared for transfer" )  
    else
        app:logErr( "Unable to prepare xmp metadata for transfer - ^1", m )
        return
    end
    
    call:setCaption( "Transfering metadata..." )
    local readTo = {} -- to photos, for reading metadata, after transfer.
    for i, rawPhoto in ipairs( subj.rawPhotos ) do
        call:setPortionComplete( i - 1, #subj.rawPhotos )
        
        repeat

            local jpgItem = subj.jpgItems[i]

            local fromXmpFile
            local toXmpFile
            local toPhoto
        
            if rawToJpg then
                fromXmpFile = xmpo:getXmpFile( rawPhoto, cache )
                if jpgItem.photo then -- to emphasize:
                    toPhoto = jpgItem.photo -- may be nil.
                end
                toXmpFile = jpgItem.path
            else
                toPhoto = rawPhoto
                toXmpFile = xmpo:getXmpFile( rawPhoto, cache )
                fromXmpFile = jpgItem.path
            end
    
            app:log( "Transferring ^1 from ^2 to ^3", tb, fromXmpFile, LrPathUtils.leafName( toXmpFile ) )
            
            local s = transfer3( fromXmpFile, toXmpFile ) -- no "m".
            if s then
                call:incrStat( 'photoSync' )
                if toPhoto then
                    readTo[#readTo + 1] = toPhoto
                else
                    -- to-photo was jpg not in cat.
                end
            else
                app:logVerbose( "Unable to transfer xmp metadata" ) -- it already logged warnings and errors.
                call:incrStat( 'noXfr' )
            end
            
        until true
        
        if call:isQuit() then
            return false, "quit"
        end

    end -- for            
    call:setPortionComplete( 1 )


    if #readTo > 0 then 
        local s, m   
        if #readTo == 1 then
            s, m = cat:readPhotoMetadata( readTo[1], nil, true, call, nil ) -- ( photo, photoPath, alreadyInLibraryModule, service, manualSubtitle )
        else
            s, m = cat:readMetadata( readTo, false, false, true, call ) -- ( photos, preSelect, restoreSelect, alreadyInGridMode, service )
        end
        if s then
            app:logVerbose( "xmp read into target photos in catalog - metadata should be successfully transferred." )  
        else
            app:logErr( "Unable to read metadata, so it was not successfully transferred - ^1", m )            
        end
    else
        app:log( "None done." )
        call:setStat( 'photoSync', 0 )
    end
    
end   



--- menu handler
function RawPlusJpeg:syncMeta( title, rawToJpg )
    app:call( Service:new{ name=title, async=true, progress=true, main=function( call )

        call:initStats{ 'photoSync', 'jpgChg', 'noXfr' }
        
        local photos = cat:getSelectedPhotos()
        
        local subs
        local msg
        local main={}
        local acc
        local buttons

        app:initGlobalPref( 'xfrWhat', 'meta' ) -- 'meta', 'dev', 'both' 
        
        local props = LrBinding.makePropertyTable( call.context )
        initJpgQual( props, "Sync jpegs", main, 0 )
        initJpgSig( props, main, 10 )
        
        local function ch( id, p, k, v )
            app:call( Call:new{ name="change handler", async=true, guard=App.guardSilent, main=function( icall )
                local n = app:getGlobalPrefName( k )
                if n == 'xfrWhat' then
                    if v == 'dev' or v == 'both' then
                        local button = app:show{ confirm="Develop settings sync may not work when local paint (brush strokes) are present, try anyway?", -- ###1: 7/Aug/2013 18:27 - really? (using xmp for sync should be OK no?)
                            buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel', false ) },
                            actionPrefKey = "Sync when painted",
                        }
                        if button == 'cancel' then
                            app:setGlobalPref( 'xfrWhat', 'meta' )
                        end
                    end
                end
            end } )                    
        end
        
        ch( nil, nil, app:getGlobalPrefKey( 'xfrWhat' ), app:getGlobalPref( 'xfrWhat' ) )
        view:setObserver( prefs, app:getGlobalPrefKey( 'xfrWhat' ), RawPlusJpeg, ch )

        main[#main + 1] = vf:spacer{ height=15 }                
        main[#main + 1] = vf:row {
            vf:static_text {
                title = "Transfer",
                width = share 'label_width',
            },
            vf:radio_button {
                title = "Metadata",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'xfrWhat' ),
                checked_value = 'meta',
            },
            vf:radio_button {
                title = "Develop Settings",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'xfrWhat' ),
                checked_value = 'dev',
            },
            vf:radio_button {
                title = "Both",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'xfrWhat' ),
                checked_value = 'both',
            },
        }
        
        if #photos == 0 then
            if rawToJpg then
                msg = "Sync metadata (raw -> jpeg) - throughout the entire catalog?"
            else
                msg = "Sync metadata (jpeg -> raw) - throughout the entire catalog?"
            end
            photos = catalog:getAllPhotos()
        else
            if rawToJpg then
                msg = "Sync metadata, raw -> jpeg (^1 will be considered)?"
            else
                msg = "Sync metadata, jpeg -> raw (^1 will be considered)?"
            end
            subs = str:nItems( #photos, "selected photos" )
        end

        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            viewItems = main,
            accItems = acc,
            buttons = buttons,
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'copyName' } }
        local toPhotos
        local fromPhotos
        local inCat, sidecars = getJpgQual()
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local subj = self:_getSubjectPhotoTable( photos, inCat, sidecars, sfx, cache )
        
        if #subj.rawPhotos > 0 then
            app:log()
            app:log( "^1 subject to transfer.", str:nItems( #subj.rawPhotos, "photos" ) )
        else
            app:show{ info="No photos subject to transfer" }
            return
        end

        app:log()
        
        self:_transfer( subj, rawToJpg, sidecars, cache, call )
        
    end, finale=function( call )
    
        exifTool:closeSession( call.ets ) -- no-op if ets is nil or exiftool itself.
    
        app:log()
        app:logStat( "^1 sync'd", call:getStat( 'photoSync' ), "photos" )
        app:logStat( "^1 changed", call:getStat( 'jpgChg' ), "jpegs" )
        app:logStat( "^1", call:getStat( 'noXfr' ), "transfer metadata failures" )
        app:log()
    
        --Debug.showLogFile()
    
    end } )

end



--- menu handler
function RawPlusJpeg:importJpegs( title )
    app:call( Service:new{ name=title, async=true, progress=true, main=function( call )
    
        call:initStats{ 'sep' }
        
        local subs
        local msg
        local main={}
        local acc
        local buttons
        
        local photos = cat:getSelectedPhotos()
        
        if #photos == 0 then
            msg = "Import jpegs corresponding to the raws that exist in the entire catalog?  (photos in catalog without corresponding unimported jpegs on disk will not be affected)"        
            photos = catalog:getAllPhotos()
        else
            msg = "Import jpegs corresponding to the raws that exist in the catalog amonst ^1? (selected photos without corresponding unimported jpegs on disk will not be affected)"
            subs = str:nItems( #photos, "selected photos" )
        end
        
        app:initGlobalPref( 'stack', 'no' )
        
        main[#main + 1] = vf:row {
            vf:static_text {
                title = "Stack imported jpeg",
            },
            vf:radio_button {
                title = "Above the raw",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'above',
            },
            vf:radio_button {
                title = "Below the raw",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'below',
            },
            vf:spacer{ width=5 },
            vf:radio_button {
                title = "Do not stack",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'no',
            },
        }
        
        local props = LrBinding.makePropertyTable( call.context )
        -- Note: it does not make sense to include those already in-catalog.
        initJpgSig( props, main, 15 )
        
        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            buttons = buttons,
            viewItems = main,
            accItems = acc,
            -- no actionprefkey
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        local stack = app:getGlobalPref( 'stack' ) or 'no'
        if stack == 'no' then
            stack = nil
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'fileName', 'copyName' } }
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local subj = self:_getSubjectPhotoTable( photos, false, true, sfx, cache ) -- not in-cat, just sidecars.
        
        assert( #subj.jpgItems == #subj.jpgPaths, "jpg item mismatch" )
        
        if #subj.jpgItems > 0 then
            app:log()
            app:log( "Subject to import:" )
            app:log( "-----------------" )
            for i, v in ipairs( subj.jpgItems ) do
                app:log( v.path )
            end
        else
            app:show{ info='No such jpegs (that exist on disk, but not in catalog) are present amongst selected photos - no action taken...' }
            return
        end
        
        repeat
            call:setCaption( "Dialog box needs your attention..." )
            local button = app:show{ confirm="Confirm that you want to import the files as indicated in the log file.",
                buttons = { dia:btn( "Show Log File", 'other' ), dia:btn( "Yes (import jpegs)", 'ok' ), dia:btn( "No (do not import)", 'cancel' ) },
            }
            if button == 'other' then
                app:showLogFile()
            elseif button == 'cancel' then
                call:cancel()
                return
            else
                break
            end
        until false
        
        app:log()
        app:log( "Importing jpegs:" )
        app:log( "---------------" )
        call:setCaption( "Importing jpegs" )
        local s, m = cat:update( 30, "Importing jpegs", function( context, phase )
            for i, jpgPath in ipairs( subj.jpgPaths ) do
                call:setPortionComplete( i - 1, #subj.jpgPaths )
                local raw = stack and subj.rawPhotos[i] or nil -- note: array is parallel.
                local s, m = LrTasks.pcall( catalog.addPhoto, catalog, jpgPath, raw, stack )
                if s then
                    app:log( jpgPath .. " - added to catalog." )
                    call:incrStat( 'sep' )
                else
                    app:logError( "Unable to import '^1' - ^2.", jpgPath, m )
                end
                if call:isQuit() then
                    return
                end
            end
            call:setPortionComplete( 1 )
        end )
        if s then 
            call:setStat( 'sep', #subj.jpgItems )        
            call:setCaption( "Dialog box needs your attention..." )
            app:show{ info="If some of the imported jpegs were previously associated with RAW+JPEG photos (i.e. imported as one, not separately), then consider doing 2 things now:\n \n1. If you haven't already, check 'Treat JPEG files next to raw files as separate photos' (Edit Menu -> Preferences -> General Tab -> Import Options section).\n \n2. Re-synchronize folders so Lightroom updates image status - e.g. will extinguish the +JPEG from the RAW+JPEG on the lib-grid thumb.",
                actionPrefKey="Resync after import to complete separation",
            }
        else
            app:logErr( m )
            call:setStat( 'sep', 0 )            
        end
            
    
    end, finale=function( call )
    
        app:log()
        app:log( "Total jpegs imported: ^1", call:getStat( 'sep' ) )
        app:log()
    
    end } )

end



--- menu handler
function RawPlusJpeg:extractJpegs( title )
    app:call( Service:new{ name=title, async=true, progress=true, main=function( call )
    
        call:initStats{ 'extracted', 'andImported', 'alreadyImported', 'firstTime', 'overwritten' }
        
        local subs
        local msg
        local main={}
        local acc
        local buttons
        
        local photos = cat:getSelectedPhotos()
        
        if #photos == 0 then
            msg = "Extract jpegs corresponding to the raws that exist in the entire catalog?"        
            photos = catalog:getAllPhotos()
        else
            msg = "Extract jpegs corresponding to the raws that exist in the catalog amonst ^1?"
            subs = str:nItems( #photos, "selected photos" )
        end
        
        app:initGlobalPref( 'stack', 'no' )
        
        main[#main + 1] = vf:row {
            vf:static_text {
                title = "Stack extracted jpeg",
            },
            vf:radio_button {
                title = "Above the raw",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'above',
            },
            vf:radio_button {
                title = "Below the raw",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'below',
            },
            --vf:spacer{ width=5 },
            vf:radio_button {
                title = "Do not stack",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'no',
            },
            vf:radio_button {
                title = "Do not import",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'stack' ),
                checked_value = 'x',
            },
        }
        
        main[#main + 1] = vf:spacer{ height = 15 }
        app:initGlobalPref( 'extractFormats', 'dng' )
        main[#main + 1] = vf:row {
            vf:static_text {
                title = "Extract from",
                width = share 'label_width',
            },
            vf:radio_button {
                title = "DNG",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'extractFormats' ),
                checked_value = 'dng',
            },
            vf:radio_button {
                title = "RAW",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'extractFormats' ),
                checked_value = 'raw',
            },
            --vf:spacer{ width=1 },
            vf:radio_button {
                title = "Either",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'extractFormats' ),
                checked_value = 'both',
            },
        }
        
        main[#main + 1] = vf:spacer{ height = 5 }
        app:initGlobalPref( 'extractOverwrite', false )
        main[#main + 1] = vf:row {
            vf:static_text {
                title = "Extract if",
                width = share 'label_width',
            },
            vf:radio_button {
                title = "Not already on disk",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'extractOverwrite' ),
                checked_value = false,
            },
            --vf:spacer{ width=1 },
            vf:radio_button {
                title = "Regardless",
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'extractOverwrite' ),
                checked_value = true,
            },
        }
        
        local props = LrBinding.makePropertyTable( call.context )
        initJpgSig( props, main, 15 ) -- reminder: in this case (unlike all other cases) this is not a matching suffix, but a writing suffix.
        -- also: it's just the example that binds to props - the suffix itself is bound to global pref.
        
        local function ch( id, props, key, value )
            app:call( Call:new{ name="changer", async=true, main=function( call )
                local name = app:getGlobalPrefName( key )
                local common = "\n \nMetadata will not be transferred automatically to extracted jpegs - you'll have to do that manually for the time being."
                if name == 'extractFormats' then
                    if value == 'dng' then
                        app:show{ info="Not sure about ICC profile for DNG previews yet - please let me know if they do or do not appear to have correct color interpretation - please.^1",
                            subs = common,
                            actionPrefKey = "DNG preview extraction"
                        }
                    elseif value == 'raw' then
                        app:show{ info="ICC profile is not being assigned to jpegs extracted from raws - this will result in incorrect color interpretation in some (but not all) cases. If your raws are NEF, I strongly recommend using NxToo instead for preview extraction, since it handles icc-profile correctly, and transfers metadata automatically.^1",
                            subs = common,
                            actionPrefKey = "RAW preview extraction"
                        }
                    elseif value == 'both' then
                        app:show{ info="ICC profile is not being assigned to jpegs extracted from raws - this will result in incorrect color interpretation in some (but not all) cases. If your raws are NEF, I strongly recommend using NxToo instead for preview extraction, since it handles icc-profile correctly, and transfers metadata automatically.\n \nAlso, I'm not yet certain about the icc-profile for jpegs extracted from the DNGs either, so their color may also be off too - this story still unfolding...^1",
                            subs = common,
                            actionPrefKey = "DNG & RAW extractions, both"
                        }
                    else
                        error( "bad value" )
                    end
                elseif name == 'extractOverwrite' then
                    if value then
                        app:show{ info="With 'Regardless' checked, extracted jpegs will overwrite existing jpegs of the same filename, without warning.",
                            subs = common,
                            actionPrefKey = "jpeg extractions overwrite"
                        }
                    else
                        app:show{ info="With 'Not already on disk' checked, jpegs will not be extracted if already existing on disk, in which case they will remain as they were, and will not be updated.",
                            subs = common,
                            actionPrefKey = "jpeg extractions already on disk"
                        }
                    end
                end
            end } )
        end
        view:setObserver( prefs, app:getGlobalPrefKey( 'extractFormats' ), RawPlusJpeg, ch )
        view:setObserver( prefs, app:getGlobalPrefKey( 'extractOverwrite' ), RawPlusJpeg, ch )
        
        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            buttons = buttons,
            viewItems = main,
            accItems = acc,
            -- no actionprefkey
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        local stack = app:getGlobalPref( 'stack' ) or 'no'
        local add = true
        if stack == 'no' then
            stack = nil
        end
        if stack == 'x' then
            add = false
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'fileName', 'copyName' } }
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local _xfmt = app:getGlobalPref( 'extractFormats' ) -- can't use 'or' expression with boolean. ###3 consider extending get*pref syntax to have default and constraints.
        local xdng = _xfmt == 'dng' or _xfmt == 'both'
        local xraw = _xfmt == 'raw' or _xfmt == 'both'
        local xoverwrite = app:getGlobalPref( 'extractOverwrite' ) -- can't use 'or' expression with boolean.
        local subj = self:_getSubjectPhotoTable( photos, true, true, sfx, cache, xdng, xraw, xoverwrite ) -- in-cat, or sidecars, overwrite as specified.
        
        assert( #subj.rawPhotos == #subj.jpgItems, "mismatch" )

        local s, m = exifTool:isUsable()
        app:log()
        if s then
            if m then
                app:log( "exiftool may be usable - ^1", m )
            else
                app:log( "exiftool to be used - ^1", exifTool:getExe() )
            end
        else
            app:show{ warning="exiftool not config - ^1", m }
            call:cancel()
            return
        end
        -- use session regardless of photo count.
        local cfg = LrPathUtils.child( _PLUGIN.path, "ExifTool_Config.txt" )
        call.ets = exifTool:openSession( call.name, cfg ) -- raw extractions need big-image from config file.
        local ver, m = call.ets:getVersionString()
        if str:is( ver ) then
            app:log( "Exiftool version: ^1", ver )
        else
            app:show{ warning="Unable to determine exiftool due to error - ^1", m }
            call:cancel()
            return
        end
        app:log()
        
        if #subj.jpgItems > 0 then
            app:log()
            app:log( "Subject to extraction:" )
            app:log( "---------------------" )
            for i, v in ipairs( subj.jpgItems ) do
                app:log( v.path )
            end
        else
            app:show{ info='No jpegs are subject to extraction...' }
            return
        end
        
        repeat
            call:setCaption( "Dialog box needs your attention..." )
            local button = app:show{ confirm="Confirm that you want to extract jpeg files as indicated in the log file.",
                buttons = { dia:btn( "Show Log File", 'other' ), dia:btn( "Yes (extract jpegs)", 'ok' ), dia:btn( "No (do not extract)", 'cancel' ) },
            }
            if button == 'other' then
                app:showLogFile()
            elseif button == 'cancel' then
                call:cancel()
                return
            else
                break
            end
        until false
        
        
        local function extract( rawPhoto, jpgPath )
            local rawPath = cache:getRawMetadata( rawPhoto, 'path' )
            --Debug.pause( rawPath:sub( -60 ), jpgPath:sub( -60 ) )
            local fmt = cache:getRawMetadata( rawPhoto, 'fileFormat' )
            local sfx = app:getGlobalPref( 'jpgSig' ) or ""
            local base = LrPathUtils.removeExtension( rawPath ) .. sfx
            local tjpg = LrPathUtils.addExtension( base, "jpg" )
            assert( tjpg == jpgPath, "bad jpg path expectation" )
            local sfxt = sfx .. ".jpg" -- for -w! command.
            
            if fmt == 'RAW' then
                call.ets:addArg( "-BigImage\n-b" ) -- -- does not work well with DNG (sometimes returns an even smaller image).
                call.ets:addArg( '-w!' )
                call.ets:addArg( sfxt )
                call.ets:addTarget( rawPath )
                local rslt, errm = call.ets:execute()
                if str:is( errm ) then
                    app:logErr( "Unable to extract - ^1", errm )
                    return false
                elseif str:is( rslt ) and not rslt:find( "0 output files created" ) then
                    assert( fso:existsAsFile( jpgPath ), 'no jpg file at expected path: "' .. jpgPath .. '",  suffix: "' .. sfxt .. '"' )
                    app:log( "Extracted size-large preview" )
                    return true
                else
                    Debug.pause( rslt )
                    app:logErr( "No extraction - no reason." )
                    return false
                end
            else
                call.ets:addArg( "-jpgFromRaw\n-b" ) -- big, but unedited.
                call.ets:addArg( "-w!" )
                call.ets:addArg( sfxt )
                call.ets:addTarget( rawPath )
                local rslt, errm = call.ets:execute()
                if str:is( errm) then
                    app:logErr( "Unable to extract - ^1", errm )
                    return false
                elseif str:is( rslt ) and not rslt:find( "0 output files created" ) then
                    app:log( "Extracted size-large preview" )
                    return true
                else
                    call.ets:addArg( "-PreviewImage\n-b" ) -- medium, edited.
                    call.ets:addArg( "-w!" )
                    call.ets:addArg( sfxt )
                    call.ets:addTarget( rawPath )
                    local rslt, errm = call.ets:execute()
                    if str:is( errm) then
                        app:logErr( "Unable to extract - ^1", errm )
                        return false
                    elseif str:is( rslt ) and not rslt:find( "0 output files created" ) then
                        app:log( "Extracted medium-sized preview" )
                        return true
                    else
                        app:logWarning( "Unable to extract jpeg preview - seems not to be present." )
                        return false
                    end
                end
            end
        end
        
        
        app:log()
        app:log( "Extracting jpegs:" )
        app:log( "-----------------" )
        call:setCaption( "Extracting jpegs" )
        local s, m = cat:update( 30, "Extract jpegs", function( context, phase )
            for i, v in ipairs( subj.jpgItems ) do -- note: in this special case, jpg-paths is parallel to raw-photos array in this case.
                local jpgPath = v.path
                call:setPortionComplete( i - 1, #subj.jpgItems )
                repeat
                    local s = extract( subj.rawPhotos[i], jpgPath ) -- no need for "m": logs as side-effect.
                    if s then
                        call:incrStat( 'extracted' )
                        if not subj.jpgPhotos[i] then -- not already in catalog.
                            if add then -- add to catalog
                                local raw = stack and subj.rawPhotos[i] or nil -- note: array is parallel.
                                local s, m = LrTasks.pcall( catalog.addPhoto, catalog, jpgPath, raw, stack )
                                if s then
                                    app:log( jpgPath .. " - added to catalog." )
                                    call:incrStat( 'andImported' )
                                else
                                    app:logError( "Unable to import '^1' - ^2.", jpgPath, m )
                                end
                                if call:isQuit() then
                                    return
                                end
                            else
                                app:log( "Extracted (not added to catalog)" )
                            end
                        else
                            call:incrStat( 'alreadyImported' )
                            app:log( "Re-extracted (already in catalog)" )
                        end
                    else
                        -- nuthin.
                    end
                until true
            end
            call:setPortionComplete( 1 )
        end )
        if s then 
            call:setCaption( "Dialog box needs your attention..." )
            app:show{ info="If some of the imported jpegs were previously associated with RAW+JPEG photos (i.e. imported as one, not separately), then consider doing 2 things now:\n \n1. If you haven't already, check 'Treat JPEG files next to raw files as separate photos' (Edit Menu -> Preferences -> General Tab -> Import Options section).\n \n2. Re-synchronize folders so Lightroom updates image status - e.g. will extinguish the +JPEG from the RAW+JPEG on the lib-grid thumb.",
                actionPrefKey="Resync after import to complete separation",
            }
        else
            app:logErr( m )
            call:setStat( 'andImported', 0 )            
        end
            
    
    end, finale=function( call )

        exifTool:closeSession( call.ets )    
        app:log()
        app:log( "jpegs extracted: ^1", call:getStat( 'extracted' ) )
        app:log( "and imported: ^1", call:getStat( 'andImported' ) )
        app:log( "already imported: ^1", call:getStat( 'alreadyImported' ) )
        app:log()
    
    end } )

end



-- menu handler
function RawPlusJpeg:viewJpegs( title )
    app:call( Service:new{ name=title, async=true, main=function( call )
        local viewer = app:getPref( "localViewer" )
        local mostSelOnly = app:getPref( 'localViewMostSelectedOnly' )
        local function view( fileOrFiles )
            if str:is( viewer ) then
                --app:log( "Opening file in local viewer, URL: ^1", url )
                app:executeCommand( viewer, app:getPref( "localViewerParam" ), fileOrFiles )
            else
                --app:log( "Opening file in browser, since no local viewer configured, URL: ^1", files )
                LrHttp.openUrlInBrowser( fileOrFiles )
            end
        end
        local photos = cat:getSelectedPhotos()
        local subs
        local msg
        local main={}
        local acc
        local buttons
        
        local props = LrBinding.makePropertyTable( call.context )
        initJpgQual( props, "View jpegs", main, 0 )
        initJpgSig( props, main, 10 )

        if #photos == 0 then
            msg = "View jpegs corresponding to raws in entire catalog??"
            photos = catalog:getAllPhotos()
        else
            msg = "View jpegs corresponding to raws amongst ^1?"
            subs = str:nItems( #photos, "selected photos" )
        end
        
        call:setCaption( "Dialog box needs your attention..." )
        local button = app:show{ confirm=msg,
            subs = subs,
            buttons = buttons,
            viewItems = main,
            accItems = acc,
        }
        if button == 'cancel' then
            call:cancel()
            return
        end
        
        call:setCaption( "Working..." )
        local cache = lrMeta:createCache{ photos=photos, rawIds={ 'path', 'fileFormat', 'isVirtualCopy' }, fmtIds={ 'fileName', 'copyName' } }
        local inCat, sidecars = getJpgQual()
        local sfx = app:getGlobalPref( 'jpgSig' ) or ""
        local subj = self:_getSubjectPhotoTable( photos, inCat, sidecars, sfx, cache )
        -- show the unedited versions for comparison. ###3?
        local mostSelIndex = subj.mostSelIndex or 1
        if #subj.allJpgPaths > 0 then
            call:setCaption( "Viewing..." )
            if str:is( viewer ) then -- ###3 orientation?
                if mostSelOnly then                
                    view( subj.allJpgPaths[mostSelIndex] )
                else
                    view( subj.allJpgPaths ) -- local viewer may or may not do the right thing. So far, ACDSee's quick viewer does not.
                end
            else
                call:setCaption( "Dialog box needs your attention..." )
                app:show{ info="No viewer configured - most selected will be viewed in browser.",
                    actionPrefKey="View most selected in browser",
                }
                call:setCaption( "Viewing..." )
                view( subj.allJpgPaths[mostSelIndex] )
            end
        else
            app:show{ warning='No such jpeg files were found for viewing.' }
        end
        call:cancel("") -- cancel log dialog box if no errors thrown.
    end } )
end



return RawPlusJpeg