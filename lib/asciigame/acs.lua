local mty = require'metaty'

--- acs: library for asciicolor sprites loading and coloring.
---
--- [%.acs] files 
local M = mty.mod'asciigame.acs'

local sfmt     = string.format
local push     = mty.from(table, 'insert')
local get, Deq, int = mty.from'ds  get, Deq, int'

function M.load(path)
  local o = {}
  local f, l = assert(io.open(path, 'r')), 0
  local lines = f:lines'l'
  local function iter()
    local ln = lines(); if not ln then return end
    l = l + 1
    return l, ln
  end
  acs.parse(path, iter, function(s) push(o, s) end)
  return o
end


function M.highlight(path, lf, fgFile, bgFile)
  local l = 1
  local function iter()
    local ln = get(lf, l); if not ln then return end
    l = l + 1
    return l-1, ln
  end
  local fl, bl = 0, 0
  local function fw(ln) fgFile:write(ln, '\n'); fl = fl + 1 end
  local function bw(ln) bgFile:write(ln, '\n'); bl = bl + 1 end
  local function catchup(l)
    while fl < l do fw'' end
    while bl < l do bw'' end
  end
  local function recv(sp)
    catchup(sp.l)
    fw'Z'; bw'' -- header is bold
    -- Collect which lines need fg/bg written
    local fg,bg = {}, {}
    for _, aln in ipairs(sp) do
      if aln.fg then
        local ft = '  '..aln.fg..' '
        fg[aln.tl], fg[aln.fl] = ft, ft
      end
      if aln.bg then
        local bt = '  '..aln.bg..' '
        bg[aln.tl], bg[aln.bl] = bt, bt
      end
    end
    -- Write out the fg/bg.
    for l=sp.l+1,sp.le do
      fw(fg[l] or ''); bw(bg[l] or '')
    end
  end
  M.parse(path, iter, recv)
end

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
  'le [int]: end line before next sprite (or EoF)',
}

function M.matchHeader(line)
  local h,w, name = line:match"^#%s*(%d*)x(%d*)%s+(..-)%s*$"
  if not name then return end
  return h~='' and int(h), w~='' and int(w), name
end
local matchHeader = M.matchHeader

--- Match the line for a content line.
function M.matchContent(line) --> ty, default, cnt
  local t,d,c = line:match"^(['<>])(.?)(.*)$"
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
  local lineNum = 0

  local function updateSprite()
    while #txt > 0 do
      push(sprite, AcsLine{
        txt=txt(), fg=fg(), bg=bg(),
        tl=tl(),   fl=fl(), bl=bl(),
        fgDefault=fd(), bgDefault=bd(),
      })
    end
    sprite.le = lineNum-1
    return sprite
  end

  for l, line in iter do
    lineNum = l
    if line:match'^%s*$' then goto cont end
    t, d, cnt = matchContent(line); if t then
      if     t == "'" then txt:push(cnt); tl:push(l);
      elseif t == '>' then  fg:push(cnt); fl:push(l); fd:push(d)
      elseif t == '<' then  bg:push(cnt); bl:push(l); bd:push(d)
      else error'unreachable' end
      goto cont;
    end

    h,w, name = matchHeader(line); if name then
      -- Send sprite we've been building.
      if sprite then send(updateSprite(l)) end
      -- Start next sprite
      sprite = M.AcsSprite{l=l, h=h,w=w, name=name}
      txt:clear(); fg:clear(); bg:clear()
      tl:clear();  fl:clear(); bl:clear()
      goto cont;
    end

    if line:match'^%s*%-%-' then goto cont end
    error(sfmt('%s line %s has invalid acs syntax:\n%q',
      path, l, line))
    ::cont::
  end
  if sprite then send(updateSprite()) end
end

return M
