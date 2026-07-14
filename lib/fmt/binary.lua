#!/usr/bin/env -S lua
local shim = require'shim'
local FMT = '%.2x '

--- Library to format binary text.
---
--- Cmd usage: [$seebin path/to/file.bin]
local M = shim.cmd'fmt.binary' {
  'width [int]: column width in bytes',  width=16,
  'fmt [string]: format string for hex', fmt=FMT,
  'to [file]: file to output to',
  'i [int]: starting index to use', i=0,
}

local mty = require'metaty'
local Fmt = require'fmt'.Fmt

local concat = table.concat
local byte, srep, sfmt = string.byte, string.rep, string.format
local min = math.min

function M.new(T, self)
  self.width = shim.number(self.width)
  self.i     = shim.number(self.i)
  self.to    = shim.file(self.to)
  return shim.constructNew(T, self)
end

function M.format(f, str, fmt)
  fmt = fmt or FMT
  local b
  for i=1,#str do
    b = byte(str, i,i)
    if 32 <= b and b <= 127 then f:write(sfmt(fmt, b))
    else f:styled('literal', sfmt(fmt, b)) end
  end
  f:write''
end
local format = M.format

function M.ascii(f, str)
  for c=1,#str do
    local b = byte(str,c,c)
    if 32 <= b and b <= 127 then f:write(str:sub(c,c))
    else f:styled('empty', ' ') end
  end
end
local ascii = M.ascii

local function formatCols(f, str, fmt, offset)
  f:styled('line', sfmt('% 6i: ', offset));
  format(f, str, fmt)
end

function M.columns(f, str, width, si, fmt)
  fmt, width, si = fmt or FMT, width or 16, si or 0
  local i, len, s = 1, #str
  if len == 0 then return end
  if len <= width then goto last end -- only 1 line
  -- first line
  s = str:sub(i, i+width-1)
  formatCols(f, s, fmt, i+si-1); f:styled('meta', ' | '); ascii(f, s)
  i = i + width
  while i <= len-width do -- middle lines
    s = str:sub(i, i+width-1); f:write'\n'
    formatCols(f, s, fmt, i+si-1); f:styled('meta', ' | '); ascii(f, s)
    i = i + width
  end
  ::last::
  if i <= len then -- last line (with padding)
    if len > width then f:write'\n' end
    s = str:sub(i)
    formatCols(f, s, fmt, i+si-1)
    f:write(srep(' ', #sfmt(fmt, 1) * (width - #s)))
    f:styled('meta', ' | '); ascii(f, s)
  end
  return f
end
local columns = M.columns

--- Simple API to get the concatenated arguments as binary.
function M.bstring(...) --> string
  return concat(columns(Fmt{}, ...))
end

function M:__call()
  assert(#self > 0,
    'fmt.binary: must provide at least one argument')
  local raw = shim.popRaw(self)
  local fmt, width, si = self.fmt, self.width, self.i
  local f = io.fmt
  local read = require'ds.path'.read
  for _, path in ipairs(self) do
    columns(f, (path=='-') and io.stdin:read'a' or read(path), width, si, fmt)
  end
  if #self > 0 then f:write'\n' end
  if raw then
    for _, r in ipairs(raw) do columns(f, r, width, si, fmt) f:write'\n' end
  end
end

if shim.isMain(M) then M:main(arg) end
return M