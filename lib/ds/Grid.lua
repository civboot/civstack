-- text grid type
local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'

local clear = ds.clear
local max = math.max
local push, concat = table.insert, table.concat
local codes, char, ulen = utf8.codes, utf8.char, utf8.len
local assertf = fmt.assertf

local EMPTY = {}

--- ds.Grid: a text grid
--- Grid is a table (rows/lines) of tables (cols). Each column should contain a
--- single unicode character or nil.
local G = mty'ds.Grid' {
  'h [int]: height', 'w [int]: width',
}
getmetatable(G).__call = function(T, t)
  return mty.construct(T, t):clear()
end

--- clear the grid
function G:clear() --> self
  for l=1,self.h do
    local line = self[l] or {}
    clear(line, 1, max(#line, self.w)); assert(next(line) == nil)
    self[l] = line
  end
  clear(self, self.h + 1, #self)
  return self
end

local function split(s) --> lines
  if type(s) == 'string' then return ds.split(s, '\n')
  else --[[lines]]            return ipairs(s) end
end

--- Insert the str into the Grid.
--- Any newlines will be insert starting at column c.
---
--- This will automatically fill [$$[1,c-1]]$ with spaces, but will
--- NOT clear any data after the insert text, meaning it is essentially a
--- replace.
--- FIXME: considere renaming to replace... or something.
function G:insert(l, c, str) --> self
  for _, sline in split(str) do -- line from string
    local row = self[l]; if not row then return end
    for i=#row+1, c-1 do row[i] = ' ' end -- fill pre-column space
    local lc = c -- unicode column within line
    for _, uchr in codes(sline) do
      row[lc] = char(uchr); lc = lc + 1
    end
    l = l + 1
  end
  return self
end

--- Insert another grid.
function G:insertGrid(l,c, grid) --> self
  for gl, gln in ipairs(grid) do
    local ln = self[gl+l-1]
    for i=#ln+1, c-1 do ln[i] = ' ' end -- fill pre-column space
    for gc, chr in ipairs(gln) do
      assert(ulen(chr) == 1, chr)
      ln[gc+c-1] = chr
    end
  end
  return self
end

function G:__fmt(f)
  local h = self.h; for l=1,h-1 do
    f:write(concat(self[l]), '\n')
  end
  f:write(concat(self[h]))
end

return G
