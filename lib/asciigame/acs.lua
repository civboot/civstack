local mty = require'metaty'

--- acs: library for asciicolor sprites loading and coloring.
---
--- [%.acs] files 
local M = mty.mod'asciigame.acs'

local sfmt = string.format
local Deq, int = mty.from'ds  Deq, int'

--- A parsed line of AcsSprite with the information about where it is from.
M.AcsLine = mty'AcsLine' {
  'txt [str]: the text',
  'fg [str]: the foreground',
  'bg [str]: the background',
  'fgDefault [str]: the default fg',
  'bgDefault [str]: the default bg',

  'tl [int]: the text line number',
  'bl [int]: the bg line number',
  'fl [int]: the fg line number',
}
local AcsLine = M.AcsLine

--- A fully parsed sprite, which is a list of lines.
M.AcsSprite = mty'AcsSprite' {
  'name [str]: the name of the sprite',
  'h [int]: height', 'w [int]: width',
  'l [int]: line number of header',
}

function M.matchHeader(line)
  local h,w, name = line:match"^#%s*(%d*)x(%d*)%s+(..-)%s*$"
  if not h then return end
  if h ~= '' then h,w = int(h), int(w)
  else h,w = nil, nil end
  return h,w, name
end
local matchHeader = M.matchHeader

--- Match the line for a content line.
function M.matchContent(line) --> ty, default, cnt
  local t,d,c = line:match"^['<>](.?)(.*)$"
  if d == '' then d = ' ' end
  return t,d,c
end
local matchContent = M.matchContent

--- Read line and line-num from iter(), sending completed lines via send.
---
--- [$send()] receieves [$AcsLine] objects.
function M.parse(path, iter, send)
  local sprite, h,w, name, t, d, cnt
  local txt, fg, bg = Deq{}, Deq{}, Deq{}
  local tl,  fl, bl = Deq{}, Deq{}, Deq{}
  local      fd, bd = Deq{}, Deq{}, Deq{}
  local function updateSprite(force)
    while #txt > 0 and (force or (#fg > 0 and #bg > 0)) do
      push(sprite, AcsLine{
        txt=txt(), fg=fg(), bg=bg(),
        tl=tl(),   fl=fl(), bl=bl(),
        fgDefault=fd(), bgDefault=bd(),
      })
    end
    return sprite
  end

  for l, line in iter do
    t, d, cnt = matchContent(line); if t then
      if     t == "'" then txt:push(cnt); ti:push(l); td:push(d)
      elseif t == '>' then  fg:push(cnt); fi:push(l); fd:push(d)
      elseif t == '<' then  bg:push(cnt); bi:push(l); bd:push(d)
      else error'unreachable' end
      goto cont;
    end

    h,w, name = matchHeader(line); if name then
      -- Send sprite we've been building.
      if sprite then send(updateSprite(true)) end
      -- Start next sprite
      sprite = M.AcsSprite{h=h,w=w, name=name}
      txt:clear(); fg:clear(); bg:clear()
      ti:clear();  fi:clear(); bi:clear()
      goto cont;
    end

    if line:match'^%s*%-%-' then goto cont end
    error(sfmt('%s line %s has invalid acs syntax:\n%q',
      path, l, line))
    ::cont::
  end
  if sprite then send(updateSprite(true)) end
end

return M
