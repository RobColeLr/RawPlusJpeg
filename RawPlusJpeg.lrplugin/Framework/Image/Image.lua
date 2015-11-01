--[[
        Image.lua
--]]


local Image, dbg, dbgf = Object:newClass{ className = "Image", register = true }


local iccProfileLookup = {
    ['AdobeRGB'] = LrPathUtils.child( _PLUGIN.path, 'AdobeRGB1998.icc' ),
    ['ProPhotoRGB'] = LrPathUtils.child( _PLUGIN.path, 'ProPhoto.icc' ),
    ['sRGB'] = LrPathUtils.child( _PLUGIN.path, 'sRGB_IEC61966-2-1_black_scaled.icc' )
}



--- Constructor for extending class.
--
function Image:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage       An unconventional contstructor which returns nil if can't be constructed, instead of throwing an error.
--
--  @return      new image instance, or nil.
--  @return      error message if no new instance.
--
function Image:new( t )
    if Image.mogrify == nil then
        if gbl:getValue( 'mogrify' ) then
            if mogrify:isUsable() then
                Image.mogrify = mogrify
                Debug.logn( "Mogrify config'd" )
            else
                Image.mogrify = false
                Debug.logn( "Mog not usable" )
            end
        else
            Image.mogrify = false
            Debug.logn( "No mog" )
        end
    else
        --Debug.pause( "mog not nil", Image.mogrify )
    end
    if Image.exifTool == nil then
        if gbl:getValue( 'exifTool' ) then
            if exifTool:isUsable() then
                Image.exifTool = exifTool
                Debug.logn( "ExifTool config'd" )
            else
                Debug.logn( "Exiftool not usable" )
                Image.exifTool = false
            end
        else
            Debug.logn( "No exiftool" )
            Image.exifTool = false
        end
    end
    local o = Object.new( self, t )
    local s, m
    if o.file and o.content then
        s, m = fso:writeFile( o.file, o.content, o.assureDir, o.dontOverwrite ) -- added param 'true' (16/Jul/2012 18:04) so image file will be created even if folder does not exist yet.
        -- note: the default is to overwrite if already exists.
    else
        s, m = false, "need file and content to create an image"
    end
    if s then
        o.mogParam = {}
        o.etParam = {}
        return o
    else
        return nil, m -- calling context mus check for nil.
    end
end



