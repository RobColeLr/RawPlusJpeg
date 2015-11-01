--[[
        Info.lua
--]]

return {
    appName = "Raw Plus Jpeg",
    author = "Rob Cole",
    authorsWebsite = "www.robcole.com",
    donateUrl = "http://www.robcole.com/Rob/Donate",
    platforms = { 'Windows', 'Mac' },
    pluginId = "com.robcole.lightroom.RawPlusJpeg",
    xmlRpcUrl = "http://www.robcole.com/Rob/_common/cfpages/XmlRpc.cfm",
    LrPluginName = "rc Raw Plus Jpeg",
    LrSdkMinimumVersion = 3.0,
    LrSdkVersion = 5.0,
    LrPluginInfoUrl = "http://www.robcole.com/Rob/ProductsAndServices/RawPlusJpegLrPlugin",
    LrPluginInfoProvider = "ExtendedManager.lua",
    LrToolkitIdentifier = "com.robcole.RawPlusJpeg",
    LrInitPlugin = "Init.lua",
    LrShutdownPlugin = "Shutdown.lua",
    LrMetadataTagsetFactory = "Tagsets.lua",
    LrLibraryMenuItems = {
        {
            title = "&Find Raws with Jpegs",
            file = "mFindRawsWithJpegs.lua",
        },
        {
            title = "&View Jpegs",
            file = "mViewJpegs.lua",
        },
        {
            title = "&Sync (RAW -> JPEG)",
            file = "mSyncRawToJpeg.lua",
        },
        {
            title = "&Sync (JPEG -> RAW)",
            file = "mSyncJpegToRaw.lua",
        },
        {
            title = "Delete Jpegs",
            file = "mDeleteJpegs.lua",
        },
        {
            title = "&Import Jpegs",
            file = "mImportJpegs.lua",
        },
        {
            title = "E&xtract Jpegs",
            file = "mExtractJpegs.lua",
        },
    },
    VERSION = { display = "2.5.2    Build: 2013-10-02 23:18:32" },
}
