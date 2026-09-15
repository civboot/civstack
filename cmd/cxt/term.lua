G = G or _G
--- cxt for the terminal, either plain text or vt100/etc
local M = mod'cxt.term'
MAIN = G.MAIN or M

local mty  = require'metaty'
local ds = require'ds'
local shim = require'shim'
local pegl = require'pegl'
local cxt  = require'cxt'
local fd = require'fd'
local log = require'ds.log'
local lines = require'lines'
local LFile = require'lines.File'

local Token = assert(require'pegl'.Token)
local push = table.insert

--- Render cxt on a terminal.
---
--- Will render an input string or --inp=file.
M.Args = mty'Args' {
  'inp  [path|file]: input file',
  'out  [path|file]: output file (default=stdout)',
}

local KIND_ORDER = ds.BiMap {
  'hidden', 
  'table', 'list', 'quote',

  'h1', 'h2', 'h3', 'h4',
  'p', 'br', 'code', 'block', 'name', 'path', 'clone',
  'b', 'u', 'class',
}

M.STYLES = {
  h1 = 'h1', h2 = 'h2', h3 = 'h3', h4 = 'h4',
  code = 'code', block = 'code', path = 'path',
  clone = 'var', name = 'api',
  b = 'bold', u='ul',
}

M.HEADER = {h1=40, h2=20, h3=5, h4=1}

local function nodeKind(n)
  if type(n) == 'string' or mty.ty(n) == Token then
    return 'token'
  end
  for _, o in ipairs(KIND_ORDER) do
    if n[o] then return o end
  end
end

local function serializeRow(w, row, nl)
  w:level(1); if nl then w.to:write'\n' end
  w:level(1);
  for i, col in ipairs(row) do
    if i ~= 1 then w.to:write'\t' end
    M.serialize(w, col)
  end
  w:level(-1); w:level(-1)
end

local SER_KIND = {
  hidden = ds.noop,
  token = function(w, node) w.to:write(w:tokenStr(node)) end,
  p     = function(w, node) w.to:write'\n'               end,
  br    = function(w, node) w.to:write'\n'               end,
  table = function(w, node)
    if #node == 0 then return end
    w:level(1)
    for r, row in ipairs(node) do
      w.to:write'\n+ '
      for c, col in ipairs(row) do
        if c ~= 1 then w.to:write'\t' end
        w:level(1); M.serialize(w, col); w:level(-1)
      end
    end
    w:level(-1)
  end,
  list = function(w, node)
    w:level(1)
    for _, item in ipairs(node) do
      w.to:write'\n* '
      w:level(1); M.serialize(w, item); w:level(-1)
    end
    w:level(-1)
  end,
  code = function(w, node)
    local s = {}; for _, n in ipairs(node) do push(s, w:tokenStr(n)) end
    s = table.concat(s)
    if node.block and s:sub(-1) == '\n' then
      s = s:sub(1, -2) -- strip extra newline
    end
    w.to:styled('code', s, '')
  end,
}
SER_KIND.block = SER_KIND.code

-- Handle a special type of node.
local function special(w, node, style, str)
  -- If the text would be the same, simply write w/style.
  if #node == 1 and w:eqStr(node[1], str) then
    w.to:styled(style, str, '')
  else -- else, write and include styled metadata
    for _, n in ipairs(node) do M.serialize(w, n) end
    w.to:styled('meta', '[')
    w.to:styled(style, str)
    w.to:styled('meta', ']', '')
  end
end

-- serialize node to a writer
function M.serialize(w, node)
  local kind = nodeKind(node)
  local fn = SER_KIND[kind]
  if fn then return fn(w, node) end
  local header = M.HEADER[kind]
  if header then
    w.to:styled('meta', string.rep('#', header))
    if header > 4 then
      w.to:styled('meta', '\n#', ' ')
    else w.to:write' ' end
  end

  if     node.path then special(w, node, 'path', node.path)
  elseif node.href then special(w, node, 'ref',  node.href)
  else
    for _, n in ipairs(node) do M.serialize(w, n) end
  end
end

function M.convert(dat, to)
  if type(dat) == 'string' then dat = lines(dat) end
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  M.serialize(w, node)
  return w, node, p
end

function M.main(args)
  args = M.Args(shim.parseStr(args))
  args.out = args.out or ctx.fmtlog
  if #args > 0    then args.inp = lines(table.concat(args, ' '))
  elseif args.inp then args.inp = LFile:create(shim.file(args.inp))
  else error'must provide input' end
  M.convert(args.inp, args.out)
  args.out:write'\n'
  return args.out
end
getmetatable(M).__call = function(_, ...) return M.main(...) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M
