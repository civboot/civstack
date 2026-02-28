local G = G or _G

--- Module for applying asciicolor syntax highlighting to parsed pegl.
local M = G.mod and G.mod'pegl.acsyntax' or {}

local mty = require'metaty'
local ds = require'ds'
local lap = require'lap'
local pth = require'ds.path'
local pegl = require'pegl'
local lines = require'lines'
local EdFile = require'lines.EdFile'
local T = require'civtest'

local srep      = mty.from(string, 'rep')
local CODES     = mty.from'asciicolor CODES'
local info      = mty.from'ds.log  info'
local ty        = mty.from(mty,  'ty')
local Token     = mty.from(pegl, 'Token')
local push      = mty.from(ds,   'push')
local pop       = table.remove

local construct = mty.construct
local YIELD_FREQ = 32

--- Usage: [$$
--- hl = require'pegl.lua'.highlighter
--- hl:highlight(lf, fgFile, bgFile)
--- ]$
---
--- The highlighter object determines how to parse and
--- highlight a text file's syntax.
M.Highlighter = mty'Highlighter' {
 [[config [pegl.Config]: the pegl root configuration.
   Typically this should have lenient=true to allow for
   syntax errors to happen but parsing to continue.
 ]],

 [[spec: pegl root spec to parse, aka the grammar tree.
   This should typically be a "lenient" spec with a fallback
   which can parse any symbol.
 ]],

 [[style [table]: a table of name|kind -> 'style' (asciicolor style)
   (name takes precendence).

   The value can be either the style literal or a [$fn(node) -> style].

   The Highlighter will call for each node's kind, if the style isn't
   found it will be called again for all node children.
 ]],

 [[builtin [list]: list of builtin names.]],

  'styleColor {string, string}: table of style -> asciicolor fg/bg',

  'dir [string]: base dir where highlighting is stored',
}

getmetatable(M.Highlighter).__call = function(T, t)
  for _, key in ipairs(t.builtin) do t.builtin[key] = 1 end
  return construct(T, t)
end

--- Usage: [$tokens = tokenize(highlighter, lineFile)][{br}]
--- A state that when called (constructed) is a list of tokens.
M.tokenize = mty'tokenize' {
  'hl   [Highlighter]: highlighter config',
  'p    [pegl.Parser]: the parser',
  'root [pegl.Node]: the root parsed node',
  '_nodeTokens {Token}',
  '_stystack {string}: list of current node style',
  'kind',
}

getmetatable(M.tokenize).__call = function(T, highlighter, lf)
  local self = mty.construct(T, {hl=highlighter})
  self._nodeTokens, self._stystack = {}, {}
  self.root, self.p = pegl.parse(lf, self.hl.spec, self.hl.config)
  self:_dfs(self.root)
  for _, c in ipairs(self.p.comments) do c.style = 'comment' end
  ds.orderedMerge(self._nodeTokens, self.p.comments, self, Token.lte)
  return self
end

local function getKind(node)
  return rawget(node, 'name') or rawget(node, 'kind')
end

--- Perform a depth-first-search on node extracting the tokens.
function M.tokenize:_dfs(node)
  if node == pegl.EMPTY then return end
  local style = self.hl.style
  local sty = style[getKind(node)]
  if sty then push(self._stystack, sty)
  else        sty = ds.last(self._stystack) end
  for _, n in ipairs(node) do
    if ty(n) == Token then
      n.style = n.kind and (style[n.kind] or 'keyword')
             or sty
      push(self._nodeTokens, n)
      if #self._nodeTokens % YIELD_FREQ == 0 then lap.yield(true) end
    else
      self:_dfs(n)
    end
  end
  if style[node.name or node.kind] then
    pop(self._stystack)
  end
end

--- Given the file path to be highlighted, return the configured foreground
--- and background paths.
function M.Highlighter:paths(path) --> fgPath, bgPath
  local path = pth.concat(self.dir, pth.abs(lf:path()))
  return path..'fg', path..'bg'
end

function M.Highlighter:tokenize(lf) --> tokens
  return M.tokenize(self, lf)
end

function M.Highlighter:assertTokens(expect, lf) --> strTokens, tokenize
  local tz = self:tokenize(lf)
  return tz.p:assertNode(expect, tz, self.config), tz
end

--- Highlight output of [$tokenize(lf)] to fg/bg files.
function M.Highlighter:_highlight(tz, fg, bg) --> nil
  local sc = self.styleColor
  local l,c = 1,0
  for i, t in ipairs(tz) do
    if i % YIELD_FREQ == 0 then lap.yield(true) end
    local tc = sc[t.style] or '  '
    local tf = assert(CODES[tc:sub(1,1)])
    local tb = assert(CODES[tc:sub(2,2)])

    -- write empty space before token
    local l1,c1, l2,c2 = t:span()
    if l1 > l then
      fg:write(srep('\n', l1-l))
      bg:write(srep('\n', l1-l))
      l,c = l1,0
    end
    assert(c1 >= c)
    if c1 - c > 1 then
      fg:write(srep(' ', c1-c-1))
      bg:write(srep(' ', c1-c-1))
    end
    if l1 == l2 then -- same line, fill range
      fg:write(srep(tf, c2-c1+1))
      bg:write(srep(tb, c2-c1+1))
    else -- multi-line: write one char each line, fill last.
      fg:write(srep(tf..'\n', l2-l1))
      bg:write(srep(tb..'\n', l2-l1))
      fg:write(srep(tf, c2))
      bg:write(srep(tb, c2))
    end
    l,c = l2,c2
  end
end

--- Write the asciicolor highlight values to [$fgFile] and [$bgFile].
---
--- It is intended that these are read as line-files, where the final character
--- in the line is treated as the "default" for the rest of the line.
function M.Highlighter:highlight(lf, fgFile, bgFile) --> nil
  assert(self.styleColor, 'must set styleColor')
  self:_highlight(self:tokenize(lf), fgFile, bgFile)
end

function M.Highlighter:assertHighlight(str, fgExpect, bgExpect)
  local fg, bg = ds.bytearray(), ds.bytearray()
  self:highlight(lines(str), fg, bg)
  T.eq('FG:\n'..fgExpect, 'FG:\n'..tostring(fg))
  T.eq('BG:\n'..bgExpect, 'BG:\n'..tostring(bg))
end

return M

  -- TODO: this really needs to go somewhere...
  -- if ix.exists(fgPath) and mod == ds.Epoch(ix.stat(fgPath):modified()) then
  --   return fgPath, bgPath, false
  -- end
  -- ix.mkDirs(pth.dir(path))
  -- return fgPath, 
  -- local fgLf = assert(EdFile(fgPath, 'w'))
  -- local bgLf = assert(EdFile(bgPath, 'w'))
  -- fgLf:close(), bgLf:close()
  -- ix.setModified(fgPath, mod)
