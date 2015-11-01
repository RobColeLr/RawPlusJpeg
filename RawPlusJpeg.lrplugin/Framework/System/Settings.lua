--[[
        Settings
        
        Note: constructor accepts a settings file (base) name, however presently only Default.txt is being used, since constructor is being called in init-framework sans name.
--]]

local Settings, dbg, dbgf = Object:newClass{ className = 'Settings' }



-- data-type registry:
local dataTypeReg = tab:createSet{ 'string', 'number', 'boolean', 'function', 'array', 'proxy' } -- target variable types.
-- pref-data registry (lua types).
local prefTypeReg = tab:createSet{ 'string', 'number', 'boolean' } -- at the moment, all table prefs are implemented as simple elements, names array is kept in prefs as table, but that's the only thing.



--- Constructor for extending class.
--
function Settings:newClass( t )
    return Object.newClass( self, t )
end



--- Constructs a new preference manager.
--      
--  <p>Installation procedure is going to have to be smart enough to deal with pre-existing directory upgrade.</p>
--
--  <p>This object manages named preference sets. Exclude and you just have the reglar set of unnamed (un-prefixed) prefs...</p>
--
--  <p>Param Table In:<blockquote>
--          - name(id): set name. if missing, then default set.<br>
--          - file-essential boolean.</blockquote></p>
--                          
--  <p>Object Table Out:<blockquote>
--          - friendlyName: same as name/id except for default.<br>
--          - file (path)<br>
--          - prefs (name-val table)</blockquote></p>
--      
--  @param      t       input parameter table.
--
--  @usage              Subdirectory for supplemental files is 'Settings' in plugin directory.
--  @usage              See app class pref methods for more info.
--
--  @return             Preference manager object.
--
function Settings:new( t )

    assert( app, "no app" )

    local o = Object.new( self, t )
    
    o.lookup = {} -- lookup initialized items for subsequent get'ing.
    o.reg = {}
    o.err = {}

    local s, m = pcall( o.initialize, o ) -- mustn't end up with un-created settings object despite errors - this method will report critical errors to user.
    
    return o
end



function Settings:initialize()
    local settingsName = app:getGlobalPref( 'presetName' )
    if not str:is( settingsName ) then
        settingsName = 'Default'
    end
    local found, warned
    
    local dir = LrPathUtils.child( _PLUGIN.path, 'Settings' )
    for file in LrFileUtils.files( dir ) do
        repeat
            local ext = LrStringUtils.lower( LrPathUtils.extension( file ) )
            if ext ~= 'lua' and ext ~= 'txt' then
                app:logv( "file with unrecognized extension in plugin settings folder - ignored: ^1", file )
                break
            end
            app:log( "Initializing settings based on lua/txt file: ^1", file )            
            local s, elem = pcall( dofile, file )
            if not s then
                app:logErr( "Settings file is bad (usually syntax error due to editing mistake) - ^1", elem )
            end
            local filename = LrPathUtils.leafName( file )
            local basename = LrPathUtils.removeExtension( filename )
            local key = self:getKey( "settings", basename )
            if s then
                self:initAndRegister( key, elem )
                if basename == settingsName then
                    found = true
                end
            else
                self.err[key] = elem
                if settingsName ~= basename then
                    app:show{ warning="Unable to load settings from '^1' due to error: ^2", file, elem }
                    warned = true
                end
            end
        until true
    end
    if found then -- active settings are OK.
        app:log( "Settings: ^1", settingsName )
    elseif not warned then
        if self.reg[self:getKey( "settings", "Default" )] then -- default settings are OK
            local answer = app:show{ confirm="Settings named '^1' are not OK - resort to 'Default' instead? (if not 'OK', you will need to repair settings file, then reload plugin)", settingsName }
            if answer == 'ok' then
                app:setGlobalPref( 'presetName', 'Default' )
                app:log( "Resorting to 'Default' settings" )
            else
                app:logv( "*** user chose not to resort to default settings - plugin is not yet healthy, settings-wise..." )
            end
        else
            --app:show{ error="Settings file corresponding to '^1' has an error in it - consider re-installing plugin, or manually repair settings file(s).", settingsName } - redundent.
        end
    else
        app:logv( "*** settings are not ok, yet." )
    end
end



function Settings:initAndRegister( key, dataDescr )
    self:init{ key=key, items=dataDescr, bindTo=prefs, forceInit=false }
    self.reg[key] = dataDescr
end



function Settings:getDataDescr( key )
    local reg = self.reg[key] -- roots
    if reg then
        return reg
    else
        local spec = self.lookup[key]
        if spec then
            if spec.elem then
                return spec.elem
            else
                Debug.pause( "not sure if spec is data-descr - error? ###4" ) -- this hasn't happened recently @3/Jan/2013, not sure what I was thinking...
                return spec
            end
        else
            return nil, self.err[key] or str:fmtx( "Data descriptor not found for '^1'", key )
        end
    end
end



--- Get settings root view items and lookup.
function Settings:getViewItemsAndLookup( call )
    local s, m, viewItems, viewLookup = app:call( Call:new{ name="Getting additional settings view items", async=false, main=function( icall )
    
        local viewItems, viewLookup
        local key, settingsName = app:getSettingsKey()
        
        local dataDescr, errm = systemSettings:getDataDescr( key )
        if not dataDescr then
            app:error( "Unable to obtain settings for '^1' - consider checking settings name (in plugin manager), or maybe the settings file is wonky, key: '^2', error message: ^3", settingsName, key, errm )
        end
        
        viewItems, viewLookup = systemSettings:getViewItems { -- does non-forced init by default.
            dataDescr = dataDescr,
            bindTo = prefs,
            key = key,
            init = false, -- already initialized in constructor.
            call = call,
        }

        if tab:isNotEmpty( viewItems ) then
        
            --Debug.lognpp( viewItems, viewLookup )
        
            viewItems.width = 600
            viewItems.height = 800
            viewItems.margin = 1

        else
            app:error( "no view items" )
        end
        return viewItems, viewLookup
        
    end, finale=function( call )
        -- reminder: errors are reflected in returned status when call is synchrounous.
    end } )
    --Debug.pause( viewItems )
    if s then
        return app:assert( viewItems, "no view items" ), app:assert( viewLookup, "no view lookup" ) -- don't call if no additional settings defined for plugin.
    else
        return nil, nil, m
    end
end




function Settings:isKeyRelative( key )
    app:callingAssert( key, "no key" )
    app:callingAssert( type( key ) == 'string', "key not string: ^1", type( key ) )
    if key:sub( 1, 2 ) ~= "__" then
        return true
    else
        return false
    end
end



--- Translate key names, into usable form (internal format).
--  Internal format is a string with double-underscore to delimiter/separate.
--
--  @param rootKeyOrName (string) may already be in internal format - it's ok.
--  @param ... (strings) if var-args present, root-key-or-name is prepended to far-args, otherwise root-key-or-name is considered relative to current (root) settings key.
function Settings:getKey( rootKeyOrName, ... )
    app:callingAssert( rootKeyOrName, "no root key" )
    local key
    local varArgs = {...}
    if rootKeyOrName:sub( 1, 2 ) == "__" then -- is key
        key = rootKeyOrName
    else -- name
        key = '__' .. rootKeyOrName -- make key
    end
    -- append sub keys.
    if #varArgs > 0 then
        for i, name in ipairs( varArgs ) do
            key = key .. "__" .. name
        end
    else
        local rootKey = app:getSettingsKey() -- get root key corresponding to presently selected preset, or default...
        key = rootKey .. key -- key already has underscores, as does root-key.
    end
    return key
end



--- Get new key from parent key and child name.
--
function Settings:childKey( parentKey, childName )
    return parentKey .. "__" .. childName
end 



function Settings:getArrayNames( key, bindTo )
    if bindTo == nil then
        return prefs[key .. "_names"] -- default is prefs.
    else
        return bindTo[key .. "_names" ]
    end
end



function Settings:getNamesKey( key )
    return key .. "_names"
end



