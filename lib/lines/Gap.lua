local mty = require'metaty'

--- Line-based gap buffer. The buffer is composed of two lists (stacks) of
--- lines [+
--- (1) The "bot" (aka bottom) contains line 1 -> curLine.
---     curLine is at #bot. Data gets added to bot.
--- (2) The "top" buffer is used to store data in lines
---     after "bot" (aka after curLine). If the cursor is
---     moved to a previous line then data is moved from top to bot
--- ]
---
--- ["Gap gives a file-like write API which may not be the most performant
---   for some workloads (writing single characters)]
local Gap = mty.recordMod'Gap' {
  'top[table]: array of lines on the top (near start).',
  'bot[table]: array of lines on the bottom (near end).',
  'path [string]: the path this was read from or nil.',
  'readonly [bool]: whether to throw errors on write.'
}

local ds, lines  = require'ds', require'lines'
local pth = require'ds.path'
local lload = lines.load
local largs = lines._args
local span = lines.span

local push, pop, concat = table.insert, table.remove, table.concat
local move              = table.move
local sub = string.sub
local max = math.max
local getmt = getmetatable

local EMPTY = {}

getmetatable(Gap).__call = function(T, t, path)
  return mty.construct(T, {
    bot=(type(t) == 'string') and lines(t) or t or {},
    top={}, path=path
  })
end

Gap.flush = ds.noop
Gap.close = ds.noop
--- Make a copy of the gap to a lua list.
function Gap:icopy() --> list
  local b = self.bot
  local o = move(b, 1, #b, 1, {})
  local t = self.top
  for i=#t, 1, -1 do push(o, t[i]) end
  return o
end

function Gap:reader() --> Gap
  return mty.construct(getmetatable(self), {
    bot=ds.copy(self.bot),
    top=ds.copy(self.top),
    path=self.path,
  })
end

--- Load gap from file, which can be a path.
--- returns [$nil, err] on error
Gap.load = function(T, f, close) --> Gap?, err?
  if type(f) == 'string' then f = pth.abs(f) end
  local dat, err = lload(f, close)
  if not dat then dat = {} end
  return T(dat, type(f) == 'string' and f or nil)
end

function Gap:__len() return #self.bot + #self.top end
--- Get a specific line index.
function Gap:get(l) --> string
  local bl = #self.bot
  if l <= bl then return self.bot[l]
  else            return self.top[#self.top - (l - bl) + 1] end
end
--- FIXME: I need to delete this!
function Gap:__index(l)
  if type(l) ~= 'number' then return getmetatable(self)[l] end
  return self:get(l)
end

function Gap:__fmt(f)
  local len = #self
  for i, l in ipairs(self.bot) do
    f:write(l); if i < len then f:write'\n' end
  end
  for i=#self.top,1,-1 do
    f:write(self.top[i]); if i > 1 then f:write'\n' end
  end
end
Gap.__pairs = ipairs

--------------------------
-- Mutations

--- Set a specific line index with the value.
function Gap:set(l, v)
  assert(not self.readonly, 'attempt to write to readonly Gap')
  assert(l <= #self + 1, 'can only set at len+1')
  self:setGap(l); self.bot[l] = v
end
Gap.__newindex = Gap.set

--- See ds.inset for documentation.
function Gap:inset(i, values, rmlen) --> rm?
  assert(not self.readonly, 'attempt to write to readonly Gap')
  values, rmlen = values or EMPTY, rmlen or 0
  self:setGap(max(0, i + rmlen - 1))
  move(values, 1, max(#values, rmlen), i, self.bot)
end

--- Extend gap with the lines.
function Gap:extend(lns) --> self
  assert(not self.readonly, 'attempt to write to readonly Gap')
  self:setGap(#self); local bot = self.bot
  move(lns, 1, #lns, #bot + 1, bot)
  return self
end

--- set the gap to the line number, making [$l == #g.bot].
function Gap:setGap(l)
  local bot, top = self.bot, self.top
  local blen = #bot
  l = l or (blen + #self.top)
  assert(l >= 0)
  if l == blen then return end -- do nothing
  if l < blen then
    while l < #bot do
      local v = pop(bot); if nil == v then break end
      push(top, v)
    end
  else -- l > #self.bot
    while l > #bot do
      local v = pop(top); if nil == v then break end
      push(bot, v)
    end
  end
end

function Gap:write(...)
  assert(not self.readonly, 'attempt to write to readonly Gap')
  local t = largs(...)
  local len = #t; if len == 0 then return end
  self:setGap()
  local bot = self.bot; local blen = #bot
  if blen == 0 then bot[1] = t[1]
  else              bot[blen] = bot[blen]..t[1] end
  for i=2, #t do push(bot, t[i]) end
end

Gap.dumpf = lines.dump

return Gap
