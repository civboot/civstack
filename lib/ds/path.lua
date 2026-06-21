local G = G or _G

--- working with paths
--- Call directly to convert a list|str to a list of path components.
local M = G.mod and mod'ds.path' or setmetatable({}, {__name='ds.path'})

local mty = require'metaty'
local ds = require'ds'
local push, pop = table.insert, table.remove
local sfmt = string.format
local update = table.update

local extend, splitList = ds.extend, ds.splitList
local clear             = ds.clear

G.DATA_PATH = G.DATA_PATH or os.getenv'DATA_PATH'

--- read file at path or throw error
function M.read(path) --!> string
  local f, err, out = io.open(path, 'r'); if not f then error(sfmt(
    "open %q mode=r: %s", path, err
  ))end
  out, err = f:read'a'; f:close()
  if not out then error(sfmt('read %s: %s', path, err)) end
  return out
end

--- write string to file at path or throw error
function M.write(path, text) --!> nil
  local f, err, out = io.open(path, 'w'); if not f then error(sfmt(
    "open %q mode=w: %s", path, err
  ))end
  out, err = f:write(text); f:close(); assert(out, err)
end

--- append text to path, adds a newline if text doesn't end in one.
function M.append(path, text)
  local f, err, out = io.open(path, 'a'); if not f then error(sfmt(
    "open %q mode=a: %s", path, err
  ))end
  out, err = f:write(text, text:sub(-1) ~= '\n' and '\n' or '')
  f:close(); assert(out, err)
end

getmetatable(M).__call = function(_, p)
  if type(p) == 'table' then return p  end
  if p == ''            then return {} end
  p = splitList(p, '/+')
  if p[1] == ''  then p[1] = '/' end
  local len = #p
  if len > 1 and p[len] == '' then
    p[len - 1] = p[len - 1]..'/'; p[len] = nil
  end
  return p
end

function M.pathenv(var, alt)
  local d = G[var]; if d then return d end
  d = os.getenv(var) or alt and os.getenv(alt)
  if not d then error('no '..var..' path set') end
  d = M.toDir(M.canonical(d)); G[var] = d
  return d
end

-- FIXME: stop setting dir here.
--- get the current working directory
function M.cwd(dir) --> /...cwd/
  if dir then return M.cd(dir)
  else        return M.pathenv('PWD', 'CD') end
end

--- Get path to data in $DATA_PATH
function M.data(relPath)
  local d = assert(G.DATA_PATH, 'must export or set global DATA_PATH')
  if not relPath then return d end
  return M.concat{d, relPath}
end

--- Set the CWD, changing the result of [@ds.cwd].
function M.cd(dir)
  if not M.isDir(dir) then error(dir..' must be a dir/') end
  M.PWD = M.abs(dir)
  return M.PWD
end

--- get the user's home directory
function M.home() return M.pathenv('HOME', 'HOMEDIR') end

