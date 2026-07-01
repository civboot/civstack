local mty = require'metaty'
local T = require'civtest'
local ds = require'ds'
local I = require'ds.Iter'
local lines = require'lines'
local acs = require'asciigame.acs'

local push               = mty.from(table, 'insert')
local s, bytearray       = mty.from'ds  simplestr, bytearray'
local AcsSprite, AcsLine = mty.from(acs, 'AcsSprite, AcsLine')

T'Rand'; do
  -- Unseeded rand is deterministic.
  local r = require'asciigame.Rand'{}
  T.eq({1,1,36},  {r(1,1), r(1,1), r(1,100)})
  T.eq({1,6,1},   {r(1,10), r(1,10), r(1,10)})
  T.eq({916,841}, {r(1,1000), r(1,1000)})
end

T'acs'; do
  local mh = acs.matchHeader
  T.eq({3    ,3,     'man'},       {mh'# 3x3  man'})
  T.eq({3    ,false, 'man'},       {mh'# 3x  man'})
  T.eq({false,false, 'man o man'}, {mh'# x man o man '})
  T.eq(nil,                         mh'< foo')

  local mc = acs.matchContent
  T.eq(nil,                      mc"# x header")
  T.eq({"'", ' ', 'some text'}, {mc"' some text"})
  T.eq({"'", ' ', ''},          {mc"'"})

  local function p(text)
    local o = {}
    acs.parse(ds.srcloc(1), I:ofList(lines(text)), function(s)
      push(o, s)
    end)
    return o
  end

  local expect = {
    AcsSprite{
      name="sprite",
      l=2, le=10, h=3,w=3,
      AcsLine{
        txt="some text", fg="some fg", bg="some bg",
        fgDefault=" ", bgDefault=" ",
        tl=3, bl=4, fl=5
      }, AcsLine{
        txt="more text", fg="more fg", bg=nil,
        fgDefault=" ",
        tl=6, fl=8, bl=nil
      }, AcsLine{
        txt="last text", fg="last fg", bg=nil,
        fgDefault=" ",
        tl=7, fl=9, bl=nil
      },
    },
    AcsSprite {
      name='small', l=11, le=12, h=false,w=false,
      AcsLine{txt='little', tl=12},
    },
  }
  local txt = s[[
  -- comment
  # 3x3 sprite
  ' some text
  < some bg
  > some fg
  ' more text
  ' last text
  > more fg
  > last fg

  # x small
  ' little
  ]]
  T.eq(expect, p(txt))
  local fg, bg = bytearray(), bytearray()
  acs.highlight(ds.srcloc(), lines(txt), fg, bg)

  T.eq('', tostring(fg))

end
