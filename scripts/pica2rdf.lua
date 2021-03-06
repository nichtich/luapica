-------------------------------------------------------------------------------
-- Experimental demo conversion from PICA+ to RDF/Turtle.
-- @author Jakob Voss <voss@gbv.de>
-------------------------------------------------------------------------------

require 'pica'

--- Insert all values with integer keys from one table to another.
-- @param t the table to modify
-- @param a the table to concat to table a
table.append = function( t, a )
    local v
    for _,v in ipairs(a) do
        table.insert( t, v )
    end
end

-------------------------------------------------------------------------------
--- Main conversion
-- @param record a single record in PICA+ format (UTF-8)
-- @return string RDF/Turtle serialization
function main(record, source)
    if type(record) == "string" then
        record = PicaRecord.new(record)  
    end

    local t = record:first('002@$0')
    if not t then
        return "# Type not found"
    end

    local err
    local ttl = Turtle.new()

    if t:find('^[ABCEGHKMOSVZ]') then -- Bibliographic record
        bibrecord(record,ttl)
    elseif t:find('^Tp') then -- Person
        authority_person(record,ttl)
    elseif t:find('^T') then -- other kind of authority 
        authority(record,ttl)
    else
        return "# Unknown record type: "..t
    end

    return tostring(ttl) .. "\n# "..#ttl.." triples"
end

function recordidentifiers(record,source)
    local ids = { }

    local eki = table.concat( record:first('007G'):map({'c','0'}), '' )
    if eki ~= "" then 
        ids.eki = "<urn:nbn:de:eki/:"..eki..">"
    end

    -- VD16 Nummern: TODO

-- TODO
    -- VD17 Nummern (incl. alte Nummern bei Zusammenführungen!)
    local vd17 = record:all( '006Q$0|006W$0',{
        match   = "^[0-9]+:[0-9]+[A-Z]$", 
        format  = "<urn:nbn:de:vd17/%s>" 
    })
    table.append(ids, vd17)

    -- VD18 (TODO)
    --  local vd18 = record:first('006M$0'), 007S

    -- OCLC-Nummer (TODO): "info:oclcnum/"
    local oclc = record:first('003O','0')
    if (oclc ~= '') then
      -- info:oclcnum/
    --    table.insert(ids,'info/') -- TODO
    end

    return ids
end

