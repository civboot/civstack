local mty = require'metaty'

local int = mty.from'ds  int'

--- Random number generator using the Linear Congruential Generator
--- forumla. This should not be used for security-critical applications.
---
--- Example: [{$$ lang=lua}
--- local ix = require'civix'
--- local r = Rand{state = ix.epoch():asMs()
--- r(1, 100) -- get a number from [1-100]
--- ]$
---
local Rand = mty.recordMod'Rand' {
  'state [int]: current state, override to set seed.', state = 0,
  'm [int]', m = 0xF0000000,
  'a [int]', a = 1103515245,
  'c [int]', c = 12345,
}

--- Advance to the next state and get the new state.
function Rand:next() --> int
  local s = int(self.a * self.state + self.c) % self.m
  self.state = s
  return s
end

--- Get a random number between [$$[min, max]]$
function Rand:__call(min, max) --> int[min,max]
  return min + (self:next() % (max - min + 1))
end

return Rand
