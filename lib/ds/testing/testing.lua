local G = G or _G
local M = G.mod and mod'ds.testing' or {}
local ds = require'ds'

local T = require'civtest'

function M.testInset(new, assertEq)
  local N, eq, t, rm = new, assertEq or T.eq
  t = N{}; ds.inset(t, 1, {}); eq(N{}, t);

  t = N{1}; ds.inset(t, 1, {}, 1) -- rmlen=1
    eq(N{}, t)

  t = N{1, 3}; ds.inset(t, 2, {2})
    eq(N{1, 2, 3}, t)

  t = N{1, 4, 3}; ds.inset(t, 2, {2}, 1)
    eq(N{1, 2, 3}, t)

  t = N{1, 4, 3}; ds.inset(t, 2, {2}, 2)
    eq(N{1, 2}, t)

  t = N{1, 4, 3}; ds.inset(t, 2, {2, 22}, 2)
    eq(N{1, 2, 22}, t)
end

function M.testInsetStr(new, assertEq)
  local N, eq, t, rm = new, assertEq or T.eq
  t = N{};  ds.inset(t, 1, {})
   eq(N{}, t)

  t = N{'a'}; ds.inset(t, 1, {}, 1) -- rmlen=1
    eq(N{}, t)

  t = N{'a aa', 'ccc'}; ds.inset(t, 2, {'bb bbb'})
    eq(N{'a aa', 'bb bbb', 'ccc'}, t)

  t = N{"ab", "c", "", "d"}; ds.inset(t, 2, {}, 2)
    eq(N{"ab", "d"}, t)

  t = N{'123', '456', '789', 'abc'}
  ds.inset(t, 2, {'444', '555'}, 2)
    eq(N{'123', '444', '555', 'abc'}, t)
end

return M
