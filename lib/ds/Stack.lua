local mty = require'metaty'
local ds = require'ds'
local info = mty.from'ds.log  info'
local ty, meq   = mty.from'metaty  ty,eq'

--- A stack of values with history preservation.
---
--- The main value of this vs a list is that pop'd items can be
--- recovered until new items are pushed (by incrementing top up to max).
--- This is very useful for undo/redo stacks/etc.
local Stack = mty.recordMod'ds.Stack' {
  'top [int]: current top index of the stack',
  'max [int]: max index of the stack',
  'newEl  [fn(v) -> e]: element type function, calld for each new element.',
    newEl=ds.iden,
}
getmetatable(Stack).__call = function(T, self)
  assert(not getmetatable(self))
  self.top = self.top or #self
  self.max = self.max or self.top
  return mty.construct(T, self)
end

getmetatable(Stack).__index = mty.hardIndex

local G = mty.G

Stack.get = rawget
Stack.set = rawset
Stack.icopy = ds.defaultICopy

function Stack:__len() return self.top end

--- Push a value onto the stack.
function Stack:push(v) --> el
  v = self.newEl(v)
  self.top = self.top + 1
  self.max = self.top
  self:set(self.top, v)
  return v
end

--- Pop a value from the stack.[{br}]
--- This does not change the max, so the value can still be recovered.
function Stack:pop() --> el
  if self.top < 1 then return end
  self.top = self.top - 1
  return self:get(self.top + 1)
end

function Stack:__eq(oth) --> bool
  if ty(self) ~= ty(oth) or self.max ~= oth.max 
     or self.top ~= oth.top then return false end
  for i=1,self.max do
    if not meq(rawget(self,i), rawget(oth,i)) then return false end
  end
  return true
end

function Stack:__fmt(f)
  f:level(1)
  f:styled('symbol', self.__name .. f.tableStart, '\n')
  f:tableKey'top' f:write' = '; f(self.top); f:write', '
  f:tableKey'max' f:write' = '; f(self.max); f:write'\n'

  f:items(self, false, nil, 1,self.top)
  if self.top < self.max then
    f:write',\n'; f:styled('meta', '-----> top <-----', '\n')
    f:items(self, false, nil, self.top+1,self.max)
  end
  f:level(-1)
  f:write'\n'
  f:styled('symbol', f.tableEnd, '')
end

--- Copy num items into new stack.
--- This preserves all values from top -> max.
function Stack:copy(num)
  local top, max = self.top, self.max
  num = math.min(num or top, top)
  local si = top - num + 1
  local s = table.move(self, si,max, 1, {})
  s.top, s.max = num, num + max - top
  return mty.construct(Stack, s)
end
Stack.__copy = Stack.copy

return Stack
