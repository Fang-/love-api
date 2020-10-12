
local warnings = true
local outfile = 'love.d.tl'

local function warn(...)
  if warnings then print(...) end
end

--  api & lookup tables
--

local api = require('love_api')

local types = {}
local function gatherTypes(module, tys)
  for _,t in ipairs(tys) do
    if types[t.name] then
      print('woah, overwrite!', t.name)
      os.exit()
    end
    t.module = module
    types[t.name] = t
  end
end

gatherTypes('', api.types)
for _,m in ipairs(api.modules) do
  gatherTypes(m.name, m.enums)
  gatherTypes(m.name, m.types)
end

--  rendering primitives
--

local depth = 0

local function indent()
  depth = depth + 1
end

local function undent(levels)
  depth = (depth or 1) - 1
end

io.output(io.open(outfile, 'w+'))

local function write(text)
  io.write(string.rep('  ', depth) .. text)
end

local function line(text)
  write((text or '') .. '\n')
end

local function cap(s)
  return string.gsub(s, "(%a)([%w_']*)",
    function (h,t) return h:upper()..t:lower() end
  )
end

--  teal definition rendering
--

local function constructType(type)
  --TODO  handle type.name == '...' variadics
  --      but api is inconsistent about representing these!

  --  unions
  local mi, mj = type.type:find(' or ');
  if mi ~= nil then
    local first = type.type:sub(0, mi-1)
    local second = type.type:sub(mj+1)
    type.type = first
    local head = constructType(type)
    type.type = second
    return head .. ' | ' .. constructType(type)

  --  love2d types
  elseif types[type.type] then
    local module = types[type.type].module
    if module == '' then return type.type end
    return cap(module) .. '.' .. type.type

  --  records
  elseif type.type == 'table' then
    if type.table ~= nil then
      --TODO  inline records, or what?
      warn('skipping table data for', type.name)
      return 'table'
    else
      warn('no table data for', type.name)
      return 'table'
    end

  --  userdata
  elseif type.type == 'light userdata'
      or type.type == 'cdata' then
    return 'any'  --TODO  but teal docs say userdata is supported type?

  --  lua types
  elseif type.type == 'nil'
      or type.type == 'number'
      or type.type == 'string'
      or type.type == 'boolean'
      or type.type == 'function'
      or type.type == 'any' then
    return type.type
  elseif type.type == 'Variant'
      or type.type == 'any' then
    return 'any'

  --  ambiguous
  elseif type.type == 'value' then
    warn('api definition imprecise for', type.name)
    return 'any'
  else
    warn('unexpected or undefined type', type.type)
    return type.type
  end
end

local function func(fable)
  for _,f in ipairs(fable.variants) do
    --  arguments
    local args = ''
    for _,a in ipairs(f.arguments or {}) do
      if args ~= '' then args = args .. ', ' end
      args = args .. constructType(a)
    end

    --  product
    local res = ''
    if f.returns then
      for _,r in ipairs(f.returns) do
        if res ~= '' then res = res .. ', ' end
        res = res .. constructType(r)
      end
      if #f.returns > 1 then
        res = ': (' .. res .. ')'
      else
        res = ': ' .. res
      end
    end

    --  write
    line(fable.name .. ': function(' .. args .. ')' .. res)
  end
end

local function type(type)
  line('record ' .. type.name)
  indent()
    --TODO  include supertypes?
    for _,f in ipairs(type.functions) do
      func(f)
    end
  undent()
  line('end')
end

local function enum(enum)
  line('enum ' .. enum.name)
  indent()
  for _,c in ipairs(enum.constants) do
    local e = c.name:gsub('\\', '\\\\'):gsub("'", "\\'");
    line("'" .. e .. "'")
  end
  undent()
  line('end')
end

local function moduleBody(m)
  if m.enums and #m.enums > 0 then
    line('--  enums')
    for _,e in ipairs(m.enums) do
      enum(e)
    end
    line()
  end

  if m.types and #m.types > 0 then
    line('--  types')
    for _,t in ipairs(m.types) do
      type(t)
    end
    line()
  end

  if m.functions and #m.functions > 0 then
    line('--  functions')
    for _,f in ipairs(m.functions) do
      func(f)
    end
  end
end


-- render file
--

line('--  love: love2d type definitions')
line('--  this file was auto-generated!\n')

for _,m in ipairs(api.modules) do
  line('local record ' .. cap(m.name))
  indent()
  moduleBody(m)
  undent()
  line('end')
  line()
end

line('local record Love')
indent()

moduleBody(api)

line()
line('--  callbacks')
for _,callback in ipairs(api.callbacks) do
  func(callback)
end
line()

line('--  modules')
for _,m in ipairs(api.modules) do
  line(m.name .. ': ' .. cap(m.name))
end

undent()
write([[
end

return Love
]])

io.close()
print('done, written to ' .. outfile)