function Settings:getArrayElemByName( setKey, bindTo, name )
    bindTo = bindTo or prefs
    local names = bindTo[setKey .. "_names"]
    local index
    for i, v in ipairs( names ) do
        if str:isEqualIgnoringCase( v, name ) then
            index = i
            break
        end
    end
    local set
    if index then --and index <= #whole then
        set = systemSettings:getValue( setKey, bindTo, { index=index } )
    else
        return nil, "name does not exist in array"
    end
    if set then
        --customSet.customSetName = customSetName
        --Debug.lognpp( "got custom set", customSet )
        return set
    else
        --Debug.pause( , customSetName, index, #whole )
        return nil, str:fmtx( "unable to get array element" )
    end
end



--[[  *** save for possible future resurrection. Note: supports preset duplication.
prefix keys need to take array indexes into account, etc. - this would be easy for duplicating entire tree,
but not a specified item.
function Settings:_copySettings( bindTo, rootKey, oldName, newName )
    if newName == 'Default' then
        app:callingError( "can't move prefs to default - check new-name before calling." )
    end
    --local oldKey, _oldName = app:getSettingsKey( oldName )
    local oldPrefix = rootKey .. "__"
    local pos = oldPrefix:len() + 1
    local newKey, _newName = app:getSettingsKey( newName )
    local newPrefix = str:searchAndReplace( oldPrefix, oldName, newName, nil, 1 ) -- no pad-char, only replace first occurrence.
    Debug.pause( oldPrefix, newPrefix )
    for k, v in bindTo:pairs() do
        if str:isStartingWith( k, oldPrefix ) then
            local propName = k:sub( pos )
            local newPropKey = newPrefix .. propName
            dbg( "copying setting: ", str:format( "prop-name: ^1, val: ^2, new prop-key: ^3", propName, str:to( v ), newPropKey ) )
            bindTo[newPropKey] = v
        else
            dbg( "not moving: ", k )
        end
    end
end
--]]



--  Note: it may pay to have a get-enable-binding which is can accept a raw key array, or formatted key without the array index,
--  Ditto for value binding (to be able to create intelligent value bindings... - iow: to be able to traverse the spec tree for the binding, or something like that.?###2
--  e.g. something that takes actual array selection (index) into account. - haven't thought this through...



--  Get UI binding object corresponding to spec, given it's parent key and property table.
--  Sortofa glorified call to LrView.bind (granted, child key must be computed) and care to map array binding to selected name instead of..
function Settings:_getValueBinding( spec, parentKey, bindTo )
    app:callingAssert( parentKey, "no parent key" )
    
    if spec.id == nil then
        return
    end
    
    local itemKey = parentKey .. "__" .. spec.id
    if spec.dataType == 'array' then
        if spec.viewType == 'multiList' then
            itemKey = itemKey .. "_list"
        elseif spec.viewType == 'popup' then
            itemKey = itemKey .. "_sel"
        else
            -- item-key as-is.
        end
    end
    -- a tidbit just for debugging:
    local tb
    if bindTo == prefs then
        tb = "prefs"
    else
        tb = "props"
    end
    --Debug.logn( spec.id, "binding to", tb, itemKey )
    local value = bindTo[itemKey]
    local binding = bind( itemKey )
    --Debug.lognpp( "current value", value )
    return binding, itemKey
end



--  Get a popup menu corresponding to array spec, properly bound to prefs, with maintenance choices.
--  @29/Dec/2012 19:56, only used for arrays, none of which are s t a t i c ( s t a t i c popups are only used for proxy data type).
function Settings:_getPopupMenu( spec, parentKey, bindTo, call )
    app:callingAssert( parentKey, "no parent key" )
    local itemKey = parentKey .. "__" .. spec.id
    local namesKey = itemKey .. "_names"
    local selKey = itemKey .. "_sel"
    --local props = app:callingAssert( call.props, "no props" )
    local props = LrBinding.makePropertyTable( call.context ) -- new props for each popup.
    props.items = {}
    local items = {} -- popup items
    local names = {} -- names of items.

    --Debug.lognpp( "Getting array view", itemKey )
    
    local helpMsg
    if spec.helpMsg == nil then
        local p = {} -- paragraphs
        p[#p + 1] = "This popup allows you to choose a different (named) set of options, or manage these sets of options:"
        p[#p + 1] = "The upper choices are for the former (choose item), the lower choices are for the latter (item management):"
        if not spec.static then
            p[#p + 1] = "* New: Create a new item - initial option values will be the factory defaults."
            --p[#p + 1] = "* Duplicate: Same as 'New', except settings will be same as selected (duplicated) preset."
            p[#p + 1] = "* Rename: Rename the presently selected item."
            p[#p + 1] = "* Delete: Delete the presently selected item."
        end
        p[#p + 1] = "* Edit: Edit the presently selected item."
        p[#p + 1] = "* Reset: Load factory default values into presently selected item."
        
        helpMsg = table.concat( p, "\n\n" ) -- paragraph separator.
    else
        helpMsg = spec.helpMsg
    end
    
    local function updItems()
        items = {}
        names = bindTo[namesKey] or {}
        for i, name in ipairs( names ) do
            items[#items + 1] = { title=name, value=name }
        end
        -- @30/Dec/2012 10:44, popup only used for arrays
        items[#items + 1] = { separator=true }
        if not spec.static then
            items[#items + 1] = { title="New", value="__new__" }
            --items[#items + 1] = { title="Duplicate", value="__dup__" }
            items[#items + 1] = { title="Rename", value="__ren__" }
            items[#items + 1] = { title="Delete", value="__del__" }
        end
        items[#items + 1] = { title="Edit", value="__edit__" }
        items[#items + 1] = { title="Reset", value="__defaults__" }
        items[#items + 1] = { title="Help", value="__help__" }
        props.items = items
        local sel
        for i, name in ipairs( names ) do
            if name == bindTo[selKey] then
                sel = name
                break
            end
        end
        if sel then
            props.sel = sel
        else
            props.sel = names[1]
            bindTo[selKey] = sel
        end
    end
    
    local function isDup( name )
        if str:isEqualIgnoringCase( name, 'Default' ) then
            return true
        end
        for i, v in ipairs( items ) do
            if v.value ~= nil and str:isEqualIgnoringCase( v.value, name ) then -- assures user can't create preset named '__new__' and such, too.
                return true
            end
        end
        return false    
    end

    updItems() -- create items and assign to props.

    local vw
    vw = vf:popup_menu( tab:mergeSets( spec.viewOptions, {
        bind_to_object = props, -- note: binding is not to the bind-to object, since temp props are used to 
        value = bind 'sel',
        items = bind 'items',
    }))
    
    local function record( v )
        props.sel = v               -- ###2 similar code for Preferences class changed to nix this line, and instead call updItems - avoids weirdness...
        bindTo[selKey] = v -- will trigger a change in external observer, which may be problematic, if external observer makes change that triggers ch below.
    end
    
    local function ch( id, props, name, value )
    
        app:call( Call:new{ name=str:fmtx( "getPresetPopupChangeHandler_^1", spec.id ), async=true, guard=App.guardSilent, main=function( call ) -- calls may be nested.
            -- but editing a new preset backing file isn't working unless async is true.

            if name == 'sel' then
                if value == "__new__" then
                    local oldName = bindTo[selKey]
                    local newName = dia:getSimpleTextInput{
                        title="New Preset",
                        subtitle = "Enter new preset name:",
                        width_in_chars = 20,
                    }
                    if str:is( newName ) then
                        if not isDup( newName ) then
                            
                            names[#names + 1] = newName
                            bindTo[namesKey] = names
                            
                            app:show{ info="new: ^1", newName,
                                actionPrefKey = "new preset confirmation",
                            }
                            
                            record( newName )
                            updItems() -- sets props.sel. props.value only needs to be set when change to preset selection is asynchronous/external.
                            
                            local viewItems, viewLookup = systemSettings:getViewItems { -- does non-forced init by default.
                                dataDescr = spec.elem,
                                bindTo = bindTo,
                                key = itemKey,
                                call = call,
                                --init = false, - init above is no longer necessary.
                                options = { index=#names },
                            }
                            
                            if viewItems then
                                app:show{ info=newName,
                                    viewItems = viewItems
                                }
                            else
                                app:show{ warning="no items" }
                            end
                            
                        else
                            app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                            props.sel = oldName
                        end
                    else
                        props.sel = oldName
                    end
                --[[ *** save for possible future resurrection - not ready for prime time...
                elseif value == "__dup__" then
                    local oldName = bindTo[selKey]
                    if names ~= nil and #names > 0 then
                        local newName = dia:getSimpleTextInput{
                            title="Duplicate Preset",
                            subtitle = "Enter new name:",
                            width_in_chars = 20,
                        }
                        if str:is( newName ) then
                            if not isDup( newName ) then
                                
                                local index
                                for i, v in ipairs( names ) do
                                    if oldName == v then
                                        index = i
                                        break
                                    end
                                end
                                
                                if index then
    
                                    self:_copySettings( bindTo, itemKey, oldName, newName ) 
    
                                    names[#names + 1] = newName
                                    bindTo[namesKey] = names
    
                                    record( newName )
                                    updItems()
                                else
                                    Debug.pause( "no preset to duplicate" )
                                    props.sel = oldName
                                end
                                
                                app:show{ info="'^1' duplicated to '^2'", oldName, newName,
                                    actionPrefKey = "Preset duplicated",
                                }
                                
                            else
                                app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                                props.sel = oldName
                            end
                        else
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="nothing to duplicate" }
                        props.sel = oldName
                    end
                --]]
                elseif value == "__ren__" then
                    local oldName = bindTo[selKey]
                    if names ~= nil and #names > 0 then
                        local newName = dia:getSimpleTextInput{
                            title="Rename Preset",
                            subtitle = "Enter new name:",
                            width_in_chars = 20,
                        }
                        if str:is( newName ) then
                            if not isDup( newName ) then
                                
                                local index
                                for i, v in ipairs( names ) do
                                    if oldName == v then
                                        index = i
                                        break
                                    end
                                end
                                
                                if index then
    
                                    names[index] = newName
                                    bindTo[namesKey] = names
    
                                    record( newName )
                                    updItems()
                                else
                                    Debug.pause( "no preset to rename" )
                                    props.sel = oldName
                                end
                                
                                app:show{ info="'^1' renamed to '^2'", oldName, newName,
                                    actionPrefKey = "rename preset confirmation",
                                }
                                
                            else
                                app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                                props.sel = oldName
                            end
                        else
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="nothing to rename" }
                        props.sel = oldName
                    end
                elseif value == "__del__" then
                
                    local oldName = bindTo[selKey]
                    if not str:is( oldName ) then
                        Debug.pause( names )
                        updItems() -- ###4 - this is probably not needed anymore since code fixed to assure items are correct, but is cheap insurance...
                        oldName = bindTo[selKey]
                    end
                    if names ~= nil and #names > 0 then
                    
                        local button = app:show{ confirm="Delete: ^1?", oldName }
                        if button == 'cancel' then
                            props.sel = oldName
                            return
                        end
                        
                        local index
                        for i, v in ipairs( names ) do
                            if oldName == v then
                                index = i
                                break
                            end
                        end
                        
                        if index then
                        
                            table.remove( names, index )
                            --bindTo[itemKey .. "_count"] = #names
                            bindTo[namesKey] = names
                        
                            local name = names[1]
                            if str:is( name ) then
                                record( name )
                            end
                            updItems()
                        else
                            app:show{ warning="no preset to delete" }
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="nothing to delete" }
                        props.sel = oldName
                    end
                    
                elseif value == "__edit__" then
                
                    local presetName = bindTo[selKey]
                    local index
                    for i, v in ipairs( names ) do
                        if v == presetName then
                            index = i
                            break
                        end
                    end
                    if index then
                    
            	        --Debug.pause("index")
                        local viewItems, viewLookup = systemSettings:getViewItems { -- does non-forced init by default.
                            dataDescr = spec.elem,
                            bindTo = bindTo,
                            key = itemKey,
                            --init = false, - init above is no longer necessary.
                            call = call,
                            options = { index=index }
                        }
                        if viewItems then
                            app:show{ info="Editing '^1' preset: ^2", spec.friendly, presetName,
                                viewItems = viewItems
                            }
                        else
                            app:show{ warning="no items" }
                        end
                    else
                        app:show{ warning = "No preset to edit." }
                    end
                    props.sel = presetName
                    
                elseif value == "__defaults__" then
                
                    local presetName = bindTo[selKey]
                    if dialog:isOk( str:fmt( "Overwrite ^1 settings with factory defaults?", presetName ) ) then
        	            --self:loadDefaults( params.props, presetName )
        	            systemSettings:init {
        	                key = parentKey,
        	                items = { spec },
        	                bindTo = bindTo,
        	                forceInit = true,
        	            }
        	            app:show{ info="Defaults were successfully loaded.", actionPrefKey="default settings loaded" }
        	        end
                    props.sel = presetName
                    
                elseif value == "__help__" then
                
                    local presetName = bindTo[selKey]
                    app:show{ info=helpMsg }
                    props.sel = presetName
                    
                else -- existing preset selected from menu.
                
                    record( value )
                    
                end
                
            --elseif name == valueKey then -- bound value has changed, maybe externally
            
           --     Debug.pause()
            --    record( value )
              --  updItems()
                
            else
                Debug.pause( name, value )
            end
        end } )
    end
    
    view:setObserver( props, 'sel', Settings, ch ) -- assure selection changes propagate to targets.
    --view:setObserver( valueBindTo, valueKey, Settings, ch ) -- target preset name change propagates to selection.
    return vw
    
end



-- get view item (row containing popup-menu) corresponding to array data-type.
function Settings:_getPopupView( spec, parentKey, bindTo, call ) 
    app:callingAssert( parentKey, "no parent key" )
    local itemKey = parentKey .. "__" .. spec.id
    local label = vf:static_text {
        title = spec.friendly,
        width = share 'label_width',
    }
    local popup = self:_getPopupMenu( spec, parentKey, bindTo, call )
    local qual
    if spec.whole then
        qual = vf:static_text{ title="(whole set)", tooltip="Selection does not matter - the whole set is what matters." }
    else
        qual = nil -- vf:static_text{ title="(as selected)", tooltip="Presently selected item is what matters." }
    end
    if popup then
        return vf:row{ label, popup, qual }
    else
        return nil
    end
end


function Settings:_getListView( spec, parentKey, bindTo, call )
    app:callingAssert( parentKey, "no parent key" )
    local label = vf:static_text {
        title = spec.friendly,
        width = share 'label_width',
    }
    local list
    local binding, itemKey = self:_getValueBinding( spec, parentKey, bindTo )
    --Debug.lognpp( binding, itemKey )
    Debug.pause(  "binding to item", itemKey )
    assert( spec.viewOptions, "no view options" )
    assert( spec.viewOptions.items, "no items" )
    --local function comparator( v1, v2 )
    --    Debug.pause( "c" )
    --    return true
    --end
    local viewData = tab:mergeSets( { bind_to_object=bindTo, value=binding, allows_multiple_selection=true }, spec.viewOptions )
    --Debug.lognpp( "viewData", viewData )
    assert( viewData.items, "no items 2" )
    local list = vf:simple_list( viewData )
    return vf:row{ label, list }
end




--  internal/private method for getting value at specified key, from specified propertyTable.
--  note: corresponding item must have been previously initialized, and hence available for lookup based on key.
--  note2: key must be in ready-to-use format, e.g. __settings__mysetting.
--  @return value (any, required) typed and formatted value.
--  @return rawValue (any, required) raw value, as stored in property table.
function Settings:_getValue( itemKey, bindTo, options )

    app:callingAssert( itemKey, "no itemKey" )
    app:callingAssert( bindTo, "no bind-to" )
    
    local spec = self.lookup[itemKey]
    app:assert( spec, "no spec for '^1'", itemKey )

    --Debug.logn( str:fmtx( "getting value for spec id '^1' using key '^2'", spec.id, itemKey ) )
    
    local value, rawValue, other
    rawValue = bindTo[itemKey] -- default: may be overridden.
    repeat
        if spec.dataType == 'proxy' then -- at the moment, proxies are s t a t i c, and arrays are dynamic.
            local initr = tab:getTable( spec.init ) -- or app:error( "proxy initializer must have init table, '^1' doesn't", spec.id )
            if initr == nil then
                initr = (spec.viewOptions or {}).items
            end
            local val = bindTo[itemKey] -- in case of proxy, bound value is name not true value.
            local defaultValue
            local defaultFound
            if val ~= nil then -- somethin not nil in prefs/props.
                -- check for recorded title in init table, if present, that must be it.
                for i, v in ipairs( initr ) do
                    if val == v.title then
                        value = v.value
                        --Debug.pause( "value", sel )
                        break
                    elseif v.default then
                        defaultValue = v.value -- may be nil.
                        defaultFound = true
                        --Debug.pause( "not", sel, v )
                    end
                end
            end
            if value ~= nil then
                -- got value
            else
                --Debug.logn( "no proxy value - assuming default", spec.id )
                if defaultFound then -- default from init-table has priority.
                    value = defaultValue -- even if nil
                else
                    if spec.default ~= nil then
                        value = spec.default -- may be nil.
                        app:logWarning( "default should come from init/item table, not spec proper." )
                        Debug.pause( "default not specified in table, but is specified in item header - this is deprecated." )
                    end
                end
            end
        elseif spec.dataType == 'function' then
            if str:is( rawValue ) then
                local func, err = loadstring( rawValue, spec.id ) -- returns nil, errm if any troubles: no need for pcall (short chunkname required for debug).
                if func then
                    value = func
                else
                    --Debug.pause()
                    rawValue = "function() end "
                    value = function() end
                end
            else
                rawValue = "function() end "
                value = function() end
            end
        elseif spec.dataType == 'array' then
            --Debug.pause( "array", itemKey )
            if spec.viewType == 'multiList' then
                rawValue = bindTo[itemKey.."_list"] -- names
                local viewOptions = tab:getTable( spec.viewOptions ) or {}
                local items = tab:getTable( viewOptions.items ) or {}
                if #items == 0 then
                    value = {} -- regardless of persistent names, if there are no items, there is no value.
                    break
                end
                local rawLookup = tab:createSet( rawValue )
                value = {}
                -- assure all selections are still present.
                for i, v in ipairs( items ) do
                    if rawLookup[v.title] then
                        value[#value + 1] = v.title
                    end
                end
            elseif spec.viewType == 'devPresetChooser' or spec.viewType == 'metaPresetChooser' then
                rawValue = bindTo[itemKey] or ""
                value = str:split( rawValue, "\n" ) -- split trims \r.
            elseif spec.viewType == 'devSettingsEditor' or spec.viewType == 'devSettingsChooser' then -- presently not needing anything special here, but gives opportunity for debug...
                rawValue = bindTo[itemKey] -- ..'_ids']
                value = rawValue -- ###2 -- @12/Aug/2013 17:22, not sure what the issue was here.
                --Debug.pause( "_getValue", itemKey, rawValue, value )
            elseif spec.viewType == 'keywordChooser' then -- kwc nyi ###3
                rawValue = bindTo[itemKey] or ""
                value = str:split( rawValue, "," ) -- split trims \r.
            elseif spec.viewType == 'popup' then
                value = {}
                rawValue = {}
                local namesKey = itemKey .. '_names'
                options = options or {}
                local whole = options.whole
                if whole == nil then
                    whole = spec.whole
                end
                local names = tab:getTable( bindTo[namesKey], "names array" ) or {}
                local sel
                if options.name then
                    sel = options.name
                    whole = false
                elseif options.index then
                    whole = false
                elseif not whole then
                    sel = bindTo[itemKey .. '_sel'] or error( "no sel" )                
                end
                for index = 1, #names do
                    local name = names[index] or error( "no name" )
                    if whole or index == options.index or name == sel then
                        local elem = {}
                        local raw = {}
                        assert( spec.elem, "no elem" )
                        for i, it in ipairs( spec.elem ) do
                            repeat
                                if it.id == nil then break end -- e.g. spacer/separator.
                                
                                local k = itemKey .. "_" .. index .. "__" .. it.id
                                --Debug.logn( "Considering getting array element, spec", k, it.whole )
                                local _v, _rv = self:_getValue( k, bindTo, { whole=it.whole } ) -- get bound value from prefs.
                                --Debug.logn( str:fmtx( "Got array elem member [^1].^2 = ^3", index, it.id, str:to( _v ) ) )
                                
                                elem[it.id] = _v
                                raw[it.id] = _rv
                            until true
                        end
                        other = index
                        if not whole then
                            value = elem
                            rawValue = raw
                            break
                        else
                            value[#value + 1] = elem
                            rawValue[#rawValue + 1] = raw
                        end
                    else
                        --Debug.pause( "not sel name (and not getting whole)", name )
                    end
                end
            else
                app:error( "Unable to get array value due to unrecognized view type: ^1", spec.viewType )
            end -- not multi-list
        else
            --Debug.pause( "getting settings, data type:", spec.dataType )
            value = rawValue
        end
    until true
    -- Debug.lognpp( "got value?", value ) - value can be big and frequently gotten - do not overrun debug logger.
    -- note: so far, other is reserved for array selection index.
    return value, rawValue, other

end



--- Get value of setting specified by key, in bind-to property table (could be prefs or ad-hoc props)
--
--  @param      key (table or string, required) array or dot-notation specifying data value in property table.
--  @param      bindTo (property table, default=prefs) property table.
--  @param      options (table, optional) e.g. 'whole' for whole array, instead of array element.
--
--  @usage      depends on item having been pre-initialized, since item data descriptor must be consulted to format value.
--  @usage      *** throws error if key not registered. this way one can make distinction between value is nil, and value is invalid.
--
--  @return     value (any, required) typed/formated value.
--  @return     rawValue (string, number, boolean; required) raw value as read from property table.
--
function Settings:getValue( key, bindTo, options )
    bindTo = bindTo or prefs
    if self:isKeyRelative( key ) then
        key = self:getKey( key ) -- translate to absolute format, conditioned (prefixed) by currently selected preset name.
    end
    --Debug.logn( "public getting", key )
    --return self:_getValue( key, bindTo, options ) - throws error.
    --Debug.pause( "Getting", key )
    local s, _value = pcall( self._getValue, self, key, bindTo, options )
    if s then
        return _value
    else
        -- dbg..
        return nil
    end
end



function Settings:_write( key, bindTo, val, spec, tb )
    Debug.logn( "Writing", tb, "key:", key, "value:", val )
    bindTo[key] = val
    self.lookup[key] = spec
end


-- Not called unless current value is nil or we're opting for forced initialization.
-- Thus, we are after the default value unconditionally at this point.

-- initVal is *value* (not title) from init (not item) table
-- Note: the whole purpose of the init-val was so all items would not have to be gone through for each elem, no?

function Settings:_initDefault( itemKey, bindTo, spec, initVal )
    if spec.dataType == 'proxy' then
        -- reminder: in case of proxy, bound value is name, not true value.
        local name
        local items = spec.init
        if items then
            -- good: proxy's should have initializers, not view-options--items 
        elseif spec.viewOptions and spec.viewOptions.items then
            app:error( "Use init for proxied data types, not items array in view-options." )
        end
        local defaultFound
        if items then
            for i, v in ipairs( items ) do
                if v.default then -- found default initializer
                    name = v.title -- bound proxy value is name, not true value.
                    defaultFound = true
                    break
                end
            end
            if not name then
                Debug.pause( "no name" )
            end
        else
            --app:logWarning( "proxy sans items for init, key: '^1'", itemKey )                    
            app:error( "proxied item must have init array" ) -- this would happen anyway below, since name would be nil: may as well be clear - no point in having proxied data that can't be initialized!?
        end
        if name == nil then
            if defaultFound then
                app:error( "Proxy default title must not be nil (proxy value can be nil)." )
            else
                app:error( "Unable to determmine which item/initializer is defined as default - consider reviewing settings file..." )
            end
        end
        self:_write( itemKey, bindTo, name, spec, 'proxy default' )
    else -- not proxy data-type
    
        if initVal == nil then
        
            --Debug.pause( spec.dataType )

            local items = (spec.viewOptions or {}).items
            if items then
            else
                items = spec.init -- or error( "no items" ) -- no reason to have it defined if no items, may as well just hardcode. On the other hand, may be worthwhile for setting stage for future.
            end
            local defaultFound
            if items then
                for i, v in ipairs( items ) do
                    if v.default then -- found default initializer
                        initVal = v.value -- could be nil
                        --Debug.pause( "name", name )
                        defaultFound = true
                        break
                    end
                end
                if not defaultFound then
                    Debug.pause( "no default" )
                end
            else
                -- app:logv( "*** proxy sans items for init: ^1", itemKey ) - not illegal: happens all the time.
            end
            
            if not defaultFound then
                initVal = spec.default -- e.g.   s t a t i c   string..
                --Debug.logn( "non-nil default not found via explicit initializer for", spec.id, "new initVal governed by spec default value", initVal )
            end
        end
        if initVal ~= nil then
            local typ = type( initVal )
            if prefTypeReg[typ] then
                --Debug.pause( "init val", initVal )
                self:_write( itemKey, bindTo, initVal, spec, str:fmtx( "^1 default", typ ) )
            else
                app:error( "Type not supported in prefs: '^1'", typ )
            end
        elseif spec.viewType == 'popup' then -- gone @21/Dec/2012 - needs more testing. @8/Jan/2013 - not sure what I meant by that statement, but:
            -- this case is not presently happening, i.e. all popups are either proxy, or an init-val has been obtained at this point.
            -- this clause is being left in, to see if this case ever pops up again, so to speak.
            --Debug.pause( spec.id, spec.dataType )
            local initr = spec.init or (spec.viewOptions or {}).items
            app:assert( initr, "no init: ^1", spec.id )
            local defaultFound
            local sel
            for i, v in ipairs( initr ) do
                if v.default then
                    --sel = v.title
                    --Debug.pause( v.title, v.value )
                    sel = v.value
                    defaultFound = true
                    break
                end
            end
            if defaultFound then
                --Debug.pause( "default saved as name", spec.id, sel )
            else
                --Debug.pause( "no default", spec.id )
            end
            if not sel then
                sel = ""
            end
            self:_write( itemKey, bindTo, sel, spec, "popup sel name default" )
        else
            self:_write( itemKey, bindTo, nil, spec, "nil default" )
            --Debug.logn( "no default (or nil) for", itemKey, spec.id, spec.dataType ) -- nil default is perfectly acceptable.
        end
    end
    Debug.logn( "Recording default lookup", itemKey, spec.id )
    --assert( self.lookup[itemKey] == spec, "spec not recorded" )
    self.lookup[itemKey] = spec -- ###4 redundent?
end



--- Initialize spec data in bind-to object at root key, and initialize lookup for future reference.
function Settings:_init( _parentKey, _items, bindTo, force )
    bindTo = bindTo or prefs
    --   I N I T
    -- init one item, given the corresponding item key - called recursively.
    local function initItem( itemKey, item, initVal )
        if item.id == nil then -- e.g. spacer/separator.
            return
        end
    
        Debug.logn()
        Debug.logn( "init-item", itemKey, item.id, item.dataType, item.default )
        
        if item.dataType == 'array' then
            Debug.logn( "recording array's root lookup", itemKey, item.id )
            self.lookup[itemKey] = item
            if item.viewType == 'multiList' then
                repeat
                    local initr = tab:getTable( item.init ) or {}
                    if #initr == 0 then
                        self:_write( itemKey.."_list", bindTo, {}, item, 'empty multi-list array' )
                        break -- no initializer means no initial selection.
                    end
                    local initSet = tab:createSet( initr )
                    Debug.lognpp( initSet )
                    -- note: items for multi-list are being auto-treated as proxy: not backed by prefs. ###2
                    local viewOptions = tab:getTable( item.viewOptions ) or error( "Unable to find view options (to contain list items)" )
                    local items = tab:getTable( viewOptions.items ) or error( "Unable to find items in view options" )
                    local list = bindTo[itemKey .. "_list"] -- unlike normal (popup) array, multi-list array stores an array of selections - making it completely independent of other array view-types
                    if list == nil or force then
                        local names = {}
                        for i, v in ipairs( items ) do
                            Debug.logn( v.title )
                            if initSet[v.title] then
                                names[#names + 1] = v.title
                            end
                        end
                        if #names == 0 then
                            Debug.pause( "init turned up no selections - motoring on without..." )
                            --break - remove after initial debug ###
                        end
                        self:_write( itemKey.."_list", bindTo, names, item, 'multi-list array' )
                    else
                        Debug.lognpp( "Already init multi-list array", list )
                    end
                until true
            elseif item.viewType == 'devPresetChooser' or item.viewType == 'metaPresetChooser' or item.viewType == 'keywordChooser' or item.viewType == 'devSettingsEditor' or item.viewType == 'devSettingsChooser' then
                if force then
                    bindTo[itemKey] = item.default -- conceivable default could come from init-val, but so far: not.
                    --Debug.pause( "set to dflt" )
                else
                    --Debug.pause( "already init and not forcing" )
                end
            elseif item.viewType == 'popup' then            
                --Debug.pause( "init array", parentKey, spec.id )
                local initTable = tab:getTable( item.init, "init table" ) or {}
                --Debug.pause( "init elements for", item.id, #initTable )
                local namesKey = itemKey .. "_names"
                local initCount
                local names
                local selName
                if force then
                    selName = nil
                    names = {}
                    initCount = #initTable
                else
                    selName = bindTo[itemKey .. "_sel"]
                    names = tab:getTable( bindTo[namesKey] ) -- @9/Jan/2013 3:45 nil-for names indicates un-init. - used to be 'or {}' - delete comment if OK come 2014. ###4
                    --Debug.pauseIf( item.id=='backups', "names for", item.id, #names, names )
                    if names ~= nil then
                        initCount = math.max( #names, #initTable )
                    else
                        initCount = #initTable
                    end
                end
                --Debug.pauseIf( item.id=="importCustomSets", initCount, names )
                local newNames = {}
                
                for index = 1, initCount do -- array count is number existing (not forced), or number to initialize based on init, if force-init.
                    -- this is initializing one structured element of the array:
                    local name
                    local initElem = tab:getTable( initTable[index], "init element" )
                    if names and names[index] then -- not force init.
                        name = str:getString( names[index] ) -- assure string or nil (reminder, source is prefs or pgm, not user - so don't throw error if bad type).
                        --Debug.pauseIf( item.id=="importCustomSets", "name from array at index", name, index )
                    elseif force or names == nil or index <= #names then -- force init or not already init. ###4 if names == 0 is sufficient condition, then there is no way to eliminate all backups. Hmm...
                        --Debug.pause( "fi or nai", #initTable )
                        if initElem then
                            name = str:getString( initElem.title, "init name" ) -- throw error if bad type.
                            --Debug.pauseIf( item.id=="backups", "init name", name, initElem.values )
                            if bool:getAsBoolean( initElem.default ) then
                                if not selName then
                                    selName = name
                                else
                                    Debug.pause( "Too many defaults, only first has effect." )
                                end
                            else
                                assert( initElem.values, "no values" )
                            end
                        else
                            Debug.pause( "no init elem for", item.id, index ) -- ###2 - could be considered an error, but errors are not being handled upon startup how I'd like.
                        end
                    -- else
                    end
                    if str:is( name ) then -- initialize array elements corresponding to name, if such name exists.
                        --Debug.pauseIf( item.id=="importCustomSets", "name is", name )
                        newNames[#newNames + 1] = name
                        assert( item.elem, "no item.elem" )
                        for i, v in ipairs( item.elem ) do
                            repeat
                                if v.id == nil then break end -- e.g. spacer/separator
                                local k = itemKey .. "_" .. index .. "__" .. v.id
                                local val = ((initElem or {}).values or {})[v.id]
                                --Debug.pause( "init array elem", k, v.id, val )
                                initItem( k, v, val )
                            until true
                        end
                    else
                        --Debug.pauseIf( item.id=="importCustomSets",  "no mo" )
                        break -- do not initialize - probably should actually clear them, so they are not dangling.
                    end
                end
                -- ok to re-initialize to same value?
                bindTo[itemKey .. "_names"] = newNames
                --bindTo[itemKey .. "_count"] = #newNames
                if selName then
                    bindTo[itemKey .. "_sel"] = selName
                else
                    bindTo[itemKey .. "_sel"] = newNames[1]
                end
            else
                app:error( "Unable to initialize data item due to unrecocgnized view type: ^1", item.viewType )
            end
        elseif dataTypeReg[item.dataType] then -- registered data type.
            if bindTo[itemKey] == nil or force then
                self:_initDefault( itemKey, bindTo, item, initVal )
            else
                dbgf( "Already init, key: ^1, value: ^2", itemKey, bindTo[itemKey] )
            end
            Debug.logn( "lookup sub spec", itemKey, item.id )
            if item.dataType =='proxy' and (item.viewOptions or {}).tooltip == nil then
                --Debug.pause( "default proxy tooltip", itemKey )
                if not item.viewOptions then
                    item.viewOptions = {}
                end
                item.viewOptions.tooltip = "To define more options, or modify existing options, return to plugin manager and click the 'Define Additional Settings' button."
            end
            self.lookup[itemKey] = item
        else
            app:error( "Unsupported data type: ^1", item.dataType )
        end
        --init( itemKey, spec )
        --Debug.logn( "lookup main spec", itemKey, spec.id )
        --self.lookup[itemKey] = spec -- spec key is unique for every setting.
        --[[ *** save for future, maybe:
        if #item > 0 then
            Debug.pause() -- not happening now - reserved for future.
            if str:is( item.groupName ) then
                initItems( itemKey .. "__" .. item.groupName, item )
            else
                initItems( itemKey, item )
            end
        end
        --]]
    end
    -- init-items
    local function initItems( parentKey, items )
        --Debug.pause( whatev, parent )
        assert( items, "no items" )
        for i, v in ipairs( items ) do
            if v.id then
                initItem( parentKey .. "__" .. v.id, v ) -- init-val = nil.
            end
        end
    end
    initItems( _parentKey, _items )
end



function Settings:init( params )
    local parentKey = params.key
    return self:_init(
        parentKey,
        params.items or app:callingError( "no items" ),
        params.bindTo or app:callingError( "no bind-to" ),
        params.forceInit -- default is false.
    )
end


-- could conceivably be common function, except that for purposes of this module,
-- values are names, same as titles.
local function getDevPresetItems()
    local names = {}
    local folders = LrApplication.developPresetFolders()
    -- 
    for i, folder in ipairs( folders ) do
        local presets = folder:getDevelopPresets()
        --
        for i,v in ipairs( presets ) do
            names[#names + 1] = { title=v:getName(), value=v:getName() }
        end
        names[#names + 1] = { separator=true }
    end
    names[#names] = nil
    return names
end
-- ditto
local function getMetaPresetItems()
    local t = LrApplication.metadataPresets()
    local items = {}
    for k, v in pairs( t ) do
        items[#items + 1] = { title=k, value=k }
    end
    return items
end


function Settings:_initPref( key, dflt )
    if prefs[key] == nil then
        prefs[key] = dflt
    end
end


function Settings:_dngOptionsView( itemKey, bindTo, spec )
    local enableKey = str:fmt( "^1_^2", itemKey, "enable" )
    local dngKey = str:fmt( "^1_^2", itemKey, "dng" )
    local crKey = str:fmt( "^1_^2", itemKey, "cr" )
    local lossiKey = str:fmt( "^1_^2", itemKey, "lossi" ) -- -lossy -side -count or ''.
    local amountKey = str:fmt( "^1_^2", itemKey, "amount" ) -- -side -count amount.
    local previewKey = str:fmt( "^1_^2", itemKey, "preview" )
    local uncompKey = str:fmt( "^1_^2", itemKey, "uncomp" )
    local embedKey = str:fmt( "^1_^2", itemKey, "embed" )
    local linearKey = str:fmt( "^1_^2", itemKey, "linear" )
    local fastLoadKey = str:fmt( "^1_^2", itemKey, "fastLoad" )
    self:_initPref( enableKey, false )
    self:_initPref( dngKey, "-dng1.4" )
    self:_initPref( crKey, "-cr7.1" )
    self:_initPref( lossiKey, "" ) -- lossless
    self:_initPref( amountKey, "2000" )
    self:_initPref( previewKey, "-p0" )
    self:_initPref( uncompKey, "" )
    self:_initPref( embedKey, "" )
    self:_initPref( linearKey, "" )
    self:_initPref( fastLoadKey, "" )
    local enableBinding = bind( enableKey )
        
    local vi = {}
    vi[#vi + 1] = vf:checkbox {
        bind_to_object = prefs,
        title = "Let plugin decide",
        value = LrBinding.negativeOfKey( enableKey ),
    }
    vi[#vi + 1] = vf:spacer{ height = 20 }
    vi[#vi + 1] = vf:row{
        vf:static_text {
            title = "DNG Version",
            width=share 'label_width',
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( dngKey ),
            title = "Omit",
            checked_value = "",
            width=share 'd_width_1',
            tooltip = "I *think* \"latest DNG version\" is implied when DNG version is omitted, but I'm not sure - if you know, please do tell me so I/we can have a better tooltip here - thanks.",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( dngKey ),
            title = "1.1",
            checked_value = "-dng1.1",
            width=share 'd_width_2',
            tooltip = "Legacy DNG version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( dngKey ),
            title = "1.3",
            checked_value = "-dng1.3",
            width=share 'd_width_3',
            tooltip = "Legacy DNG version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( dngKey ),
            title = "1.4",
            checked_value = "-dng1.4",
            width=share 'd_width_4',
            tooltip = "Current DNG version - this is a safe choice unless legacy compatibility is required.",
            enabled = enableBinding,
        },
    }
    vi[#vi + 1] = vf:spacer{ height = 3 }
    vi[#vi + 1] = vf:row{
        vf:static_text {
            title = "ACR Version",
            width=share 'label_width',
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "2.4",
            checked_value = "-cr2.4",
            width=share 'd_width_1',
            tooltip = "Legacy ACR version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "4.1",
            checked_value = "-cr4.1",
            width=share 'd_width_2',
            tooltip = "Legacy ACR version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "4.6",
            checked_value = "-cr4.6",
            width=share 'd_width_3',
            tooltip = "Legacy ACR version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "5.4",
            checked_value = "-cr5.4",
            width=share 'd_width_4',
            tooltip = "Legacy ACR version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "6.6",
            checked_value = "-cr6.6",
            width=share 'd_width_4',
            tooltip = "Legacy ACR version - only select if necessary for legacy compatibility",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( crKey ),
            title = "7.1",
            checked_value = "-cr7.1",
            width=share 'd_width_5',
            tooltip = "Current ACR version - this is the correct choice unless legacy compatibility is required.",
            enabled = enableBinding,
        },
    }
    vi[#vi + 1] = vf:spacer{ height = 15 }
    vi[#vi + 1] = vf:row{
        vf:static_text {
            title = "Lossy Compression?",
            width=share 'label_width',
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( lossiKey ),
            title = "Lossless!",
            checked_value = "",
            width = share 'd2_width_1',
            tooltip = "Compression will incur no data loss (no quality loss) - this is the correct choice unless you know better...",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( lossiKey ),
            title = "Full-size",
            checked_value = "-lossy",
            width = share 'd2_width_2',
            tooltip = "Lossy (jpeg) compression - no image size reduction",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( lossiKey ),
            title = "Long Edge",
            checked_value = "-side",
            width = share 'd2_width_3',
            tooltip = "Lossy (jpeg) compression - image size reduction based on long edge dimension.",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( lossiKey ),
            title = "Pixel Count",
            checked_value = "-count",
            width = share 'd2_width_4',
            tooltip = "Lossy (jpeg) compression - image size reduction based on total pixel count.",
            enabled = enableBinding,
        },
        vf:edit_field {
            tooltip = "'Long Edge' - dimension in pixels of longest edge; 'Pixel Count' - width x height in pixels.",
            bind_to_object = prefs,
            value = bind( amountKey ),
            enabled = bind {
                keys={ lossiKey, enableKey },
                operation = function( one, two )
                    return prefs[enableKey] and ( prefs[lossiKey] == "-side" or prefs[lossiKey] == "-count" )
                end,
            },
            width_in_digits = 6,
            precision=0,
            min=16,
            max=999999,
        },
    }
    vi[#vi + 1] = vf:row{
        vf:static_text {
            title = "Initial Jpeg Preview",
            width=share 'label_width',
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( previewKey ),
            title = "None",
            checked_value = "-p0",
            width=share 'd2_width_1',
            tooltip = "There will be no embedded preview initially, but if you save a preview in Lightroom, size will be governed by Lr preference.",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( previewKey ),
            title = "Medium",
            checked_value = "-p1", -- could be "", since it's the default
            width=share 'd2_width_2',
            tooltip = "There will be a medium-sized preview initially, but if you save a preview in Lightroom, size will be governed by Lr preference.",
            enabled = enableBinding,
        },
        vf:radio_button {
            bind_to_object = prefs,
            value = bind( previewKey ),
            title = "Large",
            checked_value = "-p2",
            width=share 'd2_width_3',
            tooltip = "There will be a large preview initially, but if you save a preview in Lightroom, size will be governed by Lr preference.",
            enabled = enableBinding,
        },
    }
    vi[#vi + 1] = vf:spacer{ height = 20 }
    vi[#vi + 1] = vf:row{
        vf:static_text {
            title = "Miscellaneous",
            width=share 'label_width',
        },
        vf:checkbox {
            bind_to_object = prefs,
            value = bind( uncompKey ),
            title = "Uncompressed",
            checked_value = "-u",
            unchecked_value = "",
            --width=share 'd2_width_1',
            tooltip = "In case you like bigger files... (not sure why you would want to forego compression)",
            enabled = enableBinding,
        },
        vf:checkbox {
            bind_to_object = prefs,
            value = bind( embedKey ),
            title = "Embed Original",
            checked_value = "-e",
            unchecked_value = "",
            --width=share 'd2_width_2',
            tooltip = "Embed the original (proprietary) raw in the DNG, for safe-keeping and possible future extraction.",
            enabled = enableBinding,
        },
        vf:checkbox {
            bind_to_object = prefs,
            value = bind( linearKey ),
            title = "Linear",
            checked_value = "-l",
            unchecked_value = "",
            --width=share 'd2_width_3',
            tooltip = "Convert from raw to \"tif\", then wrap - essentially",
            enabled = enableBinding,
        },
        vf:checkbox {
            bind_to_object = prefs,
            value = bind( fastLoadKey ),
            title = "Fast-load",
            checked_value = "-fl",
            unchecked_value = "",
            --width=share 'd2_width_4',
            tooltip = "Embed ACR cache info in DNG - there is very little value in this, that I can see, since non-embedded ACR cache info works just as well. Still, tiny savings the first time you go to edit after importing, since Ottomanic Importer does not support automatic 1:1 preview (+ ACR cache entry) generation.",
            enabled = enableBinding,
        },
    }
    local answer = app:show{ info="Choose DNG options",
        viewItems = vi,
    }
    if answer == 'ok' then
        local lossi = prefs[lossiKey]
        if str:is( lossi ) then
            if lossi ~= "-lossy" then
                lossi = lossi .. " " .. prefs[amountKey]
            end
        end
        local options 
        if prefs[enableKey] then
            local _options = {
                prefs[dngKey],
                prefs[crKey],
                lossi,
                prefs[previewKey],
                prefs[uncompKey],
                prefs[embedKey],
                prefs[linearKey],
                prefs[fastLoadKey],
            }
            options = str:consolidate( table.concat( _options, " " ) )
        else
            options = ""        
        end
        self:_write( itemKey, bindTo, options, spec, "dng options" ) -- should be redundent now, except for debug logn. Still, cheap insurance...
    end
end



--- Get develop settings view items, value key, and function for commiting values after view items presented to user.
--
--  @usage this is a special purpose function in case develop settings are to be included inline (instead of in response to event).
--
function Settings:getDevelopSettingsViewItems( parentKey, bindTo, viewType )
    local spec = { id='devSettings', dataType='array', viewType=viewType }
    local itemKey = parentKey .. "__" .. spec.id
    if self.lookup[itemKey] == nil then
        self.lookup[itemKey] = spec -- item must be self-registered if not already, since that piece is missing when doing in this "out-of-context" fashion.
    end
    local vi, writer = self:_devSettingsView( itemKey, bindTo, spec, true ) -- get not only the items, but the writer needed to translate form values into backing storage format.
    return vi, itemKey, writer
end



--- Present Develop settings "editor/chooser" view.
--
--  @usage presently only supports multi-item selection (checkboxes), but could be modified to support<br>
--         single item view (radio-buttons).
--  @usage not wrapped (so wrap in calling context as warranted).
--
function Settings:_devSettingsView( itemKey, bindTo, spec, returnViewItems )
    local vi = { height=900 }
    if spec.viewType == 'devSettingsEditor' then
        vi.width = 600
    else
        vi.width = 400
    end
    --Debug.pause( itemKey, spec.id )
    local pvKey = str:fmt( "^1_^2", itemKey, "pvConstraint" )
    
    local lookup = {}

    self:_initPref( pvKey, 'both' ) -- other options: 'pv2012', 'pvLegacy'. -- pref, necessarily? ###2
    vi[#vi + 1] = vf:row {
        vf:static_text {
            title = "Process Version Compatibility",
            --width=share 'label_width',
        },
        vf:radio_button {
            bind_to_object = prefs,
            title = "2012",
            checked_value = 'pv2012', -- could simplify to have this equal to applies-to pv-code. ###3
            value = bind( pvKey ),
        },
        vf:radio_button {
            bind_to_object = prefs,
            title = "Legacy",
            checked_value = 'pvLegacy', 
            value = bind( pvKey ),
        },
        vf:radio_button {
            bind_to_object = prefs,
            title = "Unrestricted",
            checked_value = 'both', 
            value = bind( pvKey ),
        },
    }
    vi[#vi + 1] = vf:spacer{ height = 20 }

    local function isEnabled( id )
        if lookup[id].appliesTo == nil then
            return true
        end
        if prefs[pvKey] == 'both' then
            return true
        end
        if prefs[pvKey] == 'pv2012' then
            return lookup[id].appliesTo == DevelopSettings.pvCode2012
        elseif prefs[pvKey] == 'pvLegacy' then
            return lookup[id].appliesTo == DevelopSettings.pvCodeLegacy
        else
            error( "bad code" )
        end
    end
    local enable12Binding = bind { 
        key = pvKey,
        transform = function()
            if prefs[pvKey] == 'pv2012' or prefs[pvKey] == 'both' then
                return true
            else
                return false
            end
        end
    }
    local enableLegBinding = bind { 
        key = pvKey,
        transform = function()
            if prefs[pvKey] == 'pvLegacy' or prefs[pvKey] == 'both' then
                return true
            else
                return false
            end
        end
    }
    
    local chgHdlr = function( id, props, key, value )
        app:call( Call:new{ name="Develop Settings Change Handler", async=true, guard=App.guardSilent, main=function( call )
            --Debug.pause( props[key], key, value )
            if key:find( "_data" ) then
                local dataKey = key
                local inclKey = key:gsub( "_data", "_incl" )
                local absKey = key:gsub( "_data", "_abs" )
                if type( value ) == 'number' then
                    local abs = props[absKey]
                    if value ~= 0 or abs then
                        props[inclKey] = true
                    else -- incr/rel and value == 0
                        props[inclKey] = false -- do not include.
                    end
                elseif type( value ) == 'boolean' then
                    if value then
                        props[inclKey] = true
                    else
                        props[inclKey] = false -- may want to include false values too, but they'll have to be explicitly included.
                    end                    
                elseif type( value ) == 'string' then
                    if str:is( value ) then
                        props[inclKey] = true
                    else
                        props[inclKey] = false -- may want to include blank strings too, but they'll have to be explicitly included.
                    end                    
                end
            elseif key:find( "_abs" ) then
                local inclKey = key:gsub( "_abs", "_incl" )
                if value then
                    props[inclKey] = true
                else -- back to incr/rel.
                    local dataKey = key:gsub( "_abs", "_data" )
                    if props[dataKey] ~= 0 then
                        props[inclKey] = true
                    else
                        props[inclKey] = false
                    end
                end
            elseif key:find( "_incl" ) then
                local absKey = key:gsub( "_incl", "_abs" )
                local abs = props[absKey]
                local dataKey = key:gsub( "_incl", "_data" )
                local dataVal = props[dataKey]
                if value then -- checked inclusion box
                    if not abs then -- relative
                        if dataVal == 0 then
                            local button = app:show{ confirm="Are you sure you want to include a relative setting whose value is zero?",
                                actionPrefKey = "Include relative zeros",
                            }
                            if button ~= 'ok' then
                                props[key] = false
                            end
                        end
                    end
                else -- cleared inclusion box
                    if dataVal ~= 0 then
                        local button = app:show{ confirm="You are clearing inclusion box, care to set value to zero value too in order to keep tidy?",
                            buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                            actionPrefKey = "Zero value to stay tidy",
                        }
                        if button == 'ok' then
                            props[dataKey] = 0
                        end
                    end
                end
            end
        end } )            
    end
    
    -- add view-item (vi):
    local function add( member )
        local enableBinding
        if member.appliesTo == 0 then
            Debug.pause( "applies to zero" )
            return
        elseif member.appliesTo == DevelopSettings.pvCode2012 then
            enableBinding = enable12Binding
        elseif member.appliesTo == DevelopSettings.pvCodeLegacy then
            enableBinding = enableLegBinding
        else
            enableBinding = true -- enabled.
        end
        lookup[member.id] = member

        local initInclVal        
        local initVal -- init data value
        local vItem -- final view item
        
        -- view item components:
        local inclView
        local labelView
        local dataView
        local altView
        local absView -- not incremental, but absolute.
        
        local dataKey = str:fmtx( "^1_^2_data", itemKey, member.id )
        local inclKey = str:fmtx( "^1_^2_incl", itemKey, member.id )
        local absKey = str:fmtx( "^1_^2_abs", itemKey, member.id )
        
        if bindTo[inclKey] == nil then -- need proper init ###2
            bindTo[inclKey] = false
        end
        
        inclView = vf:checkbox {
            title = "", -- not titled
            bind_to_object = bindTo,
            value = bind( inclKey ),
            tooltip = "If checked, develop setting will be included; if unchecked, then it won't be included.",
            enabled = enableBinding,
        }

        if spec.viewType == 'devSettingsEditor' then
            if member.dataType == 'number' then
                --Debug.pause( "number" )
                local constraints = member.constraints or {}
                initVal = 0 -- have default specifyable somehow? ###2 note: dev-settings are not properly initialized until edited. ###2
                labelView = vf:static_text {
                    title = member.friendly,
                    width = share 'label_width',
                }
                if constraints[1] and type( constraints[1] ) == 'table' then
                    assert( constraints[1].title ~= nil, "dont understand constraints" ) -- value could be nil, but titles must exist.
                    dataView = vf:popup_menu {
                        bind_to_object = bindTo,
                        value = bind( dataKey ),
                        items = constraints,
                        fill_horizontal = 1,
                        width = share 'd_width',
                        enabled = enableBinding,
                    }
                else
                    dataView = vf:slider {
                        bind_to_object = bindTo,
                        value = bind( dataKey ),
                        width = 250,
                        min = constraints.min,
                        integral = not ( ( constraints.precision or 0 ) > 0 ),-- and ( constraints.max or 1 ) > 5 ),
                        max = constraints.max,
                        enabled = enableBinding,
                    }
                    altView = vf:edit_field {
                        bind_to_object = bindTo,
                        value = bind( dataKey ),
                        width_in_digits = 6,
                        width = share 'd_width_2',
                        min = constraints.min,
                        precision = constraints.precision or 0, -- assure mac & windows have same precision.
                        max = constraints.max,
                        enabled = enableBinding,
                    }
                    if bindTo[absKey] == nil then -- need proper init ###2
                        bindTo[absKey] = false
                    end
                    absView = vf:checkbox {
                        title = "", -- not titled
                        bind_to_object = bindTo,
                        value = bind( absKey ),
                        tooltip = "If checked, develop setting will be interpreted as absolute; if unchecked, then it will be interpreted as incremental/relative.",
                    }
                    view:setObserver( bindTo, absKey, Settings, chgHdlr )
                    view:setObserver( bindTo, inclKey, Settings, chgHdlr )

                end
            elseif member.dataType == 'boolean' then
                --Debug.pause( "boolean" )
                initVal = false -- ditto ###2
                labelView = vf:static_text {
                    title = "",
                    width = share 'label_width',
                }
                dataView = vf:checkbox {
                    title = member.friendly,
                    bind_to_object = bindTo,
                    value = bind( dataKey ),
                    width = share 'd_width',
                    enabled = enableBinding,
                }
            elseif member.dataType == 'string' then
                --Debug.pause( "string" )
                initVal = "" -- ###2
                local constraints = member.constraints
                labelView = vf:static_text {
                    title = member.friendly,
                    width = share 'label_width',
                }
                if tab:isEmpty( constraints ) then
                    dataView = vf:edit_field {
                        bind_to_object = bindTo,
                        value = bind( dataKey ),
                        --width_in_chars = 25,
                        fill_horizontal = 1,
                        width = share 'd_width',
                        enabled = enableBinding,
                    }
                else -- consider combo-box for some items ###3
                    local items
                    if constraints[1].title == nil then
                        items = {}
                        for i, c in ipairs( constraints ) do
                            items[#items + 1] = { title=c, value=c }
                        end
                    else
                        items = constraints
                    end
                    dataView = vf:popup_menu {
                        bind_to_object = bindTo,
                        value = bind( dataKey ),
                        items = items,
                        fill_horizontal = 1,
                        width = share 'd_width',
                        enabled = enableBinding,
                    }
                end
            else
                Debug.pause( member.dataType )
            end
            
            --Debug.pause( dataKey, initVal )
            self:_initPref( dataKey, initVal )
            assert( labelView, "no labelView" )
            assert( dataView, "no dv" )
            vItem = vf:row {
                inclView,
                labelView,
                dataView, -- edit field, popup, slider
                altView,  -- edit-field following slider
                absView,
            }
            
            view:setObserver( bindTo, dataKey, Settings, chgHdlr )
            
        elseif spec.viewType == 'devSettingsChooser' then
        
            --Debug.pause( "chooser" )
            vItem = vf:row { -- roll-yer-own checkbox.
                inclView,
                vf:static_text {
                    title = member.friendly,
                }
            }
        else
            Debug.pause( spec.viewType )
        end
        if vItem then
            vi[#vi + 1] = vItem
        end
    end
    
    for i, group in ipairs( DevelopSettings.table ) do -- DevelopSettings.getSpecTable()
        repeat
            if group.groupName ~= nil then
                vi[#vi + 1] = vf:row {
                    vf:static_text {
                        title = " ",
                        width = share 'label_width',
                    },
                    vf:static_text {
                        title = group.groupName,
                    },
                }
            else
                break -- convenience
            end
            if group.members == nil then
                app:error( "group sans members" )
                -- break
            end
            for j, member in ipairs( group.members ) do
                if member.id then
                    add( member )
                else
                    local pItem = vf:separator{ fill_horizontal = 1}
                    vi[#vi + 1] = pItem
                    for ii, submember in ipairs( member.members ) do
                        add( submember )
                    end
                    local pItem = vf:separator{ fill_horizontal = 1}
                    vi[#vi + 1] = pItem
                end
            end
            vi[#vi + 1] = vf:separator{ fill_horizontal=1 }
        until true
    end
    --if vi[#vi].separator then
    --    vi[#vi] = nil -- kill extraneous separator.
    --end
    
    assert( #vi > 0, "No vi" )
    
    local scroller = vf:scrolled_view( vi )
    
    local function writeEditedValues()
        local adj = {} 
        local pvConstraint = prefs[pvKey]
        for id, v in pairs( lookup ) do
            if isEnabled( id ) then
                local dkey = str:fmtx( "^1_^2_data", itemKey, id )
                local ikey = str:fmtx( "^1_^2_incl", itemKey, id )
                if prefs[ikey] then
                    local uiVal = prefs[dkey]
                    if spec.viewType == 'devSettingsEditor' then
                        if v.dataType == 'number' then
                            --if uiVal ~= 0 then
                                adj[#adj + 1] = { id=id, value=uiVal }
                            --end
                        elseif v.dataType == 'string' then
                            --if str:is( uiVal ) then
                                adj[#adj + 1] = { id=id, value=uiVal }
                            --end
                        elseif v.dataType == 'boolean' then
                            --if uiVal ~= false then
                                adj[#adj + 1] = { id=id, value=uiVal }
                            --end
                        else
                            Debug.pause()
                        end
                    else
                        adj[id] = true -- just a set of id's (hopefully no need for maintaining order).
                    end
                --else don't include
                end
            else
                -- omit disabled.
            end
        end
        
        --Debug.pause( adj )
        if spec.viewType == 'devSettingsEditor' then
            self:_write( itemKey, bindTo, adj, spec, "dev settings edited" )
        else
            self:_write( itemKey, bindTo, adj, spec, "dev settings chosen" )
        end
    end
    
    -- showing items may not be appropriate for screens designed to have view-items inline,
    -- like cookmarks, thus this little short-circuiter:
    if returnViewItems then
        return { scroller }, writeEditedValues
    end

    -- present inline in response to browse button...
    local info        
    if spec.viewType == 'devSettingsEditor' then
        info = "Enter Develop Adjustments"
    else
        info = "Choose Develop Settings"
    end
    
    local answer = app:show{ info=info,
        viewItems = { scroller },
    }
    if answer == 'ok' then
        writeEditedValues()            
    end
    
end



--- Get generic array of view items based on data description table.
--  
--  @param viewData (table, required) array of data descriptors.
--         <pre>
--              table element:
--         </pre>
--  @param bindTo ( property table, required )
--
function Settings:getViewItems( params )
    local elem = app:callingAssert( params.dataDescr, "need data-descr" )
    --local data = params.data or error( "no data" )
    local bindTo = params.bindTo or prefs -- app:callingAssert( params.bindTo, "no bind-to" ) - changed 4/Feb/2013 15:18 - I think it was an assertion primarily for debugging.
    local parentKey = app:callingAssert( params.key, "no key" ) -- a key must be specified. I 'spose it could default to root, but that's not a good idea me-thinks.
    -- added 4/Feb/2013 15:12 -
    if self:isKeyRelative( parentKey ) then
        parentKey = self:getKey( parentKey ) -- translate to absolute format, conditioned (prefixed) by currently selected preset name.
        --Debug.pause( parentKey )
    end
    --
    local call = app:callingAssert( params.call, "need call" )
    local options = params.options or {}
    if options.index then
        parentKey = parentKey .. "_" .. options.index
        Debug.logn( "getting view items for parent with options index", parentKey )
    else
        Debug.logn( "getting view items for parent without options index", parentKey )
    end
    if params.forceInit then
        self:_init( parentKey, elem, bindTo, true ) -- force init.
    elseif params.init == nil or params.init then -- do init by default, unless init is set to false
        self:_init( parentKey, elem, bindTo, false ) -- no force init.
    else
        app:logv( "assuming already init - if not so, then set init or force-init to true." )
    end
    local viewLookup = {}
    local viewItems = {}
    local dataWidthInChars = 30
    local dataWidth = share 'data_width'
    local labelWidth = share 'label_width'
    local function getValueBinding( spec, parentKey )
        return self:_getValueBinding( spec, parentKey, bindTo )
    end
    -- not used yet, since text functions have environment issues to be worked out.
    local function getFuncValue( spec, parentKey )
        app:callingAssert( parentKey, "no parent key" )
        local itemKey = parentKey .. "__" .. ( spec.id or error( "no id" ) )
        Debug.logn( spec.id, "getting value for using", itemKey )
        local value, rawValue
        rawValue = bindTo[itemKey]
        if spec.dataType == 'function' then
            if str:is( rawValue ) then
                local func, err = loadstring( rawValue, spec.id ) -- returns nil, errm if any troubles: no need for pcall (short chunkname required for debug).
                --Debug.pause()
                if func then
                    value = func
                else
                    --Debug.pause()
                    rawValue = "function() end"
                    value = function() end
                end
            else
                rawValue = "function() end"
                value = function() end
            end
        else
            error( "not a func" )
        end
        Debug.logn( "got func value", value, rawValue )
        return value, rawValue
    end
    local function addSep( title, options )
        options = options or {}
        local fill = options.fill_horizontal or 1
        local height = options.height or 5
        viewItems[#viewItems + 1] = vf:spacer{ height = height } -- above line
        viewItems[#viewItems + 1] = vf:separator{ fill_horizontal = fill }
        if str:is( title ) then
            viewItems[#viewItems + 1] = vf:spacer{ height = height } -- below line (above title )
            viewItems[#viewItems + 1] = vf:row {
                vf:spacer{ width=labelWidth },
                vf:static_text {
                    title=title,     
                }
            }
            viewItems[#viewItems + 1] = vf:spacer{ height = height } -- below title
        else
            viewItems[#viewItems + 1] = vf:spacer{ height = height + 1 } -- below line.
        end
    end
    local addViewItems -- forward function reference.
    local function addViewItem( spec, parentKey ) -- local
        --Debug.pause( spec )
        if spec == nil then
            app:callingError( "spec required" )
        end
        if spec.supported == false then -- usually assigned .._ENV of supprted platform.
            Debug.logn( "skipping unsupported view spec, parent key:", parentKey, "id", spec.id )
            return
        end
        if spec.viewType == 'spacer' then
            Debug.logn( "Adding spacer" )
            viewItems[#viewItems + 1] = vf:spacer( spec.viewOptions )
            return
        end
        if spec.viewType == 'separator' then
            Debug.logn( "Adding separator" )
            addSep( spec.title, spec.viewOptions )
            return
        end
        Debug.logn()
        Debug.logn( "Adding view spec, parent key:", parentKey, "id", spec.id )
        
        app:callingAssert( parentKey, "need parent key" )
        local viewItem
        
        local label = -- default label:
            vf:static_text {
                title = spec.friendly,
                width = share 'label_width',
            }
        -- default data:
        local binding, itemKey = getValueBinding( spec, parentKey )
        local viewOptions = tab:getTable( spec.viewOptions ) or {}
        local viewData = tab:mergeSets( { bind_to_object = bindTo, value = binding, width=dataWidth }, viewOptions )
        
        if spec.dataType == 'string' then
            if viewOptions.items then
                if spec.viewType == nil or spec.viewType == 'popup' then
                    viewData.items = viewOptions.items
                    viewItem = vf:row {
                        label,
                        vf:popup_menu( viewData )
                    }
                elseif spec.viewType == 'combo_box' then
                    viewData.items = viewOptions.items
                    viewItem = vf:row {
                        label,
                        vf:combo_box( viewData )
                    }
                else
                    error( "bad spec ui-type" )
                end
            elseif viewOptions.init then
                app:error( "init not supported for strings - use view-options:items instead." )
            else -- any string
                viewData.width = share 'data_width'
                viewData.width_in_chars = dataWidthInChars
                local text = vf:edit_field( viewData )
                local button
                if spec.viewType == 'browsableFile' or spec.viewType == 'browsableFolder' then
                    local chooserData = tab:mergeSets( { title = "Choose one." }, spec.chooserOptions )
                    button = vf:push_button {
                        title = 'Browse',
                        action = function( button )
                            app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                                if spec.viewType == 'browsableFile' then
                                    local file = dia:selectFile( chooserData, bindTo, itemKey ) -- passing props and key allows intelligent 
                                    if file ~= nil then
                                        self:_write( itemKey, bindTo, file, spec, "chosen file" ) -- should be redundent now, except for debug logn. Still, cheap insurance...
                                    end
                                else
                                    local folder = dia:selectFolder( chooserData, bindTo, itemKey ) -- passing props and key allows intelligent 
                                    if folder ~= nil then
                                        self:_write( itemKey, bindTo, folder, spec, "chosen folder" ) -- should be redundent now, except for debug logn. Still, cheap insurance...
                                    end
                                end
                            end } )
                        end,
                    }
                elseif spec.viewType == 'dngOptionsChooser' then
                    --local chooserData = tab:mergeSets( { title = "Choose options." }, spec.chooserOptions )
                    button = vf:push_button {
                        title = 'Browse',
                        action = function( button )
                            app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                                self:_dngOptionsView( itemKey, bindTo, spec )
                            end } )
                        end,
                    }
                --[[ *** save for potential future resurrection: status @6/Feb/2013 0:19 - dev-settings supports array data-type only
                elseif spec.viewType == 'devSettingsEditor' or spec.viewType == 'devSettingsChooser' then
                    button = vf:push_button {
                        title = 'Browse',
                        action = function( button )
                            app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                                self:_devSettingsView( itemKey, bindTo, spec )
                            end } )
                        end,
                    }
                --]]
                -- else just label and text
                end
                viewItem = vf:row {
                    label,
                    text,
                    button
                }
            end
        elseif spec.dataType == 'boolean' then
            -- view-type 
            if spec.viewType ~= nil then
                Debug.pause( "boolean view-type is based solely on default value." )
            end
            if spec.default == nil then
                local yes = vf:radio_button( tab:mergeSets( { title="Yes", bind_to_object = bindTo, value = binding, checked_value=true }, viewOptions ) )
                local no = vf:radio_button( tab:mergeSets( { title="No", bind_to_object = bindTo, value = binding, checked_value=false }, viewOptions ) )
                local maybe = vf:radio_button( tab:mergeSets( { title="Let plugin decide", bind_to_object = bindTo, value = binding, checked_value=nil }, viewOptions ) )
                local w = vf:spacer{ width=20 }
                viewItem = vf:row{ label, yes, no, w, maybe }
            elseif type( spec.default ) == 'boolean' then
                viewData.title = spec.friendly
                label.title = " "
                local checkbox = vf:checkbox( viewData )
                local paddedCheckbox = vf:column{
                    vf:spacer{ height=3 },
                    checkbox,
                    vf:spacer{ height=3 },
                }
                viewItem = vf:row{ label, paddedCheckbox }
            else
                error( "bad boolean spec" )
            end
        elseif spec.dataType == 'number' then
            app:assert( viewOptions, "numeric items should be constrained" )
            --Debug.pause( constraints )
            viewData.precision = viewOptions.precision or 0
            viewData.min = viewOptions.min or -( math.huge / 2 - 1 )
            viewData.max = viewOptions.max or math.huge
            viewItem = vf:row {
                label,
                vf:edit_field( viewData )
            }
            --Debug.pause( viewItem )
        elseif spec.dataType == 'proxy' then -- target type is function
            if spec.viewType == 'popup' then -- function selection via popup menu
                local items
                if viewOptions.items then
                    items = viewOptions.items
                elseif spec.init then
                    items = {}
                    for i, v in ipairs( spec.init ) do
                        items[#items + 1] = { title=v.title, value=v.title } -- need values to be true, so init table can not be used verbatim for popup items.
                    end
                else
                    error( "no items" )
                end
                viewData.items = items
                if #items > 1 or spec.show then
                    viewItem = vf:row {
                        label,
                        vf:popup_menu( viewData )
                    }
                else -- hide item, and make sure conditions are correct for retrieving value.
                    -- should already be init, this for cheap insurance:
                    self:_initDefault( itemKey, bindTo, spec ) -- if only one initializer for   s t a t i c   proxy, the default had better be it's value.
                end
            else
                app:error( "view-type for proxy must be popup" )
            end
        elseif spec.dataType == 'function' then -- target type is function
            --Debug.pause( "getting func val" )
            local func, funcstr = getFuncValue( spec, parentKey )
            --Debug.pause( funcstr )
            viewData.height_in_lines = viewData.height_in_lines or 3
            viewData.width = dataWidth
            viewData.width_in_chars = dataWidthInChars
            if str:is( funcstr ) then
                viewItem = vf:row {
                    label,
                    vf:edit_field( viewData )
                }
            else
                --return nil, "loadstring was unable to load contents returned from: " .. tostring( file or 'nil' ) .. ", error message: " .. err -- lua guarantees a non-nil error message string.
                app:logErr( "func err" ) -- consider presenting despite, with red-font iff compiler error.
            end
        elseif spec.dataType == 'array' then
        
            -- should do all functions like this, to improve readability/maintainability.
            if spec.viewType == 'popup' then
                --Debug.pause( "popup", spec.id )
                viewItem = self:_getPopupView( spec, parentKey, bindTo, call )
            elseif spec.viewType == 'multiList' then
                Debug.pause( "list", spec.id )
                viewItem = self:_getListView( spec, parentKey, bindTo, call )
            elseif spec.viewType == 'devPresetChooser' then
                -- consider a real entity, to make common.
                viewData.width_in_chars = 30
                viewData.height_in_lines = 2
                viewData.tooltip = "Enter here 1 per line, or use 'Browse' button for adding presets, and text field for deleting them."
                local dataView = vf:edit_field( viewData )
                local button = vf:push_button {
                    title = 'Browse',
                    action = function( button )
                        app:call( Call:new{ name="Develop Preset Chooser", async=true, main=function( call )
                            local props = LrBinding.makePropertyTable( call.context )
                            local items = getDevPresetItems()
                            local answer = app:show{ info="Choose Develop Preset, to be added to list.",
                                viewItems={ vf:popup_menu {
                                    bind_to_object = props,
                                    items = items,
                                    value = bind 'devPreset',
                                } }
                            }
                            if answer == 'cancel' then
                                return
                            end
                            local value = bindTo[itemKey]
                            if str:is( value ) then
                                bindTo[itemKey] = value .. "\n" .. props.devPreset
                            else
                                bindTo[itemKey] = props.devPreset
                            end
                        end } )
                    end,
                }
                viewItem = vf:row{ label, dataView, button }
            elseif spec.viewType == 'metaPresetChooser' then
                -- consider a real entity, to make common.
                viewData.width_in_chars = 30
                viewData.height_in_lines = 2
                viewData.tooltip = "Enter here 1 per line, or use 'Browse' button for adding presets, and text field for deleting them."
                local dataView = vf:edit_field( viewData )
                local button = vf:push_button {
                    title = 'Browse',
                    action = function( button )
                        app:call( Call:new{ name="Metadata Preset Chooser", async=true, main=function( call )
                            local props = LrBinding.makePropertyTable( call.context )
                            local items = getMetaPresetItems()
                            local answer = app:show{ info="Choose metadata preset, to be added to list.",
                                viewItems={ vf:popup_menu {
                                    bind_to_object = props,
                                    items = items,
                                    value = bind 'preset',
                                } }
                            }
                            if answer == 'cancel' then
                                return
                            end
                            local value = bindTo[itemKey]
                            if str:is( value ) then
                                bindTo[itemKey] = value .. "\n" .. props.preset
                            else
                                bindTo[itemKey] = props.preset
                            end
                        end } )
                    end,
                }
                viewItem = vf:row{ label, dataView, button }
            elseif spec.viewType == 'keywordChooser' then
                -- consider a real entity, to make common.
                viewData.width_in_chars = 30
                viewData.height_in_lines = 2
                viewData.tooltip = "Enter keywords here, separated by commas (spaces are OK around the commas). One day there may be a keywords browse button..."
                local dataView = vf:edit_field( viewData )
                local button
                viewItem = vf:row{ label, dataView, button }
            elseif spec.viewType == 'devSettingsEditor' or spec.viewType == 'devSettingsChooser' then
                local button = vf:push_button {
                    title = 'Browse',
                    action = function( button )
                        app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                            self:_devSettingsView( itemKey, bindTo, spec )
                        end } )
                    end,
                }
                local dataView = vf:static_text {
                    title = bind {
                        bind_to_object = bindTo,
                        key = itemKey, -- only asserts change when array is re-written.
                        transform = function()
                            local adj = prefs[itemKey]
                            if spec.viewType == 'devSettingsEditor' then
                                if #adj > 0 then
                                    return str:nItems( #sets, "edited settings" )
                                else
                                    return "No edited settings"
                                end
                            elseif spec.viewType == 'devSettingsChooser' then
                                local cnt = tab:countItems( adj )
                                if cnt > 0 then
                                    return str:nItems( cnt, "chosen settings" )
                                else
                                    return "No chosen settings"
                                end
                            else
                                return str:to( spec.viewType or "bad view type" )
                            end
                        end
                    }
                }
                viewItem = vf:row{ label, dataView, button }
            else
                error( "bad spec type" )
            end
        
        end
        if viewItem then
            --Debug.pause( viewItem )
            viewItems[#viewItems + 1] = viewItem
            viewLookup[spec.id] = { spec=spec, viewItem=viewItem } -- this is weak, but so far view-lookup is not being used. ###3
        else
            --Debug.pause( spec.id, spec.viewType) - this happens regularly, when only 1 item in (non-array) popup.
        end
    end
    function addViewItems( elem, parent ) -- local
        --Debug.pause( whatev, parent )
        assert( elem, "no elem" )
        for i, v in ipairs( elem ) do
            addViewItem( v, parent )
        end
    end
    dataWidthInChars = dataWidthInChars or elem.dataWidthInChars
    addViewItems( elem, parentKey )
    --Debug.pause( #viewItems )
    return viewItems, viewLookup
end



return Settings