-------------------------------------------------------------------------------
--- Transforms a bibliographic PICA+ record
-------------------------------------------------------------------------------
function bibrecord(record, ttl)

    local i,id
    for i,id in ipairs(recordidentifiers(record)) do
        if i == 1 then
            ttl:subject( id )
        else
            ttl:addlink( 'owl:sameAs', id )
        end
        -- ttl:add( "dc:identifier", eki )
    end

    ttl:addlink('a','dct:BibliographicResource')

    dc = record:map({
       ['dc:title'] = {'021A$a'},
       ['dct:extent'] = {'034D$a'}, -- TODO: add 034M    $aIll., graph. Darst.
    })

    for key,value in pairs(dc) do
        ttl:add( key, value )
    end

    ttl:add( "dct:issued", record:first('011@$a'), 'xsd:gYear' ) -- TODO: check datatype

    ---------------------------------------------------------------------------
    -- Sacherschließung
    ---------------------------------------------------------------------------
    -- 5056-5058 = 045V,045W,045Y : SSG-Angaben (TODO)

    -- 5060 = 045X *: Notation eines Klassifikationssystems (TODO)

    -- 5080 = 045U *: ZDB-Notation (TODO)

    -- 5090 = 045T *: RVK (TODO)

    -- 51xx = 041A : RSWK-Ketten (derzeit nicht als Kette ausgewertet)
    local swd = record:all('041A$8',{match='D\-ID:%s*(%d+)'})
    for _,swdid in ipairs(swd) do
        ttl:addlink( 'dc:subject', '<http://d-nb.info/gnd/'..swdid..'>' )
    end


    -- 54xx = 045H : DDC-Notation
    record:all('045H',function(f)
        local edition = f[{"e!",match="^DDC(%d+)"}]
        local notation = f["a!"]
        if edition and notation then
            local uri = "<http://dewey.info/class/"..notation.."/e"..edition.."/>"
            ttl:addlink( 'dc:subject', uri )
        end
    end)

    -- 5010 = 045F : DDC
    record:all('045F',function(f)
        local edition = f[{'e!',match="^DDC(%d+)"}]
        f:all({"a",function(notation)
            local uri = "<http://dewey.info/class/"..notation.."/e"..edition.."/>"
            ttl:addlink( 'dc:subject', uri )
        end})
    end)

    -- 5500 = 044A *: LoC Subject headings
    -- 5510 = 044C *: Medical subject headings
    -- 5520 = 044E *: PRECIS
    -- 5530 = 044F *: DDB-Schlagwörter bis 1986
    -- 5540 = 044G *: British Library subject headings
    -- ...

    -- 530x = 045Q : Basisklassifikation
    record:all('045Q$8',{match='(%d%d\.%d%d)', each = function(notation)
        ttl:addlink( 'dc:subject', '<http://uri.gbv.de/terminology/bk/'..notation..'>' ) end
        }
    )

    --- TODO: Digitalisat (z.B. http://nbn-resolving.org/urn:nbn:de:gbv:3:1-73723 )

end

--- Trim a string
function trim(s) return s:match'^%s*(.*%S)' or '' end

--- Collect and join subfield values (you must not use "+" and "*" flags).
function fjoin( field, sep, ... )
    local t = field:map({...})
    return table.concat({table.unpack(t)} , sep )
end


-- useful dumper method
function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end


-------------------------------------------------------------------------------
--- Transforms a PICA+ authority record about a person
-------------------------------------------------------------------------------
function  authority_person(rec,ttl)
    ttl:addlink('a','foaf:Person')
    ttl:addlink('a','skos:Concept')

    local pnd = rec:first('007S$0')
    if pnd == "" then
        ttl:warn("Missing PND!")
    else 
        ttl:subject( "<http://d-nb.info/gnd/" .. pnd..">" )
        ttl:add( "dc:identifier", pnd )
    end

    ttl:add( "dc:identifier", rec:first('003@$0' ))

    local name = rec:first('028A'):join(' ',{
      'e','d','a','5',              -- selected subfields in this order
      { 'f', format='(%s)' } -- also with filters
    })

    if name ~= '' then
        ttl:add("skos:prefLabel",name) 
        ttl:add("foaf:name",name) 
    end
    -- 028A $dVannevar$aBush

end

-------------------------------------------------------------------------------
--- Transforms PICA+ authority record
-------------------------------------------------------------------------------
function  authority(rec,ttl)
    ttl:addlink('a','skos:Concept')
    -- ...
end

-------------------------------------------------------------------------------
--- Simple turtle serializer.
-- This class provides a handy serializer form a limited subset of RDF/Turtle
-- format. Each instances stores multiple RDF statements with the same subject.
-- 
-- @class table
-- @name Turtle
-------------------------------------------------------------------------------
Turtle = {

    -- static properties
    popular_namespaces = {
        bibo = 'http://purl.org/ontology/bibo/',
        dc   = 'http://purl.org/dc/elements/1.1/',
        dct  = 'http://purl.org/dc/terms/',
        foaf = 'http://xmlns.com/foaf/0.1/',
        frbr = 'http://purl.org/vocab/frbr/core#',
        skos = 'http://www.w3.org/2004/02/skos/core#',
        xsd  = 'http://www.w3.org/2001/XMLSchema#',
        owl  = 'http://www.w3.org/2002/07/owl#',
    },
    literal_escape = {
        ['"']   = "\\\"",
        ["\\"]  = "\\\\",
        ["\t"] = "\\t",
        ["\n"] = "\\n",
        ["\r"] = "\\r"
    },

    -- operators
    __index = function(ttl,key) -- ttl [ key ]
        return Turtle[key]
    end

    -- # ttl returns the number of triples
}

--- Creates a new Turtle serializer.
-- @param subject the subject for all triples
function Turtle.new( subject )
    local tt = {
        warnings = { },
        namespaces = { }
    }
    setmetatable(tt,Turtle)
    tt:subject( subject or "[ ]" )
    return tt
end

--- Set the triple's subject.
function Turtle:subject( subject )
    self.subj = subject
end
 
--- Add a warning message.
-- @param message string to add as warning. Trailing whitespaces are removed.
function Turtle:warn( message )
    message = message:gsub("%s+$","")
    table.insert( self.warnings, message )
    return false
end

--- Adds a statement with literal as object.
-- empty strings as object values are ignored!
-- unknown predicate vocabularies are ignored!
function Turtle:add( predicate, object, lang_or_type )
    if object == nil or object == "" then
        return false
    end

    if type(object) == "string" or type(object) == "number" then
        object = self:literal(object, lang_or_type)
    end -- else???

    if not self:use_uri( predicate ) then
        return false -- TODO. log error
    end

    table.insert( self, " " .. predicate .. ' ' .. object )
    return true
end

--- Adds a statement with URI as object.
function Turtle:addlink( predicate, uri )
    if uri == nil or uri == "" then
        return false
    end

    if not self:use_uri( predicate ) or not self:use_uri( uri ) then
        return false -- TODO. log error
    end

    table.insert( self, " " .. predicate .. ' ' .. uri )
    return true
end


function Turtle:use_uri( uri )
    if uri == 'a' or uri:find('^<[^>]*>$') then
        return true
    else
        local _,_,prefix = uri:find('^([a-z]+):')
        if prefix and self.popular_namespaces[prefix] then
            self.namespaces[prefix] = self.popular_namespaces[prefix]
        else
            prefix = prefix and prefix..':' or uri
            self:warn( "unknown uri prefix " .. prefix )
            return false
        end
    end
    return true
end

--- Returns a RDF/Turtle document
function Turtle:__tostring()
    if #self == 0 then return "" end

    local ns = ""
    local prefix, uri

    for prefix, uri in pairs(self.namespaces) do
        ns = ns .. "@prefix "..prefix..": <"..uri.."> .\n"
    end
    if ns then ns = ns .. "\n" end

    local warnings,w = {}
    for _,w in ipairs(self.warnings) do
        w = "# "..w:gsub("\n","\n# ")
        table.insert( warnings, w )
    end

    return ns .. self.subj 
        .. table.concat( self, " ;\n    " ) .. " .\n" 
        .. table.concat( warnings, "\n" )
end

function Turtle:literal( value, lang_or_type )
    local str
    if type(value) == "string" then
        str = value:gsub('(["\\\t\n\r])',function(c)
            return Turtle.literal_escape[c]
        end)
        str = '"'..str..'"'
        if lang_or_type and lang_or_type ~= '' then
            if lang_or_type:find('^[a-z][a-z]$') then -- TODO: less restrictive
                str = str .. '@' .. lang_or_type
            elseif self:use_uri( lang_or_type ) then
                str = str .. '^^' .. lang_or_type
            else
                return
            end
        end
        -- TODO: add type_or_lang
    elseif type(value) == "number" then
        str = value
    end
    return str
end

