local mty = require'metaty'

--- Ele game library.
local M = mty.mod'ele.game'

local G = mty.G
local types = require'ele.types'
local push = mty.from(table, 'push')
local getmt = G.getmetatable

--- A Game window which renders a list of sprites.
M.Game = mty.extend(types.BasePane, 'Game', {
 [[sprites {asciigame.Sprite}: list of sprites to render.
   sprites are written first -> last (last wins).]],
  'mh [int]: minimum height', 'mw: minimum width',
})

getmt(M.Game).__call = function(T, t)
  t.sprites = t.sprites or {}
  return getmt(types.BasePane).__call(T, t)
end

function M.Game:draw(ed, isRight)
  local d = ed.display
  local tl, tc = self.tl, self.tc
  local txt, fg, bg = d.text, d.fg, d.bg
  if self.th < self.mh then return txt:insert(tl,tc, 'height too low') end
  if self.tw < self.mw then return txt:insert(tl,tc, 'width too low')  end

  for _, s in ipairs(self.sprites) do
    local l, c = tl + s.l - 1, tc + s.c - 1
    if s.txt then txt:insert(l,c, s.txt) end
    if s.fg  then  fg:insert(l,c, s.fg)  end
    if s.bg  then  bg:insert(l,c, s.bg)  end
  end
end

return M
