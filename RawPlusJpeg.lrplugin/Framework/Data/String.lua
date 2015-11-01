--[[
        String.lua
--]]

local String, dbg = Object:newClass{ className = 'String', register = false }

local pluralLookup
local singularLookup
local pw



--- Constructor for extending class.
--
function String:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function String:new( t )
    return Object.new( self, t )
end



--- General purpose tester for lower case string.
--
function String:isLower( s )
    if LrStringUtils.lower( s ) == s then return true end
end



--- High performance tester for lower case char
--
function String:isCharLower( c )
    if string.byte( c ) >= 97 and string.byte( c ) <= 122 then return true end
end



--- Trim whitespace from front (left) of string.
--
--  @usage Reminder: Lr's trimmer is not binary compatible, this method is.
--
function String:trimLeft( s )
    local non, stop = s:find( "[^%s]" )
    if non then
        return s:sub( stop )
    else
        return ""
    end
end



--[[ Trim whitespace from tail (right) of string. NOT WORKING:
--
--  @usage Reminder: Lr's trimmer is not binary compatible, this method is.
--
function String:trimRight( s )
    for i = #s, 1, -1 do
        local c = str:getChar( s, i )
        if not c:find( "[^%s]" ) then
            return s:sub( 1, i )
        end
    end
    return s
end
--]]



--- Break down a path into an array of components.
--
--  @usage              Does not distinguish absolute from relative paths.
--
--  @return             array (1st component is root), usually not empty, never nil.
--
function String:breakdownPath( path )
    local a = {}
    local p = LrPathUtils.parent( path )
    local x = LrPathUtils.leafName( path )
    
    local slashes = path:find( "[\\/]" ) -- default find'r matches lua pattern.
    if not slashes then -- already root drive/device name.
        return { path }        
    end
    
    while x do
        a[#a + 1] = x
        if p then
            x = LrPathUtils.leafName( p )
        else
            break
        end
        p = LrPathUtils.parent( p )
    end

    local b = {}
    local i = #a
    while i > 0 do
        b[#b + 1] = a[i]
        i = i - 1
    end
    return b
end



--- Split a string based on delimiter.
--
--  @param      s       (string, required) The string to be split.
--  @param      delim   (string, required) The delimiter string (plain text). Often something like ','.
--  @param      maxItems (number, optional) if passed, final element will contain entire remainder of string. Often is 2, to get first element then remainder.
--
--  @usage              Seems like there should be a lua or lr function to do this, but I haven't seen it.
--  @usage              Components may be empty strings - if repeating delimiters exist.
--      
--  @return             Array of trimmed components - never nil nor empty table unless input is nil or empty string, respectively.
--
function String:split( s, delim, maxItems, regex )
    if s == nil then return nil end
    if s == '' then return {} end
    local t = {}
    local p = 1
    repeat
        local start, stop = s:find( delim, p, not regex )
        if start then
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p, start - 1 ) )
            p = stop + 1
            if maxItems ~= nil then
                if #t >= maxItems - 1 then
                    t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p ) )
                    break
                end
            end
        else
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p ) )
            break
        end
    until false
    return t
end



