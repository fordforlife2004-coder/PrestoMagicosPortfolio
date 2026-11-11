-- A small JSON encoder and decoder for the tests (FiveM has its own json). Sets the global json if
-- there isn't one.

local J = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if math.type(k) ~= 'integer' or k < 1 then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local function encode(value)
    local kind = type(value)
    if value == nil then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        if math.type(value) == 'integer' then return tostring(value) end
        if value == math.floor(value) and math.abs(value) < 1e15 then return ('%d'):format(value) end
        return ('%.14g'):format(value)
    end
    if kind == 'string' then
        return '"' .. value:gsub('[%c"\\]', function(c) return escapes[c] or ('\\u%04x'):format(c:byte()) end) .. '"'
    end
    if kind == 'table' then
        local array, n = isArray(value)
        local parts = {}
        if array then
            for i = 1, n do parts[i] = encode(value[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        end
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = value[k]
            if v == nil then v = value[tonumber(k)] end
            parts[#parts + 1] = encode(k) .. ':' .. encode(v)
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    error('json: cannot encode ' .. kind)
end
J.encode = encode

function J.decode(text)
    local pos = 1
    local function ws() pos = text:find('[^ \t\r\n]', pos) or #text + 1 end
    local value
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            if c == '' then error('json: unterminated string') end
            if c == '"' then pos = pos + 1 break end
            if c == '\\' then
                local e = text:sub(pos + 1, pos + 1)
                local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if e == 'u' then
                    local code = tonumber(text:sub(pos + 2, pos + 5), 16)
                    out[#out + 1] = utf8.char(code)
                    pos = pos + 6
                else
                    out[#out + 1] = map[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    function value()
        ws()
        local c = text:sub(pos, pos)
        if c == '{' then
            local obj = {}
            pos = pos + 1
            ws()
            if text:sub(pos, pos) == '}' then pos = pos + 1 return obj end
            while true do
                ws()
                local k = str()
                ws()
                pos = pos + 1 -- :
                obj[k] = value()
                ws()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == '}' then return obj end
            end
        elseif c == '[' then
            local arr = {}
            pos = pos + 1
            ws()
            if text:sub(pos, pos) == ']' then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = value()
                ws()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == ']' then return arr end
            end
        elseif c == '"' then
            return str()
        elseif text:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif text:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif text:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        end
        local num = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
        if not num or num == '' then error('json: unexpected ' .. c) end
        pos = pos + #num
        return math.tointeger(tonumber(num)) or tonumber(num)
    end
    return value()
end

if not json then json = J end
return J
