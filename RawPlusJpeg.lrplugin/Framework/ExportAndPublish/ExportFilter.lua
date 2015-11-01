--[[
        ExportFilter.lua
--]]


local ExportFilter, dbg, dbgf = Object:newClass{ className="ExportFilter", register=true }





--- Constructor for extending class.
--
function ExportFilter:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function ExportFilter:new( t )
    local o = Object.new( self, t )
    app:callingAssert( o.filterContext, "need filter context" )
    app:callingAssert( o.functionContext, "need function context" )
    -- o.excludeVideo = o.excludeVideo or false
    return o
end



--- Process rendered photos method.
--
--  @usage ordinarily, derived type would override this method, but maybe not..
--
function ExportFilter:processRenderedPhotosMethod()

    local filterContext = self.filterContext
    local exportSettings = filterContext.propertyTable

    -- Debug.lognpp( exportSettings )
    
    local one = exportSettings.one
    if exportSettings.LR_size_doConstrain then
        if exportSettings.LR_size_resizeType == "wh" then
            -- ...
        else
            -- app:error( "Invalid resize type, only 'Width & Height' supported." )
        end
    else
        -- app:logVerbose( "No resize" )
    end

    local renditionOptions = {
        filterSettings = function( renditionToSatisfy, exportSettings )
            --exportSettings.LR_format = 'ORIGINAL' -- quickest export is original (forcing rendering error by using bad format takes takes 3 seconds per photo).
            --return renditionToSatisfy.destinationPath -- extension will be jpg ('twas pre-checked in should-render-photo).
        end,
    }
    for sourceRendition, renditionToSatisfy in filterContext:renditions( renditionOptions ) do
        repeat
            local success, pathOrMessage = sourceRendition:waitForRender()
            if success then
                Debug.logn( "Source \"rendition\" created at " .. pathOrMessage )
                if pathOrMessage ~= renditionToSatisfy.destinationPath then
                    app:logVerbose( "Destination path was originally to be '^1', but has changed to '^2'", renditionToSatisfy.destinationPath, pathOrMessage )
                end
            else -- problem exporting original, which in my case is due to something in metadata blocks that Lightroom does not like.
                app:logWarning( "Unable to export '^1', error message: ^2. This may not cause a problem with this export, but may indicate a problem with this plugin, or with the source photo.", renditionToSatisfy.destinationPath, pathOrMessage )
                pathOrMessage = renditionToSatisfy.destinationPath
            end    
            app:call( Call:new{ name="Post-Process Rendered Photo", main=function( context )
            
                -- ...
            
            end, finale=function( call, status, message )
                if status then
                    --
                else
                    app:logErr( message ) -- errors are not automatically logged for base calls, just services.
                end
            end } )
        until true
    end
end



--- This function will check the status of the Export Dialog to determine 
--  if all required fields have been populated.
--
function ExportFilter.updateFilterStatus( id, props, name, value )
    app:call( Call:new{ name="Update Filter Status", guard=App.guardSilent, main=function( context ) -- not asynchronous, but derived impl. can be.
        local message = nil
        repeat
        	-- Initialise potential error message.
        	if id ~= nil then
        	
        	    -- named property has changed
        	
            	if props.one == nil then
            	    message = "need prop one"
            	    break
            	end
            	
            	if name == 'one' then
            	--elseif
            	--else
        	    end

            end
            
            -- process stuff not tied to change necessarily
            
        until true	
    	if message then
    		-- Display error.
	        props.LR_cantExportBecause = message
    
    	else
    		-- All required fields and been populated so enable Export button, reset message and set error status to false.
	        props.LR_cantExportBecause = nil
	        
    	end
    end } )
end




--- This optional function adds the observers for our required fields metachoice and metavalue so we can change
--  the dialog depending if they have been populated.
--
function ExportFilter.startDialog( propertyTable )

	view:setObserver( propertyTable, 'one', ExportFilter, ExportFilter.updateFilterStatus ) -- assures no observer "buildup".
	ExportFilter.updateFilterStatus( nil, propertyTable )

end




--- This function will create the section displayed on the export dialog 
--  when this filter is added to the export session.
--
function ExportFilter.sectionForFilterInDialog( vf, propertyTable )
	
	return {
		title = app:getAppName(),
		vf:row {
			vf:static_text {
				title = "One",
			},
		},
		vf:row {
			spacing = vf:control_spacing(),
			vf:static_text {
				title = "Minimum Size",
				width = share 'labels',
			},
		}
    }
	
end



ExportFilter.exportPresetFields = {
	{ key = 'one', default=nil },
}



--- This function obtains access to the photos and removes entries that don't match the metadata filter.
--
--  @usage Worth noting: there is *no* filter-context at this stage, nor export session, nor export context...
--
function ExportFilter.shouldRenderPhoto( exportSettings, photo )

    -- Debug.lognpp( exportSettings )
    
    local fileFormat = photo:getRawMetadata( 'fileFormat' )
    if fileFormat == 'VIDEO' then
        return false
    end

    local targetExt = LrExportSettings.extensionForFormat( exportSettings.LR_format, photo )
    if type( targetExt ) == 'table' then -- just returns photo in case of "original" format.
        return false
    else
        if LrStringUtils.lower( targetExt ) == 'jpg' then
    	    return true
    	else
    	    -- app:logWarning( app:getAppName() .. " does not support non-jpg file format." )
    	    --return false
    	    return true
    	end
    end	
    
end



--- Post process rendered photos.
--
function ExportFilter.postProcessRenderedPhotos( functionContext, filterContext )

    if filterContext.exportFilter == nil then
        filterContext.exportFilter = objectFactory:newObject( "ExportFilter", { functionContext=functionContext, filterContext=filterContext } ) -- hopefully Lr won't mind if a member is added to the filter context (?)
        -- this gives a nice way to tap in without going whole-hog oo, like was done for export and publish objects, proper.
    end
    
    filterContext.exportFilter:postProcessRenderedPhotosMethod()

end



return ExportFilter
