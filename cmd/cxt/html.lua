--- Serialize cxt nodes as html
local M = mod and mod'cxt.html' or setmetatable({}, {})

local mty  = require'metaty'
local fmt  = require'fmt'
local pegl = require'pegl'
local cxt  = require'cxt'
local shim = require'shim'
local T = require'civtest'
local push, sfmt = table.insert, string.format
local ds    = require'ds'
local info = require'ds.log'.info
local lines = require'lines'
local LFile = require'lines.File'

local concat = table.concat
local split = ds.split

local function nodeKind(n)
  if type(n) == 'string' or mty.ty(n) == pegl.Token then
    return 'token' end
  if n.block                 then return 'block' end
  if n.code                  then return 'code'  end
  if n.quote                 then return 'quote' end
  if n.table                 then return 'table' end
  if n.list                  then return 'ul'    end
  if n.p                     then return 'p'     end
  if n.br                    then return 'br'    end
end

local preNameAttrs = {'h1', 'h2', 'h3', 'h4', 'h5'}
local fmtAttrs = {'b', 'i', 'u'}
local nodeStart = {
  quote = 'div class=info',
  block = 'div class=code-block',
  code  = 'span class=code',
  table = 'div class=table><table',
}
local nodeEnd = {
  quote = 'div',
  block = 'div',
  code  = 'span',
  table = 'table></div',
}

local function addAttr(attrs, k, v)
  -- TODO: html encode
  push(attrs, sfmt('%s="%s"', k, v))
end

local function addLine(w, line, noNl)
  w.to:write(concat(line), noNl and '' or '\n')
end

local function startFmt(w, n, kind, line)
  for _, f in ipairs(preNameAttrs) do
    if n[f] then push(line, '<'..f..'>') end
  end
  if n.id then
    local id = n.id:gsub('%s+', '-')
    push(line, sfmt('<a id="%s" href="#%s" class=anchor>', id, id))
    if #n == 0 then push(n, n.id) end
  end
  if n.href then
    push(line, '<a ')
    addAttr(line, 'href', n.href)
    push(line, '>')
  end
  if n.path then
    push(line, '<a '); addAttr(line, 'href', w.config.pathUrl(n.path)); push(line, '>')
  end
  for _, f in ipairs(fmtAttrs) do
    if n[f] then push(line, '<'..f..'>') end
  end
end
local function endFmt(n, line)
  for _, f in ds.ireverse(preNameAttrs) do
    if n[f] then push(line, '</'..f..'>') end
  end
  for _, f in ds.ireverse(fmtAttrs) do
    if n[f] then push(line, '</'..f..'>') end
  end
  if n.id   then push(line, '</a>') end
  if n.href then push(line, '</a>') end
  if n.path then push(line, '</a>') end
end
local function startNode(n, kind, line)
  if not kind then return end
  push(line, '<')
  push(line, nodeStart[kind] or kind)
  push(line, '>')
end
local function endNode(n, kind, line)
  if not kind then return end
  push(line, '</')
  push(line, nodeEnd[kind] or kind)
  push(line, '>')
end

local HTML_ENCODE = {
  ['<'] = '&lt;',    ['>']  = '&gt;',  ['&'] = '&amp;',
  ['\n'] = '<br>\n', ['\t'] = '&#9;',
}
function M.htmlEncode(s)
  s = s:gsub('[&<>\n\t]', HTML_ENCODE)
  s = s:gsub('^ ', '&nbsp;'):gsub('\n ', '\n&nbsp;')
       :gsub('  ', ' &nbsp;')
  return s
end

local function _serialize(w, line, node) --> line
  local kind = nodeKind(node)
  if kind == 'token' then
    local s = w:tokenStr(node)
    if s:sub(#s,#s) == '\n' then
      push(line, s:sub(1, #s-1))
      addLine(w, line)
      line = {}
    else push(line, s) end
    return line
  elseif node.hidden  then return line
  elseif kind == 'p'  then addLine(w, line); return {'<p>'}
  elseif kind == 'br' then
    push(line, '<br>'); addLine(w, line)
    return {}
  end
  startFmt(w, node, kind, line)
  startNode(node, kind, line)
  if kind == 'table' then
    w.to:level(1); addLine(w, line)
    for ri, row in ipairs(node) do
      w.to:level(1); addLine(w, {'<tr>'})
      for ci, col in ipairs(row) do
        local el = row.header and 'th' or 'td'
        line = {'<'..el..'>'}
        line = _serialize(w, line, col)
        push(line, '</'..el..'>')
        addLine(w, line, ci == #row)
      end
      w.to:level(-1)
      w.to:write('\n</tr>', ri == #node and '' or '\n')
    end
    line = {}; w.to:level(-1); w.to:write'\n'
  elseif kind == 'ul' then
    w.to:level(1); addLine(w, line)
    for i, item in ipairs(node) do
      line = {'<li>'}
      line = _serialize(w, line, item)
      push(line, '</li>')
      addLine(w, line, i == #node)
    end
    line = {}; w.to:level(-1); w.to:write'\n'
  elseif node.code then
    local s = {}; for _, n in ipairs(node) do push(s, w:tokenStr(n)) end
    s = concat(s)
    if s:sub(1, 1) == '\n' then s = s:sub(2)    end
    if s:sub(-1)   == '\n' then s = s:sub(1,-2) end
    s = M.htmlEncode(s)
    if s:find'\n' then -- multi-line code block
      local lvl = w.to:level(); w.to:level(-lvl)
      push(line, s); addLine(w, line)
      line = {}; w.to:level(lvl)
    else push(line, s) end
  elseif #node == 0 then
    if node.href then line = _serialize(w, line, node.href) end
  else
    for _, sub in ipairs(node) do
      line = _serialize(w, line, sub)
    end
  end
  endNode(node, kind, line); endFmt(node, line)
  return line
end

--- serialize the node to the writer.
function M.serialize(w, node)
  -- line is an implementation detail of html around when to line break.
  -- We want to keep the output html as concise as reasonable, which
  -- this approach helps with.
  local line = {}; for _, n in ipairs(node) do
    line = _serialize(w, line, n)
  end
  if #line > 0 then
    addLine(w, line)
  end
end
function M.serializeDoc(w, node, head)
  addLine(w, {'<!DOCTYPE html>\n<html>'})
  if head then addLine(w, {head}) end
  addLine(w, {'<body><div class=doc>'})
  M.serialize(w, node)
  addLine(w, {'</div></body>\n</html>'})
end

function M.convert(dat, to, config)
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  w.config = config or cxt.Config{}
  M.serializeDoc(w, node, w.config.header)
  return w.to, p, w
end

function M.assertHtml(expectedHtml, cxtDat, dbg)
  local node, p = cxt.parse(cxtDat, dbg)
  local w = cxt.Writer:fromParser(p)
  M.serialize(w, node)
  T.eq(expectedHtml, concat(w.to))
end

return M