local mty = require'metaty'

--- Simple random number generation.
--- This also automatically registers [$ctx.rand] if not already set.
local M = mty.mod'ds.rand'

local int           = mty.from'ds  int'
local tconcat, push = mty.from(table, 'concat insert')
local char = string.char

--- Random number generator using the Linear Congruential Generator
--- forumla. This should not be used for security-critical applications.
---
--- Example: [{$$ lang=lua}
--- local ix = require'civix'
--- local r = Rand{state = ix.epoch():asMs()
--- r(1, 100) -- get a number from [1-100]
--- ]$
---
M.Rand = mty'Rand' {
  -- FIXME: rename seed.
  'state [int]: current state, override to set seed.', state = 0,
  'm [int]', m = 0xF0000000,
  'a [int]', a = 1103515245,
  'c [int]', c = 12345,
}
getmetatable(M.Rand).__call = function(T, self)
  if type(self) ~= 'table' then self = {state = self} end
  self.state = self.state or math.random(0, math.maxinteger)
  return mty.construct(T, self)
end

--- Advance to the next state and get the new state.
function M.Rand:next() --> int
  local s = int(self.a * self.state + self.c) % self.m
  self.state = s
  return s
end

local BYTE_a, BYTE_z = string.byte'a', string.byte'z'
function M.Rand:string(len)
  local r, t = self:next(), {}
  while #t < len do
    push(t, char(BYTE_a + (r % 26)))
    r = r // 26 -- shift by base 26
    if r == 0 then r = self:next() end
  end
  return tconcat(t)
end

--- Get a random number between [$$[min, max]]$
function M.Rand:__call(min, max) --> int[min,max]
  return min + (self:next() % (max - min + 1))
end

CTX_BASE.rand = CTX_BASE.rand or M.Rand{state = math.random(0, math.maxinteger)}

return M