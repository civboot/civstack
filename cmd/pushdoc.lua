#!/usr/bin/env -S lua
local shim = require'shim'

--- Small script to build and push docs from civ.
--- Eventually some of this logic may be moved to the doc.lua library.
--- For now, this is effectively a builtin-build step.
local M =  shim.cmd'pushdoc' {
  __cmd = 'pushdoc',
  'readme [string]: main README.cxt',
    readme='README.cxt',
  'pat [string]: documentation pattern to push.', 
    pat={'civ:.#doc_.'},
  'config [string]: path to civ.core.Config',
  'dir [string]: output directory',
  'clean [bool]', clean = false,
}

local core = require'civ.core'
local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local info = require'ds.log'.info
local ix = require'civix'
local civ = require'civ'
local cxt = require'cxt'
local doc = require'doc'

local sfmt = string.format
local push = ds.push

M.config = core.DEFAULT_CONFIG

local HEAD = [[
<head>
  <meta charset="utf-8">
  <title>Civboot</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="%s">
</head>
]]

local LUA_NAV = [[
<nav>
  <ul>
    <a href="../index.html"   class="nav"             >civ/</a>
    <a href="index.html"      class="nav nav-selected">lua/</a>
  </ul>
</nav>
]]

local ROOT_NAV = [[
<nav>
  <ul>
    <a href="index.html"   class="nav nav-selected">civ/</a>
    <a href="lua/index.html" class="nav"           >lua/</a>
  </ul>
</nav>
]]

local function export(cxtFile, htmlFile, header)
  local to = assert(io.open(htmlFile, 'w'))
  to:write(header); to:write'\n'
  return cxt.html { cxtFile, to=to }
end

function M:__call()
  local D = pth.abs(pth.toDir(self.dir))
  io.fmt:write('pushdoc to ', D, '\n')
  local luaDir = D..'lua/'
  self.pat = shim.list(self.pat)
  ix.mkDirs(luaDir)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  local tgtnames = cv:expandAll(self.pat)
  local header = HEAD:format('../styles.css')..LUA_NAV
  local nav = {}
  civ._build(self, cv, tgtnames)
  for _, tgtname in ipairs(tgtnames) do
    info('pushdoc %q', tgtname)
    local tgt = cv:target(tgtname)
    local nameCxt = ds.only(tgt.out.doc.lua)
    local name = assert(nameCxt:gsub('(%.cxt)$', ''))
    push(nav, name)
    export(
      cv.cfg.buildDir..'doc/lua/'..nameCxt,
      luaDir..name..'.html',
      header
    )
  end
  local indexPath = cv.cfg.buildDir..'doc/lua/index.cxt'
  local f = io.open(indexPath, 'w')
  f:write'[+\n'
  for _, n in ipairs(ds.sort(nav)) do
    f:write(sfmt('* [<%s>%s]\n', n..'.html', n))
  end
  f:write']\n'; f:flush(); f:close()
  export(indexPath, luaDir..'index.html', header)
  if self.readme then
    export(self.readme, D..'index.html',
           HEAD:format('styles.css')..ROOT_NAV)
  end
end

print('@@ pushdoc', shim.isMain(M))
if shim.isMain(M) then M:main(G.arg) end
return M