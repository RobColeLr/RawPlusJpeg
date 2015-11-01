--[[
        PublishServices.lua

        Represents a publish service from the point of view of catalog/database functionality, as opposed to export functionality,
        which is handled by the publish module proper.
--]]


local PublishServices, dbg = Object:newClass{ className = "PublishServices", register=true }



--- Constructor for extending class.
--
function PublishServices:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage      Represents the collection of all publish services defined under for a plugin.
--
function PublishServices:new( t )
    local o = Object.new( self, t )
    --[[ *** there can always be any number of publish service instances - however many the user has created.
    if o.publishService == nil then
        local srvs = catalog:getPublishServices( _PLUGIN.id )
        if #srvs == 0 then
            app:error( "There are no publish services for this plugin." )
        elseif #srvs == 1 then
            o.publishService = srvs[1]
        else
            app:error( "If more than one publish service in plugin (there are ^1), you must pass reference to publish-service.", #srvs )
        end
    else
        -- ok
    end
    --]]
    return o
end



-- private method to accumulate photos from specified collection.
function PublishServices:_addFromCollection( pubPhotos, pubColl, pubServices )
    local addPubPhotos = pubColl:getPublishedPhotos()
    local ps = pubColl:getService()
    for i = 1, #addPubPhotos do
        pubServices[#pubServices + 1] = ps
    end
    tab:appendArray( pubPhotos, addPubPhotos )
end



-- private method to accumulate photos from specified collections.
function PublishServices:_addFromColls( pubPhotos, colls, pubServices )
    for i, v in ipairs( colls ) do
        self:_addFromCollection( pubPhotos, v, pubServices )
    end
end



-- private method to accumulate photos from specified collection set.
function PublishServices:_addFromCollSet( pubPhotos, set, pubServices )
    local collSets = set:getChildCollectionSets()
    local colls = set:getChildCollections()
    self:_addFromColls( pubPhotos, colls, pubServices )
    self:_addFromCollSets( pubPhotos, collSets, pubServices )
end



-- private method to accumulate photos from specified collection sets.
function PublishServices:_addFromCollSets( pubPhotos, collSets, pubServices )
    for i, v in ipairs( collSets ) do
        if v:type() == 'LrPublishedCollection' then
            self:_addFromColl( pubPhotos, v, pubServices )
        elseif v:type() == 'LrPublishedCollectionSet' then
            self:_addFromCollSet( pubPhotos, v, pubServices )
        else
            app:error( "what?" )
        end
    end
end



--- Get all published photos, across all collections, all services defined for this plugin.
--
function PublishServices:getPublishedPhotos( pluginId )
    if pluginId == nil then
        pluginId = _PLUGIN.id -- for backward compatibility.
    elseif pluginId == 0 then
        pluginId = nil -- for new capability to get published photos for all services.
    end
    local pubPhotos = {}
    local pubServices = {} -- parallel array of services that each published photo is published on.
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        self:_addFromCollSet( pubPhotos, v, pubServices ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return pubPhotos, pubServices
end



--- Get table of published info (published-photo, published-collection, published-service, indexed by photo.
--
function PublishServices:getPublishedInfo( targetPhotos, pluginId )
    targetPhotos = targetPhotos or app:callingError( "Specify target photos." ) -- catalog:getTargetPhotos() - don't like the get-target-photos default.
    if pluginId == nil then
        pluginId = _PLUGIN.id -- for backward compatibility.
    elseif pluginId == 0 then
        pluginId = nil -- for new capability to get published photos for all services.
    end
    local photoSet = tab:createSet( targetPhotos )
    local info = {}
    local function fromColl( coll )
        local addPubPhotos = coll:getPublishedPhotos()
        local ps = coll:getService()
        for i, pp in ipairs( addPubPhotos ) do
            local p = pp:getPhoto()
            if photoSet[p] then -- include
                if info[p] == nil then
                    info[p] = { { pubPhoto = pp, pubColl = coll, pubSrv = ps } }
                else
                    local a = info[p]
                    a[#a + 1] = { pubPhoto = pp, pubColl = coll, pubSrv = ps }
                end
            -- else not to be included.
            end
        end
    end
    local function fromColls( colls )
        for i, v in ipairs( colls ) do
            fromColl( v )
        end
    end
    local fromCollSet -- forward reference
    local function fromCollSets( collSets )
        for i, v in ipairs( collSets ) do
            if v:type() == 'LrPublishedCollection' then
                fromColl( v )
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromCollSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromCollSet( set ) -- local
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromCollSets( collSets )
    end
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        fromCollSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return info
end



--- Get table of published collections as keys, publish service as value.
--
function PublishServices:getPublishCollectionInfo( pluginId )
    if pluginId == nil then
        pluginId = _PLUGIN.id
    elseif pluginId == 0 then
        pluginId = nil
    end
    local info = {}
    local function fromColls( _colls )
        for i, v in ipairs( _colls ) do
            info[v] = v:getService()
        end
    end
    local fromCollSet -- forward reference.
    local function fromCollSets( collSets )
        for i, v in ipairs( collSets ) do
            if v:type() == 'LrPublishedCollection' then
                --fromColl( v ) - ###1 presumably a bug, noticed 1/Sep/2013 7:24, not sure scope of applicability.
                fromColls{ v } -- bug presumably fixed 1/Sep/2013 7:25
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromCollSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromCollSet( set )
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromCollSets( collSets )
    end
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        fromCollSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return info
end



--- Get published photos corresponding to all selected photos.
--
--  @return array of published photos from one collection in one service - may be empty, but never nil.
--  @return Publish service - may be nil.
--  @return Publish collection - may be nil.
--
function PublishServices:getSelectedPublishedPhotos()
    local targetPhotos = catalog:getTargetPhotos()
    if tab:isEmpty( targetPhotos ) then
        return {}
    end
    local photoSet = {}
    for i, photo in ipairs( targetPhotos ) do
        photoSet[photo] = true
    end
    local sources = catalog:getActiveSources()
    local pubPhotos = {}
    local pubSrv -- not array, key'd by PS name.
    local pubColl
    for i, v in ipairs( sources ) do
        if v:type() == 'LrPublishedCollection' then
            if pubColl then
                app:error( "Photos must be from same published collection" )
            else
                pubColl = v
            end
            pubSrv = v:getService()
            local _pubPhotos = v:getPublishedPhotos()
            if #_pubPhotos > 0 then
                for j, pp in ipairs( _pubPhotos ) do
                    if photoSet[pp:getPhoto()] then -- published photo is selected
                        pubPhotos[#pubPhotos + 1] = pp
                    else
                    end
                end
            else
                Debug.logn( "No published photos in " .. pubColl:getName() )
            end
        end
    end
    return pubPhotos, pubSrv, pubColl
end



--- Call to assure fresh data before looking up collections based on id.
--
--  @usage Called automatically if need be, but can be called externally as part of init.
--
function PublishServices:computeCollLookup()
    self.collLookup = {}
    local fromColl, fromColls, fromSets, fromSet
    function fromColl( coll )
        --Debug.logn( str:fmt( "lookup for coll '^1', ID: ^2", coll:getName(), coll.localIdentifier ) )
        self.collLookup[coll.localIdentifier] = coll
    end
    function fromColls( colls )
        for i, v in ipairs( colls ) do
            fromColl( v )
        end
    end
    function fromSets( sets )
        --Debug.logn( str:fmt( "lookup for ^1 sets", #sets ) )
        for i, v in ipairs( sets ) do
            if v:type() == 'LrPublishedCollection' then
                fromColl( v )
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromSet( set )
        --Debug.logn( str:fmt( "lookup for set", set:getName() ) )
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromSets( collSets )
    end
    local srvs = catalog:getPublishServices() -- get publish services for all plugins.
    --Debug.logn( str:fmt( "lookup for ^1 services", #srvs ) )
    for i, v in ipairs( srvs ) do
        fromSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
end



--- Get collection by local identifier.
--
--  @param id local identifier as obtained via sdk, or sql.
--
function PublishServices:getCollectionByLocalIdentifier( id )
    if self.collLookup == nil then
        self:computeCollLookup()
    end
    return self.collLookup[id]
end



return PublishServices