--- Transfer metadata from source photo to target photo, using exiftool.
--
--  @usage Metadata to transfer is specified in local prefs.
--
function Image:transferMetadata( fromPhoto, fromPath, profile, toPath, fmtMeta, ets )
    -- variables to return
    local s, m = false, "unknown error"
    app:call( Call:new{ name="Transfer Metadata", main=function( call )

        if ets then
            Debug.logn( "Transferring metadata using exiftool session" )
            assert( type( ets ) == 'table', "ets not table" )
        else
            ets = Image.exifTool
            assert( ets ~= nil, "ExifTool required to transfer image metadata" )
            Debug.logn( "Transferring metadata via exiftool proper." )
        end
        
        local nMetaArgs = 0
        local function addMetaArg( arg )
            ets:addArg( arg )
            nMetaArgs = nMetaArgs + 1
        end
        
        local exifMeta = app:getPref( 'exifMeta' ) -- isolate config for exiftool metadata transfer.

        if exifMeta then    
            
            --ets:addArg( str:fmt( "-fast\n-fast2\n-X\n^1", fromPath ) ) -- '-fast2' means omit maker-notes. -fast means ignore JPEG metadata blocks that come after the image block (no effect on other formats).
                -- I don't *think* Lightroom is storing any useful metadata after the main image block.
            ets:addArg( "-fast\n-fast2\n-X\n" ) -- '-fast2' means omit maker-notes. -fast means ignore JPEG metadata blocks that come after the image block (no effect on other formats).
                -- Note: arg adder will split newlines when included, although may be cleaner to separate arg add calls.
            ets:addTarget( fromPath )
            local content, comment = ets:execute()
            if content then
                app:logVerbose( "exif xml file obtained" )
            elseif comment then
                app:error( "Unable to obtain metadata (of '^1') using exiftool for icc profile info and such stuff, error message: ^2", fromPath, comment )
            elseif shutdown then
                call:abort( "shutdown" )
                return
            else
                app:error( "ets session execute returned bogus value(s)" )
            end
            -- _debugTrace( "x: ", content )
            local tbl = xml:parseXml( content )
            if not tbl then
                app:error( "Unable to parse exiftool output for icc profile info and such stuff." )
            end
            local stf = ((tbl[2] or {}) [1]) or {}
            for j = 1, #stf do
                repeat
                    local thng = stf[j]
                    if thng == nil then
                        break
                    end
                    
                    local ns = thng.ns
                    local name = thng.name
                    
                    local ref = exifMeta[ns]
                    if ref then
                        local t = ref[name]
                        if t then -- meta include
                            local value = thng[1]
                            if str:is( value ) then
                            
                                addMetaArg( "-" .. thng.label .. "=" .. value )

                            else
                                dbg( "xar ", name )
                            end
                        else
                        
                        end
                        
                    else
                    end                        
                until true                    
            end
        else
            app:logVerbose( "No exif-meta configured for transfer." )
        end
                    
        if profile ~= nil and profile ~= 'sRGB' then
            local profilePath = iccProfileLookup[profile]
            if profilePath then
                app:logVerbose( "Assigning icc profile via exif-tool: ^1", profilePath )
                addMetaArg( "-icc_profile<=" .. profilePath )
            else
                app:error( "ICC profile not supported: ^1", profile )
            end
        else -- ###2 - It's possible in some scenarios for untagged image to not be interpreted as sRGB, so really this should be robustened.
            app:logVerbose( "*** Not assigning sRGB profile." )
        end
        
        local _lrMeta = app:getPref( 'lrMeta' )
        if _lrMeta ~= nil then
            for name, tag in pairs( _lrMeta ) do
                local value = cat:getFormattedMetadata( fromPhoto, name, fmtMeta ) -- most.
                if value == nil then
                    value = fromPhoto:getRawMetadata( name ) -- very few.
                end
                if value ~= nil then
                    if type( value ) == 'string' then
                        if value ~= "" then
                            addMetaArg( '-' .. tag .. "=" .. value )
                        else
                            app:logVerbose( "xmp val blank: ^1", tag )
                        end
                    elseif type( value ) == 'number' then
                        addMetaArg( "-" .. tag .. "=" .. value )
                    elseif type( value ) == 'boolean' then
                        addMetaArg( "-" .. tag .. "=" .. str:to( value ) )
                    else
                        app:logWarning( "Type?" .. type( value ) )
                        addMetaArg( "-" .. tag .. "=" .. str:to( value ) )
                    end
                else
                    app:logVerbose( "No lr metdata for " .. name )
                end
            end
        else
            app:logVerbose( "No Lr Metadata" )
        end

        local spec = app:getPref( 'lrSpecialMeta' )
        if spec then
            -- keywords:
            local kwTags = spec.keywordTags
            local kwTags4Exp = spec.keywordTagsForExport
            local kwStr
            if kwTags then
                kwStr = fromPhoto:getFormattedMetadata( 'keywordTags' )
            elseif kwTags4Exp then
                kwStr = fromPhoto:getFormattedMetadata( 'keywordTagsForExport' )
            else
                app:logVerbose( "No keywords" )
            end
            if str:is( kwStr ) then
                -- argFileBuf[#argFileBuf + 1] = str:fmt( '-sep ", " -keywords+="^1"', kwStr ) - couldn't get this to work.
                local kwArr = str:split( kwStr, "," )
                for i, key in ipairs( kwArr ) do -- this works...
                    addMetaArg( "-keywords+=" .. key )
                end
            end 
            -- copyright status
            if spec.copyrightState then
                local status = fromPhoto:getRawMetadata( 'copyrightState' )
                if status == 'copyrighted' then
                    addMetaArg( "-XMP-xmpRights:Marked=True" )
                elseif status == 'public domain' then
                    addMetaArg( "-XMP-xmpRights:Marked=False" )
                -- else don't mark it.
                end
            end
                    
        else
            app:logVerbose( "No special metadata like keywords." )
        end        
        
        if nMetaArgs > 0 then
       
            ets:addTarget( toPath )
            
            if LrFileUtils.exists( toPath ) then
                app:logVerbose( "Raw jpg still exists: ^1", toPath )
                
                local rsp, msg = ets:execute()

                if rsp then
                    --app:log( "Metadata transferred using this command: " .. m )
                    app:log( "Metadata transferred via exif-tool." )
                else
                    --app:error( "Unable to assign metadata and icc profile, error message: " .. m )
                    app:error( "Unable to assign metadata and icc profile, error message: " .. str:to( msg ) )
                end
            else
                app:error( "Can't do exiftool command - ^1 no longer exists.", toPath )
            end
        else
            app:log( "*** No metadata to transfer." ) -- perfectly acceptable that the photo did not have any of the specified metadata, so no harm no foul, but always log a pseudo-warning,
                -- since probably indicates a malcurrence.
        end

    end, finale=function( call, status, message )
        -- normally deleted, but in case of error:
        local original = toPath .. "_original"
        if fso:existsAsFile( original ) then
            LrFileUtils.delete( original )
        end
        local temp = toPath .. "_exiftool_tmp"
        if fso:existsAsFile( temp ) then
            local sts, msg = fso:moveFolderOrFile( temp, toPath )
            if sts then
                if app:getUserName() == "_RobCole_" then
                    app:logWarning( "Cleaned up exiftool-tmp file." )
                else
                    app:logVerbose( "Cleaned up exiftool-tmp file." )
                end
            else
                if status then
                    status = false
                    message = "Unable to rename exiftool temp file: " .. str:to ( msg )
                else
                    message = str:to ( message ) .. ". Also, unable to rename exiftool temp file: " .. str:to ( msg )
                end
            end
        end
        s, m = status, message
    end } )
    --Debug.showLogFile()
    return s, m

end




function Image:addMogParam( ... )
    tab:appendArray( self.mogParam, { ... } )
end




function Image:addExifToolParam( ... )
    tab:appendArray( self.etParam, { ... } )
end



-- profile-name is name of profile that should rightfully be assigned to unmodified image data.
-- 
function Image:addColorProfile( icc, profileName, toProfile, ets )
    if icc == 'A' or ( icc == 'C' and profileName ~= 'sRGB' and profileName == toProfile) then -- assignment, or conversion from non-sRGB profile.
        if profileName ~= 'sRGB' then
            local file = iccProfileLookup[profileName]
            if file then
                if fso:existsAsFile( file ) then
                    if ets then -- a true exiftool session pre-empts the others
                        assert( type( ets ) == 'table', "ets not table" )
                        Debug.logn( "Adding (non-sRGB) color profile via exiftool session." )
                        self.etParam[#self.etParam + 1] = str:fmt( '-icc_profile<=^1', file ) -- Note: argfilebuf does NOT like double-quotes around this.
                    elseif Image.mogrify then -- mogrifier is preferred over exiftool, if no true session.
                        Debug.logn( "Adding color profile via mogrify." )
                        self.mogParam[#self.mogParam + 1] = str:fmt( '-profile "^1"', file )
                    elseif Image.exifTool then -- 
                        Debug.logn( "Adding color profile via exiftool proper." )
                        self.etParam[#self.etParam + 1] = str:fmt( '"-icc_profile<=^1"', file ) -- Note: unless args are in a file buf, the quotes need to span the whole thing (not just the icc file path) - unlike mogrify (see above).
                    else
                        -- Debug.pause( Image.mogrify )
                        app:error( "Nothing configured that can add a color profile." )
                    end
                else
                    app:error( "Missing " .. file )
                end
            else
                app:error( "ICC profile not supported: ^1", profileName ) 
            end
        else -- 'sRGB' -- note: this assumes the data *is* rgb, if its *not*, then do a convert instead.
            app:logVerbose( "No assignment of color profile in case of sRGB" )
        end
    elseif icc == 'C' and not ( profileName == toProfile ) then -- convert from something to something else.
        local file = iccProfileLookup[profileName]
        if file then
            if fso:existsAsFile( file ) then
                local file2 = iccProfileLookup[toProfile]
                if file2 then
                    if fso:existsAsFile( file2 ) then
                        if Image.mogrify then
                            dbgf( "Converting from ^1 to ^2 profile via mogrify.", file, file2 )
                            self.mogParam[#self.mogParam + 1] = str:fmt( '-profile "^1" -profile "^2"', file2, file )
                        else
                            app:error( "ImageMagick mogrify must be configured to convert icc color profile." )
                        end
                    else
                        app:error( "Missing " ..  file2 )
                    end
                else
                    app:error( "ICC profile not supported: ^1", profileName ) 
                end
            else
                app:error( "Missing " .. file )
            end
        else
            app:error( "ICC profile not supported: ^1", profileName ) 
        end
    elseif icc ~= 'A' and icc ~= 'C' then
        app:callingError( "Bad icc op: ^1", icc )
    elseif profileName == 'sRGB' then
        assert( toProfile == 'sRGB', "icc profile mixup" )
        app:logVerbose( "No need to convert from sRGB to sRGB" )
    end
end



function Image:addOrientation( orient, ets )
    app:callingAssert( orient ~= nil, "no orient" )
    app:logVerbose( "Setting orientation of ^1 to ^2", self.file, orient  )
    self.orient = orient
    local useExifTool = false
    if ets then
        assert( type( ets ) == 'table', "ets not table" )
        useExifTool = true
        Debug.logn( "Considering orientation via exiftool session." )
    elseif Image.exifTool and not Image.mogrify then
        useExifTool = true
        Debug.logn( "Considering orientation via exiftool proper." )
    end
    if useExifTool then
        local p
        if orient == 'AB' then -- unflipped/unrotated, or its flipped & rotated equivalent.
            -- degrees = 0 - for purposes here, no need to rotate if 0 degrees.
            return
        elseif orient == 'BC' then
            p = "Rotate 90 CW" -- CW required.
        elseif orient == 'CD' then
            p = "Rotate 180" -- must not include a "CW" suffix.
        elseif orient == 'DA' then
            p = "Rotate 270 CW" -- must be CW.
        elseif orient == 'BA' then -- flipped horizontal, no rotation.
            p = "Mirror Horizontal"
        elseif orient == 'AD' then -- ", 90
            p = "Mirror Horizontal and Rotate 90 CW"
        elseif orient == 'DC' then -- ", 180 (which is equivalent to flipped vertically).
            p = "Mirror Vertical"
        elseif orient == 'CB' then -- ", 270
            p = "Mirror Horizontal and Rotate 270 CW"
        else
            app:callingError( "^1 has '^2' db-orientation, which is not yet supported - please report error: ", str:to( self.file ), orient )
        end
        Debug.logn( "Adding exiftool orientation param." )
        self.etParam[#self.etParam + 1] = '-Orientation=' .. p
    elseif Image.mogrify then
        Debug.logn( "Adding orientation via mogrify." )
        local degrees
        -- local suspect = "not sure what to do"
        local flop
        if orient == 'AB' then -- unflipped/unrotated, or its flipped & rotated equivalent.
            -- degrees = 0 - for purposes here, no need to rotate if 0 degrees.
            return
        elseif orient == 'BC' then
            degrees = 90
        elseif orient == 'CD' then
            degrees = 180
        elseif orient == 'DA' then
            degrees = 270
        elseif orient == 'BA' then -- flipped horizontal, no rotation.
            flop = "-flop"
        elseif orient == 'AD' then -- ", 90
            flop = "-flop"
            degrees = 90
        elseif orient == 'DC' then -- ", 180 (which is equivalent to flipped vertically).
            flop = "-flip"
        elseif orient == 'CB' then -- ", 270
            flop = "-flop"
            degrees = 270
        else
            app:callingError( "^1 has '^2' db-orientation, which is not yet supported - please report error: ", str:to( self.file ), orient )
        end
        if flop then
            self.mogParam[#self.mogParam + 1] = flop
        end
        if degrees then
            self.mogParam[#self.mogParam + 1] = '-rotate ' .. degrees
        end
    else
        app:error( "Nothing configured to do orientation." )
    end
end



--- Commit all mogrification and exiftool'n transformations.
--
function Image:commit( ets )
    --[[ *** OBS:
    local mog = app:getPref( 'mogrify' )
    if not str:is( mog ) then
        return false, "cant find mogrify setting in plugin manager configuration"
    end
    --]]
    if ets ~= nil then
        Debug.logn( "image commission via exiftool session" )
    else
        Debug.logn( "image commission via exiftool proper" )
        ets = Image.exifTool
    end
    local s, m, c = true, "", ""
    -- Do exiftool before mogrification, since mogrification may depend on icc-profile having been assigned already...
    if not tab:isEmpty( self.etParam ) then
    
        if ets then
            self:addExifToolParam( "-overwrite_original" )
            for i, v in ipairs( self.etParam ) do
                ets:addArg( v )
                Debug.logn( "etParam", v )
            end
            ets:addTarget( self.file ) 
            Debug.logn( "target", self.file )            
            local resp, msg = ets:execute()
            if not str:is( msg ) then
                if str:is( resp ) then
                    -- ###2 need exiftool to parse response.
                    Debug.logn( "exiftool session - response to execute command: " .. resp )
                else
                    app:logError( "Unable to exiftool image - no response" )
                    s, m, c = false, "no message", "no response"
                end
            else
                app:logError( "Unable to exiftool image - ^1", msg )
                s, m, c = false, msg, "response unknown"
            end
        else
            Debug.logn( "Exiftool'n skipped:" )
            Debug.lognpp( self.etParam )
            app:error( "Imaging operations requiring exif-tool are not supported unless exiftool app has been configured." )
        end
    else
        Debug.logn( "No additional ExifTool'n needed for commission." )
    end
    -- Finish with mogrification.
    if not tab:isEmpty( self.mogParam ) then
        if Image.mogrify then
            Debug.logn( "image commission includes mogrification" )
            local param = table.concat( self.mogParam, " " )
            --local s, m = app:executeCommand( mog, param, { self.file } )
            s, m, c = mogrify:executeCommand( param, { self.file } )
            if s then
                local ext = param:match( "%-format%s+(%w-)%s+" )
                if not str:is( ext ) then
                    ext = param:match( "%-format%s+(%w-)$" )
                end
                if str:is( ext ) then
                    --Lr File Utils . delete ( self . file ) -- can't do this so soon or the export fails.
                    self.file2 = LrPathUtils.replaceExtension( self.file, ext )
                    app:logVerbose( "converted to ^1", self.file2 )
                    --LrShell.revealInShell( self.file2 )
                else
                    -- Debug.pause( "no match in", param )
                    Debug.logn( "mog good: " .. str:to( m ) )
                end
            else
                app:error( "Unable to mogrify, error message: ^1", str:to( m ) )
            end
        else
            Debug.logn( "Mogrification skipped:" )
            Debug.lognpp( self.mogParam )
            app:error( "Imaging operations requiring mogrification are not supported unless Image Magick's mogrify app has been configured." )
        end
    else
        Debug.logn( "No mog'n to be done to image." )
    end
    self.etParam = {}
    self.mogParam = {}
    return s, m
end



--- Get image file path.
--
function Image:getFile()
    if self.file2 then -- not the smoothest ###2
        -- delete self.file?
        return self.file2
    else
        return self.file
    end
end



--- Static function to normalize image coordinates from internal (xmp-compatible) format to "what you see" format, taking orientation into consideration.
--
--  @param orientation  As per exiftool'd xmp, *not* (catalog) db, not dev settings.
--  @param top          in fractional format (as opposed to pixels)
--  @param left         in fractional format (as opposed to pixels)
--  @param bottom       in fractional format (as opposed to pixels)
--  @param right        in fractional format (as opposed to pixels)
--
--  @usage              Assures coordinates are properly bounded within image, msg returned indicates type of correction needed, if any.
--  @usage              Orientation takes flip into account.
--
--  @returns            top
--  @returns            left
--  @returns            bottom
--  @returns            right
--
function Image.normalizeCoordinates( orientation, top, left, bottom, right, angle, wholeDim )

    if type( orientation ) == 'number' then
        app:callingError( "orientation must be exif-tool compatible string" )
    elseif type( orientation ) == 'string' then
        -- good
    else
        app:callingError( "bad orientation type" )
    end
    
    if angle ~= 0 then
        local sin = math.sin( math.rad( -angle ) )
        local cos = math.cos( math.rad( -angle ) )      
        
        -- fractional
        local wFrac = right - left
        local hFrac = bottom - top

        -- reverse for portraits (?)
        local wholeW = wholeDim.width
        local wholeH = wholeDim.height
        
        local wPix = wFrac * wholeW -- 2144
        local hPix = hFrac * wholeH -- 1424
        
        --Debug.pause( crsW, crsH, w, h )
        
        local leftInPixels = left * wholeW
        local topInPixels = top * wholeH
        local rightInPixels = right * wholeW
        local bottomInPixels = bottom * wholeH
        
        -- x, y -> coordinates, in pixels, of upper left corner of crop box, relative to center of crop box (and hence, center of rotation).
        local x = -wPix/2
        local y = -hPix/2
        
        -- xT, yT -> angled coordinates, transformed according to angle, but still relative to center of rotation/crop-box.
        local xT = x * cos - y * sin
        local yT = x * sin + y * cos
        
        -- xP, yP -> angled coordinates, in pixels, relative to upper left corner of image.
        local xP = leftInPixels + ( xT - x )
        local yP = topInPixels + ( yT - y )
        
        -- xF, yF -> final coordinates, as fractional values.
        left = xP / wholeW
        top = yP / wholeH
        
        -- x, y -> coordinates, in pixels, of upper left corner of crop box, relative to center of crop box (and hence, center of rotation).
        local x = wPix/2
        local y = hPix/2
        
        local xT = x * cos - y * sin
        local yT = x * sin + y * cos
        
        -- xP, yP -> angled coordinates, in pixels, relative to upper left corner of image.
        local xP = rightInPixels + ( xT - x )
        local yP = bottomInPixels + ( yT - y )
        
        -- xF, yF -> final coordinates, as fractional values.
        right = xP / wholeW
        bottom = yP / wholeH
        
        --Debug.pause( left, top, right, bottom )
        
    else
        -- angle == 0 => no rotation required.
    end
            
    local t, l, b, r

    -- mirror horizontal and rotate 180 same as mirror vertical.
    -- mirror vertical and rotate 180 same as mirror horizontal.
    -- mirror vertical and rotate 270 CW sames as mirror horizontal and rotate 90 CW.
    -- mirror vertical and rotate 90CW same as mirror horizontal and rotate 270 CW.
    
    -- norm
    if orientation == 'Horizontal (normal)' then
        
        -- confirmed:
        return top, left, bottom, right
        
    elseif orientation == 'Mirror horizontal' then

        -- confirmed:
        t = top
        l = 1 - right
        b = bottom
        r = 1 - left
        
    elseif orientation == 'Mirror vertical' then
    
        -- confirmed:
        t = 1 - bottom
        l = left
        b = 1 - top
        r = right
    
    elseif orientation == 'Rotate 90 CW' then

        -- confirmed:
        t = left
        l = 1 - bottom
        b = right
        r = 1 - top
    
    elseif orientation == 'Rotate 180' then
    
        -- confirmed:
        t = 1 - bottom
        l = 1 - right
        b = 1 - top
        r = 1 - left
    
    elseif orientation == 'Rotate 270 CW' then

        -- confirmed:
        t = 1 - right
        l = top
        b = 1 - left
        r = bottom

    elseif orientation == 'Mirror horizontal and rotate 270 CW' then

        -- confirmed    
        t = left
        l = top
        b = right
        r = bottom
    
    elseif orientation == 'Mirror horizontal and rotate 90 CW' then
    
        -- confirmed    
        t = 1 - right
        l = 1 - bottom
        b = 1 - left        
        r = 1 - top
        
    else
        app:callingError( "Unrecognized orientation." )
    end
    
    return t, l, b, r
end





--- Static function to map (presumably modified) image coordinates from "what you see" format to internal (xmp-compatible) format, taking orientation into consideration.
--
--  @param orientation  As per exiftool'd xmp, *not* (catalog) db, not dev settings.
--  @param top          in fractional format (as opposed to pixels)
--  @param left         in fractional format (as opposed to pixels)
--  @param bottom       in fractional format (as opposed to pixels)
--  @param right        in fractional format (as opposed to pixels)
--
--  @usage              Assures coordinates are properly bounded within image, msg returned indicates type of correction needed, if any.
--  @usage              Orientation takes flip into account.
--
--  @returns            top
--  @returns            left
--  @returns            bottom
--  @returns            right
--  @returns            msg         nil unless correction(s) needed to keep coordinates in range.
--
function Image.mapCoordinates( orientation, top, left, bottom, right, angle, wholeDim )
    if type( orientation ) == 'number' then
        app:callingError( "orientation must be exif-tool compatible string" )
    elseif type( orientation ) == 'string' then
        -- good
    else
        app:callingError( "bad orientation type: ^1", type( orientation ) )
    end

    local t, l, b, r, msg

    -- mirror horizontal and rotate 180 same as mirror vertical.
    -- mirror vertical and rotate 180 same as mirror horizontal.
    -- mirror vertical and rotate 270 CW sames as mirror horizontal and rotate 90 CW.
    -- mirror vertical and rotate 90CW same as mirror horizontal and rotate 270 CW.

    -- note: dimensions are in mapped domain (reversed for portrait orientations)
    -- default to landscape oriented dimensions
    local wholeW = wholeDim.width
    local wholeH = wholeDim.height
    
    -- map orthogonally
    if orientation == 'Horizontal (normal)' then
        
        t = top
        l = left
        b = bottom
        r = right
        
    elseif orientation == 'Mirror horizontal' then

        t = top
        l = 1 - right
        b = bottom
        r = 1 - left
        
    elseif orientation == 'Mirror vertical' then
    
        t = 1 - bottom
        l = left
        b = 1 - top
        r = right
    
    elseif orientation == 'Rotate 90 CW' then
    
        wholeW = wholeDim.height
        wholeH = wholeDim.width
    
        t = 1 - right
        l = top
        b = 1 - left
        r = bottom
    
    elseif orientation == 'Rotate 180' then
    
        t = 1 - bottom
        l = 1 - right
        b = 1 - top
        r = 1 - left
    
    elseif orientation == 'Rotate 270 CW' then -- mirror vertical and rotate 90CW
    
        wholeW = wholeDim.height
        wholeH = wholeDim.width
    
        t = left
        l = 1 - bottom
        b = right
        r = 1 - top
    
    elseif orientation == 'Mirror horizontal and rotate 270 CW' then
    
        wholeW = wholeDim.height
        wholeH = wholeDim.width
    
        t = left
        l = top
        b = right
        r = bottom
        
    elseif orientation == 'Mirror horizontal and rotate 90 CW' then
    
        wholeW = wholeDim.height
        wholeH = wholeDim.width
    
        t = 1 - right
        l = 1 - bottom
        b = 1 - left
        r = 1 - top
        
    else
        app:callingError( "Unrecognized orientation." )
    end
    
    -- rotate -45 to 45 degrees (true angle opposite sign from UI)
    -- uses basic formula for translating to polar coordinates, setting the angle, then translating back.
    if angle ~= 0 then
        local sin = math.sin( math.rad( angle ) )
        local cos = math.cos( math.rad( angle ) )      
        
    --[[ *** formula from Steve Sprengel
       ref:  http://feedback.photoshop.com/photoshop_family/topics/lightroom_camera_raw_dng_xmp_what_is_the_formula_for_converting_crop_coordinates_when_photo_gets_angled
       ref2: http://answers.yahoo.com/question/index?qid=20100314163944AAIu9xk
             
        x' = x * Cos(theta) - y * Sin(theta) + a
        y' = x * Sin(theta) + y * Cos(theta) + b
        
    --]]        
        
        -- fractional
        local wFrac = r - l
        local hFrac = b - t
        
        local wPix = wFrac * wholeW
        local hPix = hFrac * wholeH
        
        --Debug.pause( crsW, crsH, w, h )
        
        local leftInPixels = l * wholeW
        local topInPixels = t * wholeH
        local rightInPixels = r * wholeW
        local bottomInPixels = b * wholeH
        
        -- x, y -> coordinates, in pixels, of upper l corner of crop box, relative to center of crop box (and hence, center of rotation).
        local x = -wPix/2
        local y = -hPix/2
        
        -- xT, yT -> angled coordinates, transformed according to angle, but still relative to center of rotation/crop-box.
        local xT = x * cos - y * sin
        local yT = x * sin + y * cos
        
        -- xP, yP -> angled coordinates, in pixels, relative to upper l corner of image.
        local xP = leftInPixels + ( xT - x )
        local yP = topInPixels + ( yT - y )
        
        -- final coordinates, as fractional values.
        l = xP / wholeW
        t = yP / wholeH
        
        -- x, y -> coordinates, in pixels, of upper l corner of crop box, relative to center of crop box (and hence, center of rotation).
        local x = wPix/2
        local y = hPix/2
        
        local xT = x * cos - y * sin
        local yT = x * sin + y * cos
        
        -- xP, yP -> angled coordinates, in pixels, relative to upper l corner of image.
        local xP = rightInPixels + ( xT - x )
        local yP = bottomInPixels + ( yT - y )
        
        -- xF, yF -> final coordinates, as fractional values.
        r = xP / wholeW
        b = yP / wholeH
        
        --Debug.pause( l, t, r, b )
        
    else
        -- angle == 0 => no rotation required.
    end

    -- assure rotated coordinates are bounded in image:    
    local shrunk
    if t < 0 then
        b = b - t -- add t differential to b
        t = 0
        shrunk = true
    end
    if l < 0 then
        r = r - l -- add differential to maintain width.
        l = 0
        shrunk = true
    end
    if b > 1 then
        t = t - ( b - 1 )
        if t < 0 then
            t = 0
        end        
        b = 1
        shrunk = true
    end
    if r > 1 then
        l = l - ( r - 1 )
        if l < 0 then
            l = 0
        end
        r = 1
        shrunk = true
    end
    if t >= b then
        Debug.pause( t, b )
        return nil, nil, nil, nil, "Unable to accomodate specified height."
    end
    if l >= r then
        Debug.pause( l, r )
        return nil, nil, nil, nil, "Unable to accomodate specified width."
    end
    if shrunk then
        msg = "Some coordinates were modified to stay in range."
    end
    
    return t, l, b, r, msg

end


return Image