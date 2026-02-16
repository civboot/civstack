local M     = require'pegl.acsyntax'
local T     = require'civtest'
local mty   = require'metaty'
local ds    = require'ds'
local lines = require'lines'
local ac    = require'asciicolor'
local pegl     = require'pegl'
local pegl_lua = require'pegl.lua'

local s, bytearray = mty.from(ds, 'simplestr,bytearray')
local KW, N = mty.from(pegl.testing, 'KW,N')

local hl = pegl_lua.highlighter
hl.styleColor = ac.dark

local function Tk(...) return pegl.Token:encode(nil, ...)        end
local function tokenize(str) return hl:tokenize(lines(str)) end

T'tokens'; do
  -- no comments
  hl:assertTokens({N'x', KW'=', '1'}, [[x = 1]])
  -- with comments and style
  local _, tz = hl:assertTokens(
    {"-- comment 1", KW'local', N'x', KW'=', '1', "-- comment 2"},
    s[[
      -- comment 1
      local x = 1 -- comment 2
    ]])
  T.eq(Tk(1,1, 1,12,   nil,     'comment'), tz[1])
  T.eq(Tk(2,1, 2,5,    'local', 'keyword'), tz[2])
  T.eq(Tk(2,7, 2,7,    'name',  'none'),    tz[3])
  T.eq(Tk(2,9, 2,9,    '=',     'symbol'),  tz[4])
  T.eq(Tk(2,11, 2,11,  nil,     'num'),     tz[5])

  local fg,bg = bytearray(), bytearray()
  hl:_highlight(tz, fg,bg)
  T.eq(s[[
  ffffffffffff
  RRRRR z A N ffffffffffff]]
  , tostring(fg))

  hl:assertTokens({N's', {kind='singleStr', "'str'"}}, [[s'str']])
end

T'color'; do
  hl:assertHighlight(
[[
function foo()
  return 'foo'
end
]],
"RRRRRRRR zzzRR\
  RRRRRR ggggg\
RRR",
"zzzzzzzz zzzzz\
  zzzzzz zzzzz\
zzz")
end

