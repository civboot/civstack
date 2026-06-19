-- asciicolor: encode text color and style with a single ascii character
local M = mod and mod'asciicolor' or {}

local shim = require'shim'
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local pth = require'ds.path'
local civix = require'civix'

local construct, newindex = mty.construct, mty.newindex
local sfmt, srep = string.format, string.rep

M.CONFIG_PATH = '.config/colors.luck'

--- typosafe mapping of asciicode -> fullname
---
--- [" Note: These map to the available colors in a VT100 terminal emulator,
---    See the vt100 module for that implementation]
M.Color = ds.TypoSafe{
  z = 'zero', [' '] = 'zero', [''] = 'zero', -- aka default.

  --  (dark)           (light)
  b = 'black',         w = 'white',
  d = 'darkgrey',      l = 'lightgrey',
  r = 'red',           p = 'pink',
  y = 'yellow',        h = 'honey',
  g = 'green',         t = 'tea',
  c = 'cyan',          a = 'aqua',
  n = 'navy',          s = 'sky', -- blue
  m = 'magenta',       f = 'fuschia',
}

--- typosafe mapping of fullname -> asciichar
M.Ascii = mod and mod'Ascii' or {}
for k, v in pairs(M.Color) do M.Ascii[v] = k end
M.Ascii.zero = 'z' -- hardocde as there are 3 possibilities

--- makes [$' '] and [$''] both convert to [$'z']
--- as well as check that the ascii code is valid.
local CODES = {}; do
  for k in pairs(M.Color) do CODES[k] = k end
  local UC = {}; for k in pairs(M.Color) do
    CODES[k:upper()] = k:upper()
  end
  CODES['z'] = 'z'; CODES[' '] = 'z'; CODES[''] = 'z'
  CODES['Z'] = 'Z'
end
M.CODES = CODES

function M.assertcode(ac) --> single leter (or error)
  return CODES[ac] or error(sfmt('invalid ascii color: %q', ac))
end

--- Dark mode styles (defaults)
M.dark = {
  bg = 'b',

  none = '',

  -- Find tools (i.e. ff)
  path  = 'm',  -- file/dir path
  match = 'Bf', -- search match
  line  = 'ld', -- line number / etc
  meta  = 'd',  -- Meta=metadata such as description of ops, etc
  info  = 'bl', -- info box, i.e. editor overlay.
  -- TODO: rename notice
  notify = 'C', -- make very visible
  good   = 'G',
  error  = 'Wr', warn  = 'Y',
  debug  = 'A',
  base   = 'F', basel   = 'Wf', -- base(line),   aka removed text
  change = 'G', changel = 'Wg', -- change(line), aka added text
  empty  = 'zd',
  ref    = 'cZ',

  -- Document Styles
  code = 'hb',
  bold = 'Z', ul = 'zZ', boldul = 'ZZ',
  h1 = 'N', h2 = 'S', h3 = 'W', h4 = 'Z',

  -- Code Syntax
  api           = 'G', -- api, i.e. public function/class name
  type          = 'h', -- type signature
  var           = 'G', -- variable name
  keyword       = 'R', -- for while do etc
  symbol        = 'A', -- = + . { } etc
  builtin       = 'p', -- builtin fns/mods/names: io sys self etc
  comment       = 'f', -- content of comment:  /*content*/
  stringbox     = 'd', -- start/end of string: '' "" [[]] etc
  string        = 'g', -- content of string inside quotes
  key           = 'T', -- key in map/struct/etc
  char          = 'g', -- single character: 'c'
  num           = 'N', -- float or integer: 0 1.0 0xFF etc
  literal       = 'h', -- other literal: null, bool, date, regex, etc
  call          = 'c', -- function call: foo()
  dispatch      = 'C', -- object.method called: obj.foo(), obj:foo()
}

--- Sub-style for "bars", used in applications (like editor)
--- to create sub-styles.
M.dark.bar = {
  fg = 'b', bg = 'w', -- foreground/background overrides
  meta = 'lw',
  line = 'nw',
}

-- Reverse any white fg items, preserving bold.
for k, v in pairs(M.dark) do
  if type(v) == 'string' then
    if     'w' == v:sub(1,1) then M.dark.bar[k] = 'bw'
    elseif 'W' == v:sub(1,1) then M.dark.bar[k] = 'Bw' end
  end
end

-- TODO: light-mode styles

function M.mode() return G.CLIMODE or os.getenv'CLIMODE' end

function M.stylePath() return pth.concat{pth.home(), CONFIG_PATH} end

function M.loadStyle(mode, path)
  mode = mode or M.mode() or 'dark'
  path = (path == true) and M.stylePath() or path
  local style = M[mode] or error('styles not found: '..mode)
  if path and civix.isFile(path) then
    -- log.info('loading style from %s', path)
    -- local cfg = require'luck'.load(path, {MODE = mode})
    -- return ds.update(table.update({}, style), cfg)
  end
  return style
end

--- Create a styler
---
--- Note: pass f (file) to create the default AcWriter with the file.
--- Note: pass mode, stylepath to control loadStyle
M.Styler = mty'Styler' {
  'acwriter [AcWriter]',
  "style [table]: default=loadStyle() in Fmt", style=M.dark,
}

M.Styler.__tostring = function() return 'Styler{...}' end

M.Styler.level = function(st, add) return st.acwriter.f:level(add) end
M.Styler.flush = function(st) return st.acwriter:flush() end

--- Get the style's fb (foreground + background asciicolor bytes)
M.Styler.getFB = function(st, style) --> fb
  style = style or 'zz'
  local sub, subSty = style:match'(%w+):(%w+)'
  if sub then
    style = subSty
    sub = st.style[sub];   if not sub then goto getstyle end
    local fb = sub[style]; if fb      then return fb     end
    -- not explicitly defined, use the default background
    fb = (st.style[style] or 'z'):sub(1,1)
    if     CODES[fb] == 'z' then fb = sub.fg or 'z'
    elseif CODES[fb] == 'Z' then fb = (sub.fg or 'Z'):upper() end
    return fb..(assert(sub.bg))
  end
  ::getstyle::
  return st.style[style] or 'zz'
end

--- Example: st:styled('path', 'path/to/foo.txt', '\n')
M.Styler.styled = function(st, style, str, ...)
  local len, fb = #str, st:getFB(style)
  return st.acwriter:acwrite(
    fb:sub(1,1):rep(len), fb:sub(2,2):rep(len),
    str, ...)
end

--- write as plain
M.Styler.write = function(st, ...)
  return st.acwriter:acwrite(nil, nil, ...)
end

M.Styler.__newindex = function(st, k, v)
  if type(k) ~= 'number' then return newindex(st, k, v) end
  assert(k == 1, 'cannot push non 1')
  st.acwriter:write(v)
end


--- Setup standard formatters (io.fmt and io.user).
function M.setup(to, user)
  io.fmt  = M.Fmt{to=to   or io.stderr}
  io.user = M.Fmt{to=user or io.stdout}
end

return M