--- Split at delimiter, but interpret consecutive delimiters as escaped data, and unescape it.
--
--  @usage does not support max components, but does allow custom preparation function - defaulting to whitespace trimmer.
--
function String:splitEscape( s, delim, prepFunc )
    if s == nil then return nil end
    if s == '' then return {} end
    local t = {}
    local findIndex = 1
    local getIndex_1
    local getIndex_2
    if prepFunc == nil then
        prepFunc = LrStringUtils.trimWhitespace
    end
    repeat
        local start, stop = s:find( delim, findIndex, true )
        --Debug.pause( findIndex, start, stop )
        local n= 1
        if start then
            while s:sub( stop + n, stop + n + #delim - 1 ) == delim do
                n = n + #delim
            end
            if n > 1 then
                local _start, _stop = s:find( delim, stop + n, true )
                if _start then
                    getIndex_1 = findIndex
                    getIndex_2 = _start - 1
                    findIndex = _stop + 1
                else
                    getIndex_1 = findIndex
                    getIndex_2 = nil
                end
            else
                getIndex_1 = findIndex
                getIndex_2 = start - 1
                findIndex = stop + 1
            end
        else
            getIndex_1 = findIndex
            getIndex_2 = nil
        end
        local insert = s:sub( getIndex_1, getIndex_2 )
        if n > 1 then
            insert = insert:gsub( delim..delim, delim )
        end
        t[#t + 1] = prepFunc( insert )
        if getIndex_2 == nil then
            break
        end
    until false
    return t
end






---     Make path from component array.
--
--      @param comps        The array of path components: 1st element is root, last element is child.
--
function String:makePathFromComponents( comps )

    local path = comps[1]

    for i = 2, #comps do
        path = LrPathUtils.child( path, comps[i] )
    end

    return path

end
        



---	Determine if two strings are equal other than case differences.
--
function String:isEqualIgnoringCase( s1, s2 )
	local s1l = string.lower( s1 )
	local s2l = string.lower( s2 )
	return s1l == s2l
end



---	Determine if two strings are equal - case-sensitive by default.
--
function String:isEqual( s1, s2, ignoreCase )
    if ignoreCase then
        return self:isEqualIgnoringCase( s1, s2 )
    else
        return s1 == s2
    end
end



---	Makes a string of spaces - used for indentation and output formatting...
--
--  @usage				*** Deprecated - use Lua's string-rep function instead.
--
function String:makeSpace( howMany )
    return string.rep( " ", howMany ) -- there used to be a lot more in this function ;-}
end



--- Remove spaces from middle of a string (as well as ends).
--      
--  @usage          Convenience function to make more readable than testing for nil followed by gsub.
--      
--  @return         Squeezed string, nil -> empty.
--
function String:squeeze( s )
    if s == nil then
        return ''
    else
        return s:gsub( " ", '' )
    end
end



--- Remove redundent adjacent characters.
--      
--  @usage          Initial motivation was to format value returned by table.concat( items, " " ) when some items may be empty strings.
--      
--  @return         Consolidated string.
--
function String:consolidate( s, char, charCount )
    if s == nil then
        return ''
    end
    charCount = charCount or 1
    if charCount == 0 then
        char = ""
    else
        char = ( char or " " ):rep( charCount )
    end
    local chars = char:rep( charCount + 1 )
    local rslt, matchCount = s:gsub( chars, char )
    while matchCount > 0 do
        rslt, matchCount = rslt:gsub( chars, char )
    end
    return rslt
end



--- Squeezes a path to fit into fixed width display field.
--
--  <p>One could argue for another parameter that selects a balance between first part of path, and second part of path<br>
--     i.e. balance = 0 => select first part only, balance = 1 => prefer trailing path, .5 => split equally between first and last part of path.</p>
--  <p>Although its conceivable that some pathing may be preferred over long filename, that solution is waiting for a problem...</p>
--
--  @usage          Guaranteed to get entire filename, and as much of first part of path as possible.
--  @usage          Lightroom does something similar for progress caption, but algorithm is different.
--
--  @return         first-part-of-path.../filename.
--
function String:squeezePath( _path, _width )
    local len = string.len( _path )
    if len <= _width then
        return _path
    end
    -- fall-through => path reduction necessary.
    local dir = LrPathUtils.parent( _path )
    local filename = LrPathUtils.leafName( _path )
    local fnLen = string.len( filename )
    local dirLen = _width - fnLen - 4 -- dir len to be total len less filename & .../
    if dirLen > 0 then
        dir = string.sub( dir, 1, dirLen ) .. ".../"
        return dir .. filename
    else
        return filename -- may still be greater than width. If this becomes a problem, return substring of filename,
            -- or even first...last.
    end
end



--- Return lenth-limited version of s
function String:limit( s, n )
    if s == nil or s:len() <= n or n < 4 then
        return s
    else
        return s:sub( 1, n - 3 ) .. "..."
    end
end

       

--- Squeezes a string to fit into fixed width display field.
--
--  @return          first half ... last half
--
function String:squeezeToFit( _str, _width )

    if self:is( _str ) then
        if _str:len() > _width then -- reduction required.
            if _width >= 5 then
                local firstHalf = math.ceil( _width / 2 ) - 2
                -- 5 => 1, 1
                -- 6 => 1, 2
                -- 7 => 2, 2
                -- 8 => 2, 3
                -- 9 => 3, 3
                local secondHalf = math.floor( _width / 2 ) - 1
                return _str:sub( 1, firstHalf ) .. "..." .. _str:sub( - secondHalf )
            else
                return "..." -- just punt if the field is that freakun small.
            end
        else
            return _str
        end
    else
        return ""
    end

end
        


---     Synopsis:       Pads a string on the left with specified character up to width.
--
--      Motivation:     Typically used with spaces for tabular display, or 0s when string represents a number.
--
function String:padLeft( s, chr, wid )
    local n = wid - string.len( s )
    --[[ this until 7/Feb/2013 18:13 -
    while( n > 0 ) do
        s = chr .. s
        n = n - 1
    end
    return s
    --]]
    -- this since 7/Feb/2013 18:13 - (more efficient)
    if n > 0 then
        local pad = string.rep( chr, n )
        return pad .. s
    else
        return s
    end
end



--- Pads a string on the left with specified character up to width.
--
--  @usage Typically used with spaces for tabular display, or 0s when string represents a number.
--  @usage only works right if fixed-width font.
--
function String:padRight( s, chr, wid )
    local n = wid - string.len( s )
    if n > 0 then
        local pad = string.rep( chr, n )
        return s .. pad
    else
        return s
    end
end



--- Convenience function for getting the n-th character of a string.
--
--  @param      s       The string.
--  @param      index   First char is index 1.
--
--  @usage      @2010-11-23: *** Will throw error if index is out of bounds, so check before calling if unsure.
--
--  @return     character in string.
--
function String:getChar( s, index )
    return string.sub( s, index, index )
end



--- Convenience function for getting the first character of a string.
--
--  @usage throws error if string does not have a first character, so check before calling if necessary.
--
function String:getFirstChar( s )
    if self:is( s ) then
        return string.sub( s, 1, 1 )
    else
        return ''
    end
end
String.firstChar = String.getFirstChar -- synonym for same method.



--- Convenience function for getting the last character of a string.
--
--  @usage throws error if string does not have a last character, so check before calling if necessary.
--
function String:getLastChar( s )
    if str:is( s ) then
        local len = string.len( s )
        return string.sub( s, len, len )
    else
        return ''
    end
end
String.lastChar = String.getLastChar --- synonym for same method.



--- Compare two strings.
--
--  @usage          Returns immediately upon first difference.
--
--  @return         0 if same, else difference position.
--
function String:compare( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return len2
    elseif len2 > len1 then
        return len1
    end
    local c1, c2
    for i=1, len1, 1 do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            return i
        end
    end
    return 0
end



--- Get the difference between two strings.
--      
--  @usage      Use to see the difference between two strings.
--      
--  @return     diff-len
--  @return     s1-remainder
--  @return     s2-remainder
--
function String:getDiff( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    local compLen
    local diffLen = len1 - len2
    if diffLen > 0 then
        compLen = len2
    else
        compLen = len1
    end
    local c1, c2, i
    i = 1
    while i <= compLen do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            return i, string.sub( s1, i ), string.sub( s2, i )
        end
        i = i + 1
    end
    if diffLen > 0 then
        return diffLen, string.sub( s1, i ), nil
    elseif diffLen < 0 then
        return diffLen, nil, string.sub( s2, i )
    else
        return 0, nil, nil
    end
        
end
        


--- Compare two strings in their entirety (or until one string runs out of characters).
--
--  @usage      Use when it is desired to know the character positions of all the differences.
--  @usage      Most appropriate when the files are same length, or at least start off the same, since there is no attempt to resynchronize...
--
--  @return     nil if same, else array of difference indexes.
--
function String:compareAll( s1, s2, count )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return { len2 }
    elseif len2 > len1 then
        return { len1 }
    end
    local c1, c2
    local diffs = {}
    for i=1, len1, 1 do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            diffs[#diffs + 1] = i
        end
    end
    if #diffs > 0 then
        return diffs
    else
        return nil
    end
end



--- Extract a number from the front of a string.
--
--  <p>Initial application for ordering strings that start with a number.</p>
--
--  @return          Next parse position.
--
--  @usage           *** Warning: Does NOT check incoming string or parse position.
--
function String:getNonNegativeNumber( s )
    local pos1, pos2 = string.find( s, "%d+", 1 )
    if pos1 ~= nil and pos1 == 1 then
        return tonumber( string.sub( s, pos1, pos2 ) ), pos2 + 1
    else
        return nil, -1
    end
end



--- Format a string using LOC formatter but without localization.
-- 
--  @usage          An alternative to lua string.format function (which uses ansi 'C' printf syntax).
--
function String:format( s, ... )
    if s ~= nil then
        return LOC( "$$$/X=" .. s, ... )
    else
        return ""
    end
end
String.fmt = String.format -- synonym: String:fmt( s, ... )



--- Format a string, ampersands are expected to be in && win-compatible format (if plugin runs on Windows too), but will be converted to mac compatible format on mac.
--
--  @param      s       format string in LOC format.
--  @param      ...     substution variables - any format: nil OK.
--
--  @usage      x in the name stands for cross-platform.
--  @usage      Will never throw an error, unless format string is not string type - don't use for critical program strings, just logging and UI display, when it's better to have a small aesthetic bug than a catastrophic error.
--  @usage      LOC will throw error when passed a boolean, string.format will throw an error when insufficient substitutions or incompatible data type.
--  
function String:fmtx( s, ... )
    if not str:is( s ) then
        return ""
    end
    local subs = {}
    local param = { ... } -- include nils
    -- 1st: assure all parameters are substutued.
    for i = #param + 1, math.huge do
        local token = "^" .. i
        local p1, p2 = s:find( token, 1, true )
        if p1 then
            local _, m = pcall( error, "Insufficient substitutions for str:fmtx", 3 ) -- fake an error in caller of this function and get module name + line-no.
            Debug.pause( m )
            s = s:gsub( "%"..token, "???" ) -- no plain text substutution, so escape the '^'.
        else
            break
        end
    end
    for i = 1, #param do -- ipairs quits on first nil, but this "iterator" won't.
        subs[i] = str:to( param[i] )
    end
    local t = LOC( "$$$/X=" .. s, unpack( subs ) )
    return WIN_ENV and t or t:gsub( "&&", "&" )
end



---     Same as format plain except converts ampersands for windows compatibility.
--
--  @deprecated in favor of fmtx.
--
--      Assumes they are formatted for Mac compatibility upon entry (single '&' ).
--      
--      Pros: More readable on all platforms.
--      Cons: Less efficient on Windows.
--
function String:formatAmps( s, ... )
    local t = LOC( "$$$/X=" .. s, ... )
    return ( WIN_ENV and t:gsub( "&", "&&" ) ) or t
end
String.fmtAmps = String.formatAmps -- Synonym



---     Same as format plain except converts ampersands for mac compatibility.
--      
--  @deprecated in favor of fmtx.
--
--      Assumes they are formatted for Windows compatibility upon entry (double '&&' ).
--      
--      Pros: More efficient on windows.
--      Cons: Less efficient on Mac, & less readable.
--
function String:formatAmp( s, ... )
    local t = LOC( "$$$/X=" .. s, ... )
    return ( MAC_ENV and t:gsub( "&&", "&" ) ) or t
end
String.fmtAmp = String.formatAmp -- Synonym




---     Example: str:loc( "My/Thing", "In English, we say...^1", myvar )
--      
--      In my opinion, this is just more readable than the LOC syntax.
--
function String:loc( i18nKey, s, ... )
    return LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
end

function String:locAmps( i18nKey, s, ... )
    local t = LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
    return ( WIN_ENV and t:gsub( "&", "&&" ) ) or t
end

function String:locAmp( i18nKey, s, ... )
    local t = LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
    return ( MAC_ENV and t:gsub( "&&", "&" ) ) or t
end



--- Determine if one string starts with another (regex by default).
--      
--  <p>Avoids the problem of using the nil returned by string.find in a context that does not like it.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--  @usage      If string is not expected to be there at the start, and the source string is very long, it will be more efficient to pass a substring instead, for example:<br>
--                  local isThere = str:isStartingWith( longstr:sub( 1, t:len() ), t )
--  @usage      you must also pass parameters "1, true" for plain text (index must be one, followed by boolean true).
--
--  @return     true iff s begins with t in character position 1.
--
function String:isStartingWith( s, t, ... )
    local start = s:find( t, ... ) -- ###3 probably should have hardcode 1 as start pos, since it's the only thing that makes sense.
    return start ~= nil and start == 1
end



--- Determine if one string begins with another (plain text).
--      
--  <p>Does not use 'find'.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--
--  @return     true iff s begins with t.
--
function String:isBeginningWith( s, t )
    return s:sub( 1, t:len() ) == t
end



--- Determine if one string ends with another.
--      
--  <p>Avoids the problem of using the nil returned by string.find in a context that does not like it.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--
--  @return     true iff s begins with t in character position 1.
--
function String:isEndingWith( s, t )
    return ( s:sub( 0 - t:len() ) == t )
end



--- Return last index in source string, of target string.
--
--  @return startIndex or 0 if not found - never returns nil.
--  @return stopIndex or 0 if not found - never returns nil.
--
function String:getLastIndexOf( s, t, regexFlag )
    local index = 0
    local index2 = 0
    local startAt = 1
    while( true ) do
        local start, stop = s:find( t, startAt, regexFlag )
        if start then
            index = start
            index2 = stop
            startAt = stop + 1
        else
            break
        end
    end
    return index, index2
end
String.lastIndexOf = String.getLastIndexOf -- synonym, for backward compatibility.



--- Return string that complies with Lr preference key requirements.
--
--  @usage initial motivation is for lr pref key.
--  @usage reminder: photo metadata properties can not begin with an underscore, dunno 'bout catalog properties for plugin. prefs are OK with leading underscore.
--               
--
function String:makeLuaVariableNameCompliant( s )
    if s == nil then
        error( "unable to make nil lua variable name compliant", 2 )
    end
    return s:gsub( "[^%w_]", '' ) -- strip everything except alpha-numeric and '_'
end



--- Return string that complies with filename requirements.
--
function String:makeFilenameCompliant( s )
    assert( s ~= nil, "need s to make compliant" )
    return s:gsub( "[:\\/?*]", '-' ) -- replace all funny chars with '-', for lack of a better replacement.
end



--- Convert path to key that can be used for "property for plugin" key: photo or catalog.
--
function String:pathToPropForPluginKey( path )
    local fileKey = path:gsub( "%.", "__D__" )
    fileKey = fileKey:gsub( "\\", "__N__" )
    fileKey = fileKey:gsub( "/", "__Z__" )
    fileKey = fileKey:gsub( ":", "__C__" )
    fileKey = fileKey:gsub( " ", "_" )
    fileKey = fileKey:gsub( "-", "_" )
    -- assure does not begin with underscore: dunno if required for catalog properties for plugin,
    -- but *is* required for photo properties for plugin.
    local pos = 1
    while pos < fileKey:len() do
        local c = str:getChar( fileKey, pos )
        if c ~= '_' then
            break
        else
            pos = pos + 1
        end
    end
    if pos > 1 then
        return fileKey:sub( pos )
    else
        return fileKey
    end
end



--- Makes a word presumed to be singular into its plural form.
--      
--  @usage      Call is-plural and trim beforehand if necessary.
--
function String:makePlural(word)

    self:initPlurals() -- if not already.

	local lowerword = string.lower(word)
	local wordlen = string.len(word)

	-- test to see if already plural, if so, return word as is
	-- if TestIsPlural(word) == true then return word end - more efficient to not test unless
	-- unless there is a question about it. if it already is plural, then it will get double pluralized

	-- test to see too short
	if wordlen <=2 then return word end  -- not a word that can be pluralized

	-- test to see if it is in special dictionary
	--check special dictionary, return word if found but keep first letter from original
	local dicvalue  = pluralLookup [lowerword]
	if dicvalue ~= nil then
		local dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if the word ends in a consonant plus -y, change the -y into, ies or es
	pw = string.sub(lowerword, wordlen-1,wordlen)
	if	pw=="by" or pw=="cy" or pw=="dy" or pw=="fy" or pw=="gy" or pw=="hy" or
		pw=="jy" or pw=="ky" or pw=="ly" or pw=="my" or pw=="ny" or pw=="py" or
		pw=="qy" or pw=="ry" or pw=="sy" or pw=="ty" or
		pw=="vy" or pw=="wy" or pw=="xy" or pw=="zy" then

		return string.sub(word,1,wordlen -1) .. "ies"
	
	-- for words that end in -is, change the -is to -es to make the plural form.
	elseif pw=="is" then return string.sub(word,1,wordlen -2) .. "es"

		-- for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
	elseif pw=="ch" or pw=="sh" then return word .. "es"

	else
		pw=string.sub(pw,2,1)
		if pw=="s" or pw=="z" or pw=="x" then
			return word .. "es"
		else
			return word .. "s"
		end
	end
	
end -- function to return plural form of singular



--- Make a plural form singular.
--      
--  @usage          If unsure whether already singular, call is-plural before-hand, and trim if necessary.
--
function String:makeSingular( word, exception )

    self:initPlurals() -- if not already.
    
	local wordlen = string.len(word)

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return word end
	
	--check special dictionary, return word if found but keep first letter from original
	local lowerword = string.lower(word)
	local dicvalue  = singularLookup [lowerword]
	if dicvalue ~= nil then
		local dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if it is singular form in the special dictionary, then you can't remove plural
	if pluralLookup [lowerword] ~= nil then return word end
	
	-- if at this point it doesn't end in and "s", it is probably not plural
	if string.sub(lowerword,wordlen,wordlen) ~= "s" then return word end

	--If the word ends in a consonant plus -y, change the -y into -ie and add an -s to form the plural � so reverse engineer it to get the singular
	if wordlen >=4 then
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="cies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" then
			return string.sub(word,1,wordlen -3) .. "y"
		--for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
		elseif pw=="ches" or pw=="shes" then
			return string.sub(word,1,wordlen -2)
		end
	end

	if wordlen >=3 then
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			-- some false positive here, need to add those to dictionary as found
			if not exception then
			    return string.sub(word,1,wordlen -2) -- common
			else
			    return string.sub(word,1,wordlen -1) -- but this comes up regularly for me.
			end
		elseif string.sub(pw,2,3)=="es" then
		    if not exception then
			    return string.sub(word,1,wordlen -2) .. "is" -- not sure which words this applies to.
			else
			    return string.sub(word,1,wordlen -1) -- but this comes up regularly for me.
			end
		end
	end

	-- at this point, just remove the "s"
	return string.sub(word,1,wordlen-1)

end -- function to return a singular form of plural word



--- Determine if a word is singular or plural.
--
--  <p>Note: It is possible for some plurals to escape detection. Not to be used when ascertainment is critical - intention is more for aesthetics...</p>
--      
--  @usage          trim beforehand if necessary.
--      
--  @return         true iff word is plural.
--
function String:isPlural(word)

    self:initPlurals() -- if not already.
    
	local lowerword = string.lower(word)
	local wordlen = #word

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return false

	--check special dictionary to see if plural form exists
	elseif singularLookup [lowerword] ~= nil then
		return true  -- it's definitely already a plural


	elseif wordlen >= 3 then
		-- 1. If the word ends in a consonant plus -y, change the -y into -ie and add 			an -s to form the plural 
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" or pw=="ches" or
			pw=="shes" then
			
			return true -- it's already a plural (reasonably accurate)
		end
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			
			return true -- it's already a plural (reasonably accurate)
		end

		pw = string.sub(lowerword, wordlen-1,wordlen)
		if	pw=="es" then
			
			return true -- it's already a plural (reasonably accurate)
		end
	end

	--not a plural word (after looking into special dictionary if it doesn't end in s
	if string.sub(lowerword, wordlen,wordlen) ~= "s" then
		return false

	else
		return true

	end -- group of elseifs
		
end -- function to test to see if word is plural



--- Initializes dictionaries for singular/plural support.
--
--  <p>May never be called if plugin does not call at least one plural function.</p>
--
--  @usage          Could be called in plugin-init, or in string constructor - but isn't. - will be called on first demand.
--
function String:initPlurals()

    if singularLookup ~= nil then return end -- test if already init.

--	Here are known words that have funky plural/singular conversions, they should
-- 	be checked first in all cases before the other rules are checked.  Probably wise to
--	set these as a global variable in the "init" code of the plug-in to keep from 
--	initializing everytime.

	pluralLookup = {
		afterlife	= "afterlives",
		alga		= "algae",
		alumna		= "alumnae",
		alumnus		= "alumni",
		analysis	= "analyses",
		antenna		= "antennae",
		appendix	= "appendices",
		axis		= "axes",
		bacillus	= "bacilli",
		basis		= "bases",
		bedouin		= "bedouin",
		cactus		= "cacti",
		calf		= "calves",
		cherub		= "cherubim",
		child		= "children",
		christmas	= "christmases",
		cod			= "cod",
		cookie		= "cookies",
		criterion	= "criteria",
		curriculum	= "curricula",
		dance		= "dances",
		datum		= "data",
		deer		= "deer",
		diagnosis	= "diagnoses",
		die			= "dice",
		dormouse	= "dormice",
		elf			= "elves",
		elk			= "elk",
		erratum		= "errata",
		esophagus	= "esophagi",
		fauna		= "faunae",
		fish		= "fish",
		flora		= "florae",
		focus		= "foci",
		foot		= "feet",
		formula		= "formulae",
		fundus		= "fundi",
		fungus		= "fungi",
		genie		= "genii",
		genus		= "genera",
		goose		= "geese",
		grouse		= "grouse",
		hake		= "hake",
		half		= "halves",
		headquarters= "headquarters",
		hippo		= "hippos",
		hippopotamus= "hippopotami",
		hoof		= "hooves",
		horse		= "horses",
		housewife	= "housewives",
		hypothesis	= "hypotheses",
		index		= "indices",
		jackknife	= "jackknives",
		knife		= "knives",
		labium		= "labia",
		larva		= "larvae",
		leaf		= "leaves",
		life		= "lives",
		loaf		= "loaves",
		louse		= "lice",
		magus		= "magi",
		man			= "men",
		memorandum	= "memoranda",
		midwife		= "midwives",
		millennium	= "millennia",
		miscellaneous= "miscellaneous",
		moose		= "moose",
		mouse		= "mice",
		nebula		= "nebulae",
		neurosis	= "neuroses",
		nova		= "novas",
		nucleus		= "nuclei",
		oesophagus	= "oesophagi",
		offspring	= "offspring",
		ovum		= "ova",
		ox			= "oxen",
		papyrus		= "papyri",
		passerby	= "passersby",
		penknife	= "penknives",
		person		= "people",
		phenomenon	= "phenomena",
		placenta	= "placentae",
		pocketknife	= "pocketknives",
		pupa		= "pupae",
		radius		= "radii",
		reindeer	= "reindeer",
		retina		= "retinae",
		rhinoceros	= "rhinoceros",
		roe			= "roe",
		salmon		= "salmon",
		scarf		= "scarves",
		self		= "selves",
		seraph		= "seraphim",
		series		= "series",
		sheaf		= "sheaves",
		sheep		= "sheep",
		shelf		= "shelves",
		species		= "species",
		spectrum	= "spectra",
		stimulus	= "stimuli",
		stratum		= "strata",
		supernova	= "supernovas",
		swine		= "swine",
		synopsis	= "synopses",
		terminus	= "termini",
		thesaurus	= "thesauri",
		thesis		= "theses",
		thief		= "thieves",
		trout		= "trout",
		vulva		= "vulvae",
		wife		= "wives",
		wildebeest	= "wildebeest",
		wolf		= "wolves",
		woman		= "women",
		yen			= "yen",
		-- RDC 12/Jun/2012 14:24
		-- Note: if you are passing complex terms, like "my filenames" to make singular, you must use the exception parameter.
		file        = "files",
		-- base        = "bases", - this must be handled by passing exception parameter to make-singular, since the singular is ambiguous in this case (see basis above).
		name        = "names",
		filename    = "filenames",
	}

	-- this creates a reverse lookup table of the special dictionary by reversing the variables
	-- names with the string result

	singularLookup = {}
	for k, v in pairs (pluralLookup) do
		singularLookup [v] = k
	end
	
end -- of dictionary initialization function



--- Return singular or plural count of something.
--
--  <p>Could be enhanced to force case of singular explicitly, instead of just adaptive.</p>
--
--  @param      count       Actual number of things.
--  @param      singular    The singular form to be used if count is 1.
--  @param      useNumberForSingular        may be boolean or string<blockquote>
--      boolean true => use numeric form of singular for better aesthetics.<br>
--      string 'u' or 'upper' => use upper case of singular (first char only).<br>
--      string 'l' or 'lower' => use lower case of singular (first char only).<br>
--      default is adaptive case.</blockquote>
-- 
--  @usage      Example: str:format( "^1 rendered.", str:plural( nRendered, "photo" ) ) - "one photo" or "2 photos"
--  @usage      Case is adaptive when word form of singular is used. For example: str:plural( nRendered, "Photo" ) - yields "One Photo".
--
function String:plural( count, singular, useNumberForSingular )
	local countStr
	local suffix = singular
	if count then
	    if count == 1 then
			if bool:isBooleanTrue( useNumberForSingular ) then
				countStr = '1 '
			else
		        local firstChar = self:getFirstChar( singular )
		        local upperCase
			    if str:isString( useNumberForSingular ) then
			        local case = str:getFirstChar( useNumberForSingular )
			        if case == 'u' then 
    			        upperCase = true
    			    elseif case == 'l' then
    			        upperCase = false
    			    -- else adaptive
    			    end
    			end
    			if upperCase == nil then -- adaptive.
    			    upperCase = (firstChar >= 'A' and firstChar <= 'Z') -- adaptive
    			end
		        if upperCase then
		            countStr = "One "
		        else
		            countStr = "one "
		        end
			end
	    else
	        countStr = self:to( count ) .. " "
			suffix = self:makePlural( singular ) -- correct 99.9% of the time.
	    end
	else
		countStr = 'nil '
	end
	return countStr .. suffix
end



--- Return string with number of items in proper grammar.
--
--  @param count number of items
--  @param plural correct grammer for items if 0 or >1 item.
--  @param useWordForSingular pass true iff One or one is to be displayed when 1 item. Case is adaptive.
--
--  @usage not so sure this was a good idea. Seems making plural is more often correct than making singular. ###2
--
function String:nItems( count, pluralPhrase, exception )
    local suffix
	local countStr
	if count then
	    if count ~= 1 then -- most of the time.
	        countStr = self:to( count ) .. " "
			suffix = pluralPhrase
		else
		    countStr = '1 '
            local index = self:lastIndexOf( pluralPhrase, " " )
            local pluralWord
            if index > 0 then
                pluralWord = pluralPhrase:sub( index + 1 )
            else
                pluralWord = pluralPhrase
            end
		    local singularWord = str:makeSingular( pluralWord, exception )
		    suffix = pluralPhrase:sub( 1, index ) .. singularWord
	    end
	else
	    Debug.pause( "str--n-items count is nil" )
		countStr = 'nil '
		suffix = pluralPhrase
	end
	return countStr .. suffix
end



--- Determine if a string value is non-nil or empty.
-- 
--  <p>Convenience function to avoid checking both aspects, or getting a "expected string, got nil" error.</p>
--      
--  @usage      If value type is not known to be string if not nil, then use 'is-string' instead.
--  @usage      Throws error if type is not string or nil.
--
--  @return     true iff non-empty string.
--
function String:is( s, name )
    if s ~= nil then
        if type( s ) == 'string' then
            if s:len() > 0 then
                return true
            else
                return false
            end
        else -- data-type error
            name = name or "String:is argument"
            error( LOC( "$$$/X=^1 should be string, not ^2 (^3)", name, type( s ), tostring( s ) ), 2 ) -- 2 => assert error in calling context instead of this one.
        end
    else
        return false
    end
end



--- Determine if a value is nil, or if string whether its empty.
--
--  <p>Avoids checking aspects individually, or getting a "expected string, got nil or boolean" error.
--      
--  @usage      Also weathers the case when s is a table (or number?)
--
function String:isString( s )
    if s and (type( s ) == 'string') and ( s ~= '' ) then
        return true
    else
        return false
    end
end



--- Convert windows backslash format to mac/unix/ftp forward-slash notation.
--
--  @usage      Prefer lr-path-utils - standardize-path to assure path to disk file is in proper format for localhost.
--  @usage      This function is primarily used for converting windows sub-paths for use in FTP.
--              <br>Lightroom is pretty good about allowing mixtures of forward and backward slashes in ftp functions,
--              <br>but still - I find it more pleasing to handle explicitly.
--
function String:replaceBackSlashesWithForwardSlashes( _path )
    if _path ~= nil then
        local path = string.gsub( _path, "\\", "/" )
        return path
    else
        return ""
    end
end


function String:formatPath( _path )
    if WIN_ENV then
        return string.gsub( _path, "/", "\\" )
    else
        return string.gsub( _path, "\\", "/" )
    end    
end



--- Strip non-ascii characters from binary string.
--
--  @usage Good for searching for text in binary files, otherwise string searcher stops upon first zero byte.</br>
--         could probably just strip zeros, but this gives a printable string that can be logged for debug...
-- 
function String:getAscii( binStr )
    local c = {}
    for i = 1, binStr:len() do
        local ch = str:getChar( binStr, i )
        local cn = string.byte( ch )
        if cn < 32 or cn > 126 then
            -- toss
        else
            c[#c + 1] = ch
        end
    end
    return table.concat( c, '' )
end



--- Global substitution of plain text.
--
function String:searchAndReplace( s, search, replace, padChar, max )
    local rslt = {}
    local p0 = 1
    local padString = nil
    local padReduce = nil
    if padChar then
        local rlen = replace:len()
        local slen = search:len()
        if  rlen < slen then
            padString = string.rep( padChar, slen - rlen )
        elseif rlen > slen then
            padReduce = rlen - slen
        end
    end
    max = max or 1000000 -- sanity: to prevent potential infinite loop.
    local p1, p2 = s:find( search, 1, true )
    local cnt = 0
    while p1 do
        rslt[#rslt + 1] = s:sub( p0, p1-1 )
        rslt[#rslt + 1] = replace
        p0 = p2 + 1
        if padString then
            rslt[#rslt + 1] = padString -- append pad string to compensate for short replacement.
        elseif padReduce then
            local char = str:getChar( s, p0 )
            local count = 0
            while char == padChar and count < padReduce do
                count = count + 1
                p0 = p0 + 1
                char = str:getChar( s, p0 )
            end
            if count == padReduce then -- all successive chars were padding
                -- good
            else
                error( "Pad fault" )            
            end
        end
        cnt = cnt + 1
        if cnt >= max then
            break
        else
            p1, p2 = s:find( search, p0, true )
        end
    end
    rslt[#rslt + 1] = s:sub( p0 )
    return table.concat( rslt, '' )
end



--- Returns iterator over lines in a string.
--
--  <p>For those times when you already have a file's contents as a string and you want to iterate its lines. This essential does the same thing as Lua's io.lines function.</p>
--
--  @usage      Handles \n or \r\n dynamically as EOL sequence.
--  @usage      Does not handle Mac legacy (\r alone) EOL sequence.
--  @usage      Works as well on binary as text file - no need to read as text file unless the lines must be zero-byte free.
--
function String:lines( s, delim )
    local pos = 1
    local last = false
    return function()
        local starts, ends = string.find( s, '\n', pos, true )
        if starts then
            if string.sub( s, starts - 1, starts - 1 ) == '\r' then
                starts = starts - 1
            end
            local retStr = string.sub( s, pos, starts - 1 )
            pos = ends + 1
            return retStr
        elseif last then
            return nil
        else
            last = true
            return s:sub( pos )
        end
    end
end



--- Breaks a string into tokens by getting rid of the whitespace between them.
--
--  @param              s - string to tokenize.
--  @param              nTokensMax - remainder of string returned as single token once this many tokens found in the first part of the string.
--      
--  @usage              Does similar thing as "split", except delimiter is any whitespace, not just true spaces.
--
function String:tokenize( s, nTokensMax )
    local tokens = {}
    local parsePos = 1
    local starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
    local substring = nil
    while starts do
        if nTokensMax ~= nil and #tokens == (nTokensMax - 1) then -- dont pass ntokens-max = 0.
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos ) )
        else
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos, starts ) )
        end
        if string.len( substring ) > 0 then
            tokens[#tokens + 1] = substring
        -- else - ignore
        end
        if nTokensMax ~= nil and #tokens == nTokensMax then
            break
        else
            parsePos = ends + 1
            starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
        end
    end
    if #tokens < nTokensMax then
        tokens[#tokens + 1] = LrStringUtils.trimWhitespace( s:sub( parsePos ) )
    end
    return tokens
end



--- Get filename sans extension from path.
--      
--  @usage          *** this failed when I tried these ops in reverse, i.e. removing extension of leaf-name not sure why. Hmmm...
--
function String:getBaseName( fp )        
    return LrPathUtils.leafName( LrPathUtils.removeExtension( fp ) )
end



---     Return string suitable primarily for short (synopsis-style) debug output and/or display when precise format is not critical.
--      
--      Feel free to pass a nil value and let 'nil' be returned.
--      
--      If object has an explicit to-string method, then it will be called, otherwise the lua global function.
--      
--      Use dump methods for objects and/or log-table..., if more verbose output is desired.
--
function String:to( var )
    if var ~= nil then
        if type( var ) == 'table' and var.toString ~= nil and type( var.toString ) == 'function' then
            return var:toString()
        else
            return tostring( var )
        end
    else
        return 'nil'
    end
end



--- Get root drive of specified path.
--
function String:getRoot( path ) -- ###1 test on mac
    if not str:is( path ) then
        app:callingError( 'path must be non-empty string' )
    end
    local root = path
    local leaves = { LrPathUtils.leafName( path ) }
    local parent = LrPathUtils.parent( path )
    while parent ~= nil do
        root = parent
        leaves[#leaves + 1] = LrPathUtils.leafName( parent )
        parent = LrPathUtils.parent( parent )
    end
    return root, leaves
end



--- Get root drive of specified path.
--
function String:getDriveAndSubPath( path )
    if not str:is( path ) then
        app:callingError( 'path must be non-empty string' )
    end
    local root = path
    local leaves = { LrPathUtils.leafName( path ) }
    local parent = LrPathUtils.parent( path )
    while parent ~= nil do
        root = parent
        leaves[#leaves + 1] = LrPathUtils.leafName( parent )
        parent = LrPathUtils.parent( parent )
    end
    if #leaves > 1 then -- there are 2 parts
        leaves[#leaves] = nil -- remove root
        tab:reverseInPlace( leaves ) -- make most-sig 1st.
        return root, table.concat( leaves, WIN_ENV and "\\" or "/" ) -- standardize file-path... ###1 test on Mac
    else
        assert( path == root, "?" )
        return path, "" -- all root, no sub-path
    end
end



--- Determine whether start & stop indices, when applied to substring, have a chance of yielding a non-empty string.
--
--  @usage      Note: checking is independent of string len. If len is to be considered, it must be done in calling context.
--
--  @return     0 iff yes. (-1 means both are negative and no-go, +1 means both are positive and no-go).
--
function String:checkIndices( start, stop )
    if start < 0 and stop < start then -- always specifies the empty string.
        return -1
    elseif start > 0 and stop > 0 then
        if stop < start then
            return 1
        -- else OK
        end
    -- note: if one is positive and one is negative, then their relative positioning depends on the length of the string.
    end
    return 0
end



--- Append one string to another with a separator in between, but only if the first string is not empty.
--
function String:appendWithSep( s1, sep, s2 )
    if str:is( s1 ) then
        return s1 .. sep .. str:to( s2 )
    else
        return str:to( s2 )
    end
end



--- returns path with s2 as child of s1 - assures only 1 separator between them, whether s1 ends with a sep, or s2 begins with one.
--
--  @returns s1 sep s2
--
function String:child( s1, sep, s2 )
    local s1I
    local s2I
    if str:isEndingWith( s1, sep ) then
        s1I = s1:len() - 1
    else
        s1I = s1:len()
    end
    if str:isStartingWith( s2, sep ) then
        s2I = 2
    else
        s2I = 1
    end
    return s1:sub( 1, s1I ) .. sep .. s2:sub( s2I )
end



--- Is all upper case.
function String:isAllUpperCaseAlphaNum( s )
    if s:find( "[^%u%d]" ) then
        return false
    else
        if app:isAdvDbgEna() then
            assert( s:find( "[%u%d]" ), "no U" )
        end
    end
    return true
end


--- Is all lower case.

function String:isAllLowerCaseAlphaNum( s )
    if s:find( "[^%l%d]" ) then
        return false
    else
        if app:isAdvDbgEna() then
            assert( s:find( "[%l%d]" ), "no L" )
        end
    end
    return true
end



--- Get 'a' as string if string else nil.
function String:getString( a, nameToThrow )
    if a ~= nil then
        if type( a ) == 'string' then
            return a
        elseif nameToThrow then
            app:error( "'^1' must be string, not '^2'", nameToThrow, type( a ) )
        else
            return nil
        end
    else
        return nil
    end
end



return String