--- join a table of path components
function M.concat(t, _) --> string
  assert(not _, 'usage: concat{...}')
  if #t == 0 then return '' end
  local root = (t[1]:sub(1,1)=='/') and '/' or ''
  local dir  = (t[#t]:sub(-1)=='/') and '/' or ''
  local out = {}
  for i, p in ipairs(t) do
    p = string.match(p, '^/*(.-)/*$')
    if p ~= '' then push(out, p) end
  end; return root..table.concat(out, '/')..dir
end

--- return whether a path has any '..' components
function M.hasBacktrack(path) --> bool. path: [str|list]
  if type(path) == 'string' then
    return path:match'^%.%.$' or path:match'^%.%./'
        or path:match'/%.%./' or path:match'/%.%.$'
  end
  for _, c in ipairs(path) do
    if c == '..' then return true end
  end; return false
end
function M.ext(path) --> string. path: [str|list]
  if type(path) == 'table' then path = path[#path] end
  return path:match'.*%.([^/]+)$'
end

--- Ensure the path is absolute, using the wd (default=cwd()) if necessary
---
--- This preserves the type of the input: str -> str; table -> table
function M.abs(path, wd) --> /absolute/path
  if type(path) == 'string' then
    if (path:sub(1,1) == '/') then return path end
    wd = wd or M.cwd()
    return wd..path
  end
  local st = path[1]
  if st and st:sub(1,1) == '/' then return path end
  return extend(M(wd or M.cwd()), path)
end

--- resolve any `..` or `.` path components, making the path
--- /absolute if necessary.
--- The return type is the same as the input type.
function M.resolve(path, wd) --> list|str
  local outTy = type(path)
  if type(path) == 'table' then path = update({}, path)
  else                          path = M(path) end

  -- walk path, resolving . and ..
  local i, j, len, last = 1, 1, #path, path[#path]
  local isdir = last:sub(-1) == '/' or last:match'^/?%.%.?$'
  while j <= len do
    local c = path[j]
    if c == '' or c:match'^/?%./?$'   then j = j + 1 -- '.'  skip
    elseif        c:match'^/?%.%./?$' then           -- '..' backtrack
      i = i - 1; j = j + 1
      if i <= 1 then
        assert(path[1]:sub(-1) ~= '/', '../ backtrack before root')
      end
      if i < 1 then
        local abs = M(wd or M.cwd())
        len = #abs
        table.move(path, j, #path + 1, len, abs)
        i, j      = len, len
        path, len = abs, #abs
      end
    else
      path[i] = path[j]
      i = i + 1; j = j + 1
    end
  end
  clear(path, i, len)
  len = #path; last = path[#path]
  if isdir and last and last:sub(-1) ~= '/' then
    path[len] = last..'/'
  end
  if outTy == 'string' then path = M.concat(path) end
  return path
end

--- Get the canonical path.
--- This is a shortcut for [$resolve(abs(path))].
function M.canonical(path) return M.resolve(M.abs(path)) end

function M.itemeq(a, b) --> boolean: path items are equal
  return a:match'^/*(.-)/*$' == b:match'^/*(.-)/*$'
end

--- ds.rmleft for path components
function M.rmleft(path, rm)
  return ds.rmleft(path, rm, M.itemeq)
end

--- return a nice path (string) that is resolved and readable.
---
--- It's 'nice' because it has no '/../' or '/./' elements
--- and has CWD stripped.
function M.nice(path, wd) --> string
  wd = wd or M.cwd()
  path, wd = M.resolve(M(path), wd), M(wd)
  M.rmleft(path, wd)
  if #path == 0 or path[1] == '' then path[1] = './' end
  return M.concat(path)
end

--- Return the nice path but always keep either / or ./
--- at the start.
function M.small(path, wd)
  path = M.nice(path)
  return path:find'^%.?/' and path or ('./'..path)
end

--- Return only the parent dir and final item.
--- This is often used for documentation/etc
function M.short(path, wd)
  return M.nice(path, wd):match'([^/]*/[^/]+)'
end

--- [$first/middle/last -> ("first", "middle/last")]
function M.first(path)
  if path:sub(1,1) == '/' then return '/', path:sub(2) end
  local a, b = path:match('^(.-)/(.*)$')
  if not a or a == '' or b == '' then return path, '' end
  return a, b
end

--- [$first/middle/last -> ("first/middle/", "last")]
function M.last(path)
  local a, b = path:match('^(.*/)(.+)$')
  if not a or b == '' then
    if path:sub(1,1) ~= '/' then a = './' end
    return a, path
  end
  return a, b
end

--- Get the directory of the path or nil if it is root.
function M.dir(path)
  if path == '/' then return end
  return path:match'^(.*/)(.+)$' or './'
end

--- return whether the path looks like a dir.
--- Note: civstack tries to make all ftype='dir' paths end in '/'
---   but other libraries or APIs may not conform to this.
function M.isDir(path) return path:sub(-1) == '/' end
local isDir = M.isDir
function M.toDir(path) --> path/
  return (path:sub(-1) ~= '/') and (path..'/') or path
end

function M.toNonDir(path) --> path (without ending /)
  return (path:sub(-1) == '/') and path:sub(1,-2) or path
end

--- return the relative path needed to get from [$from] to [$to].
---
--- Note: this ignores (pops) the last item in [$from] if it's not a dir/.
---
--- For example
--- T.eq(relative('/foo/bar',  '/foo/baz/bob'), 'baz/bob')
--- T.eq(relative('/foo/bar/', '/foo/baz/bob'), '../baz/bob')
function M.relative(from, to, wd)
  local inpTy = type(from)
  from, to = M.abs(M(from), wd), M.abs(M(to), wd) -- make abspath lists
  assert(from[1] == to[1] and from[1] == '/', 'not abs paths')
  if not M.isDir(from[#from]) then pop(from) end
  local rel = {}
  -- find index they have shared root (si=shared index)
  local si=1; for i=2,#from do
    si = i
    if M.toDir(from[i]) ~= M.toDir(to[i]) then
      si=i-1; break
    end
  end
  for _=si+1,#from do push(rel, '..')  end -- get from down to same root
  for i=si+1,#to   do push(rel, to[i]) end -- push remaing to path
  return inpTy == 'string' and M.concat(rel) or rel
end

--- path comparison function for [$table.sort] that sorts
--- dirs last, else alphabetically.
function M.cmpDirsLast(a, b)
  if isDir(a) then
    if isDir(b) then return a < b end
    return false
  elseif isDir(b) then return true end
  return a < b
end

return M
