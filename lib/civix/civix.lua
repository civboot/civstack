local G = G or _G

--- civix: unix-like OS utilities.
local M = G.mod and G.mod'civix' or {}

local mty  = require'metaty'
local shim = require'shim'
local fmt  = require'fmt'
local ds   = require'ds'
local log  = require'ds.log'
local Iter = require'ds.Iter'
local lap  = require'lap'
local pth  = require'ds.path'

local getmt           = getmetatable
local max             = mty.from'math     max'
local Duration, Epoch = mty.from'ds.time  Duration,Epoch'
local trace, info     = mty.from'ds.log   trace, info'
local Rand            = mty.from'ds.rand  Rand'
local abs             = mty.from'ds.path  abs'
local assertf         = mty.from'fmt      assertf'
local concat, sfmt = table.concat, string.format
local sort = table.sort
local push, pop = table.insert, table.remove
local yield = coroutine.yield
local pc = pth.concat
local construct, ty = mty.construct, mty.ty
local type = type
local check = ds.check
local toDir, toNonDir = pth.toDir, pth.toNonDir
local cmpDirsLast = pth.cmpDirsLast

local lib, fd, fdType, fmodeName, mkdir

--- Several (but not all) functions in this module are used for civ.lua.
--- However, native modules especially cannot be loaded before the
--- bulid system is bootstrapped (at least not easily), so there are
--- a few of these checks for NOLIB in this library which will use
--- civix.B (bootstrap) instead in that case.
---
--- Clients should typically not use civix.B.
M._B = G.mod and G.mod'civix.B' or {}
local B = M._B

B.EEXIST = 17

--- Mostly for bootstrapping. Makes command str quoted if necessary.
local function cmdstr(cmd) --> 'cmd'
  assert(not cmd:find"'",
    "single quote ' not allowed in bootstrapped civix.sh: "..cmd)
  return cmd:find'[^%w_.-/]' and sfmt("'%s'", cmd) or cmd
end

local function assertNilOrTrue(v, msg) --> v
  assert(v == nil or v == true, msg)
  return v
end

B.SH_UNSUPPORTED = {'stdin', 'env', 'cwd'}

local function shError(cmd, out, rc)
  fmt.errorf(
    'Command failed with rc=%s: %q%s', rc, cmd,
    (out and (#out > 0) and ('\nSTDOUT:\n'..out) or ''))
end

-- sh used for bootstrap
function B.sh(cmd) --> fakeSh
  local rcOk
  if type(cmd) == 'table' then
    rcOk = ds.popk(cmd, 'rc')
    local stdout = ds.popk(cmd, 'stdout')
    local bad = ds.updateKeys({}, cmd, B.SH_UNSUPPORTED)
    if next(bad) then error(
        'unsupported argument in bootstrap mode: '
        ..table.concat(ds.keys(bad)))
    end
    if stdout ~= nil then
      assert(stdout == true, 'only supported stdout is true')
    end
    local t = {}; for i, c in ipairs(shim.expand(cmd)) do
      t[i] = cmdstr(c)
    end
    cmd = concat(t, ' ')
  end
  local f = io.popen(cmd, 'r')
  local out, done, why, rc = f:read'*a', f:close()
  if not rcOk and rc ~= 0 then shError(cmd, out, rc) end
  return {out=out, rc=function() return rc end}
end

--- The current operating system in lowercase
--- examples: windows, linux, netbsd, etc.
M.OS = ds.trim(G.OS or os.getenv'OS'
  or (package.config:sub(1,1)=='\\' and 'windows')
  or B.sh'uname'.out:lower())

function B.mkdir(dir)
  dir = abs(dir)
  if B.exists(dir) then return false, M.EEXIST, dir..' exists' end
  local sh_ = B.sh{'mkdir', dir, rc=true}
  local ok = sh_:rc() == 0; if ok then return ok end
  return ok, 'mkdir failed', sh_:rc()
end

function B.rmdir(dir)
  dir = abs(dir)
  local sh_ = B.sh{'rmdir', dir, rc=true}
  local ok = sh_:rc() == 0; if ok then return ok end
  return ok, 'rmdir failed', sh_:rc()
end

local DIR_CMD = 'find %s -maxdepth 1 '
  ..'\\( -type d -printf "%%p/\\n" ,'   -- print dir/
  ..   ' ! -type d -printf "%%p\\n" \\)'
function B.dir(dir) --> iter[entry]
  dir = abs(dir)
  if not pth.isDir(dir) then error('must be a dir/: '..dir) end
  local s = B.sh(sfmt(DIR_CMD, cmdstr(dir:sub(1,-2))))
  if s:rc() ~= 0 then return ds.noop end -- empty iter
  return Iter{ds.split(s.out, '\n')}:map(function(_, p)
    if p == '' or p == dir then return end
    return p:sub(#dir+1),
           pth.isDir(p) and M.DIR or M.FILE
  end)
end

function B.exists(path) --> bool
  return B.sh{'test', '-e', abs(path), rc=true}:rc() == 0
end

function B.pathtype(path)
  path = abs(path)
  if not B.exists(path) then return nil, path..' does not exist' end
  local s = B.sh{'test', '-d', path, rc=true}
  return (s:rc() == 0) and M.DIR or M.FILE
end

if G.NOLIB then
  -- bootstrap mode for "civ.lua".
  fdType = ctx.fileType

  M.EEXIST = B.EEXIST
  M.sh    = B.sh
  M.mkdir  = B.mkdir
  M.rmdir  = B.rmdir
  M.dir    = B.dir
  M.exists = B.exists
  M.pathtype = B.pathtype
else
lib  = require'civix.lib'
fd   = require'fd'
fdType = fd.type
fmodeName = fd.FMODE.name

local l_mkdir, l_dir, l_rmdir, l_exists = mty.from(lib, 
       'mkdir    dir    rmdir    exists')

M.EEXIST = lib.EEXIST
--- make a new directory, the parent must exist.
function M.mkdir(dir) --> ok, errno
   return l_mkdir(abs(dir))
end

--- Stat object with mode() and modified() functions
M.Stat = lib.Stat

--- list entires in directory.
function M.dir(dir) --> iter[e, ftype]
  return l_dir(abs(dir))
end

--- remove empty directory
function M.rmdir(path) --> ok, errmsg, errno
  return l_rmdir(abs(path))
end

--- return whether path exists.
function M.exists(path) --> bool
  return l_exists(abs(path))
end

--- return path type (i.e. M.FILE, M.DIR, etc).
--- if path DNE then return (nil, errmsg).
function M.pathtype(path) --> str?, err
  path = abs(path)
  local stat, err = lib.stat(path)
  if not stat then return nil, err end
  return fmodeName(lib.S_IFMT & stat:mode())
end
end -- END else NOLIB

mkdir = M.mkdir

--- remove file.
function M.rm(path) --> ok, error
  return os.remove(abs(path))
end

ds.update(M, {
  -- file types
  SOCK = "sock", LINK = "link",
  FILE = "file", BLK  = "blk",
  DIR  = "dir",  CHR  = "chr",
  FIFO = "fifo",
})

--- Create a temporary file with a specific prefix, returning the path.
--- The file 
function M.tmpPath(prefix) --> path
  local prefix, p = ctx.TMP_DIR..(prefix or 'lua_'), nil
  while true do
    p = prefix..ctx.rand:string(6)
    if not M.exists(p) then break end
  end
  pth.write(p, '')
  return p
end

--- Block size used as default for file moves/etc
--- Default is 32 KiB
M.BLOCK_SZ = 1 << 15

--- Given a path|File|Stat return a Stat
function M.stat(v) --> Stat?, errmsg?
  if getmetatable(v) == M.Stat then return v end
  if type(v) == 'string'       then return lib.stat(v) end
  return lib.stat(fd.fileno(v))
end

--- return whether two Stats have equal max(changed, modified) time.
function M.statTimeEq(fs1, fs2)
  local s1, ns1 = fs1:time()
  local s2, ns2 = fs2:time()
  return (s1 == s2) and (ns1 == ns2)
end

--- return whether two path|File|Stat have equal max(changed, modified) time.
function M.ftimeEq(a, b)
  return M.statTimeEq(M.stat(a), M.stat(b))
end

function M.mtime(v) return assert(M.stat(v)):modified() end

--- Return the entries in a dir as a list.
--- They are sorted to put the directories first.
function M.ls(dir) --> {str}
  local adir = abs(dir); assertf(M.isDir(adir), '%s is not a dir', dir)
  local d, f = {}, {} -- dirs, files
  for e, ftype in M.dir(adir) do
    if ftype == 'dir' then push(d, pth.toDir(e))
    else                   push(f, e) end
  end
  return ds.extend(ds.sort(d), ds.sort(f))
end

--- Move path from old -> new, throwing an error on failure.
function M.mv(old, new) assert(os.rename(old, new)) end

--- Read data from fd [$from] and write to fd [$to], then flush.
function M.fdWrite(to, from, sz--[[=BLOCK_SZ]]) --> (to, from)
  sz = sz or M.BLOCK_SZ
  while true do
    local b = check(2, from:read(sz)); if not b then break end
    assert(to:write(b))
  end assert(to:flush())
  return to, from
end

--- copy data from [$from] to [$to]. Their types can be either
--- a string (path) or a file descriptor.
function M.cp(from, to)
  if type(from) == 'string' and type(to) == 'string' then
    M.sh{'cp', from, to}
    return
  end
  local fd, fc, td, tc -- f:from, t:to, d:descriptor, c:close
  if type(from) == 'string' then fd = assert(ctx.open(from, 'r')); fc = 1
                            else fd = from end
  if type(to)   == 'string' then td = assert(ctx.open(to, 'w')); tc = 1
                            else td = to end
  M.fdWrite(td, fd)
  if fc then fd:close() end
  if tc then td:close() end
end

--- swap paths a <-> b
function M.swap(a, b, ext)
  ext = ext or '.SWAP'
  M.mv(a, a..ext); M.mv(b, a); M.mv(a..ext, a)
end

--- set the modified time of the path|file
function M.setModified(f, sec, nsec) --> ok, errmsg?
  local close; if type(f) == 'string' then f = ctx.open(f); close = true end
  if ty(sec) == Epoch              then sec, nsec = sec.s, sec.ns    end

  local ok, err = lib.setmodified(fd.fileno(f), sec, nsec)
  if close then f:close() end
  return ok, err
end

--- Change modifiers on f (string or file) using the octal string p.
--- The ocal is in the form UGO where U=user, G=group, O=other.
--- execute=1, write=2, read=4 so: [+
---  * 4 = Read only (r--)
---  * 5 = Read & Execute (r-x) (4 + 1)
---  * 6 = Read & Write (rw-) (4 + 2)
---  * 7 = Read, Write & Execute (rwx) (4 + 2 + 1)
---  * 0 = No permissions (---)
--- ]
--- 
--- You can create your own octal with [$tonumber(s, 8)].
---
--- Use modmod, ormod or andmod for common mod operations.
function M.chmod(f, p)
  if type(p) == 'string' then p = tonumber(p, 8) end
  local close; if type(f) == 'string' then f = ctx.open(f); close = true end
  fd.fchmod(fd.fileno(f), p)
  if close then f:close() end
end

--- Apply [$ix.chmod(f, fn(ix.stat(f):mode(), octal(p)))]
function M.modmod(f, p, fn)
  if type(p) == 'string' then p = tonumber(p, 8) end
  local close; if type(f) == 'string' then f = ctx.open(f); close = true end
  fd.fchmod(fd.fileno(f), fn(ix.stat(fd):mode(), p))
  if close then f:close() end
end

function M.ormod(f, p)  
  return M.modmod(f, p, function(m, p) return m | p end)
end
function M.andmod(f, p)
  return M.modmod(f, p, function(m, p) return m & p end)
end

--- change executable bit.
function M.chx(f, x)
  if x then M.ormod(f,  '111') else M.andmod(f, '666') end
end

-------------------------------------
-- Utility

--- quote the str if it's possible
function M.quote(str)
  if string.find(str, "'") then return nil end
  return "'" .. str .. "'"
end

--- "global" shell settings
M.SH_SET = { debug=false, host=false }

-------------------------------------
-- Time Functions

--- Sleep for the specified duration
function M.sleep(d) --> nil
  if type(d) == 'number' then d = Duration:fromSeconds(d) end
  if d.s >= 0 then lib.nanosleep(d.s, d.ns) end
end
CTX_BASE.sleep = CTX_BASE.sleep or M.sleep

--- Return the Epoch/Mono time
--- Time according to realtime clock
function M.epoch() return Epoch(lib.epoch())   end
--- Duration according to monotomically incrementing clock.
function M.mono() return Duration(lib.mono()) end
function M.monoSec() return M.mono():asSeconds()    end

-------------------------------------
-- Core Filesystem

local function qp(p)
  return assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

--- return if the contents of the two paths are equal.
--- If both are directories return true (do not recurse).
--- If both don't exist return true
function M.pathEq(path1, path2)
  local ty1, ty2 = M.pathtype(path1), M.pathtype(path2)
  if ty1 ~= ty2              then return false end
  if not ty1 or ty1 == 'dir' then return true end
  return pth.read(path1) == pth.read(path2)
end

function M.isFile(path) return M.pathtype(path) == 'file' end
function M.isDir(path) return M.pathtype(path) == 'dir'  end
local isFile = M.isFile

local function _walkcall(ftypeFns, path, ftype, err)
  if err then return ftypeFns.error(path, err) end
  local fn = ftypeFns[ftype] or ftypeFns.default
  if fn then return fn(path, ftype) end
end

local function _walk(base, ftypeFns, maxDepth, depth)
  local err
  if maxDepth and depth >= maxDepth then return end
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then
      ftype, err = M.pathtype(path)
      if not ftype then ftype = 'error' end
    end
    local o = _walkcall(ftypeFns, path, ftype, err)
    if o == true then return end
    if o ~= 'skip' and ftype == 'dir' then
      _walk(path, ftypeFns, maxDepth, depth + 1)
    end
  end
  if ftypeFns.dirDone then ftypeFns.dirDone(base, 'dir') end
end

--- TODO: remove this, use Walk instead.
--- walk the paths up to depth, calling [$$ftypeFns[ftype]]$ for
--- each item encountered.
---
--- If depth is nil/false then the depth is infinite.
---
--- ftypeFns must be a table of ftypes (file, dir) and: [+
---  * default: called as fallback (if missing ftype key)
---  * error: called if determining the type caused an error,
---    typically due to the file not existing.
---    the call is: error(path, errstr)
---  * dirDone: called AFTER the directory has been walked
--- ]
---
--- The Fn signatures are: (path, ftype) -> stopWalk
--- If either return true then the walk is ended immediately
--- If dirFn returns 'skip' then the directory is skipped
function M.walk(paths, ftypeFns, maxDepth)
  for _, path in ipairs(paths) do
    assert('' ~= path, 'empty path')
    local ftype, err = M.pathtype(path)
    _walkcall(ftypeFns, path, ftype, err)
    if ftype == 'dir' then _walk(path, ftypeFns, maxDepth, 0) end
  end
end

--- Walk the directory tree as a iterator of [$path, ftype]. Can walk either a
--- single path [$Walk'path/'] or a list of paths [$Walk{'a/', 'b.txt'}]. [+
--- * Note: all [$ftype=='dir'] paths end in [$/].
--- * Warning: you may want to handle [$ftype=='error']
--- ]
---
--- [*Usage:][{$$ lang=lua}
--- local ix = require'civix'
--- local w = ix.Walk{'path/', 'path2/', 'file.txt'}
--- for path, pathTy in w do
---   if pathTy == 'dir' and path:match'skipMe' do
---     w:skip() -- skips the rest in this directory.
---   end
---   -- ... do something with each path.
--- end
--- ]$
M.Walk = mty'Walk' {
 [[maxDepth [int]: maximum depth to walk (default=infinite).
   A depth of 0 is equivalent to ls (with addition of root node).
 ]],
  'pi [int]: the current (root) path index being walked', pi = 0,
  '_dirs [table]: a stack of WalkDirs that are being walked',
}
getmetatable(M.Walk).__call = function(T, t)
  if type(t) == 'string' then t = {t} end
  t._dirs = {}
  return construct(T, t)
end
---- get the depth of the current directory being walked
function M.Walk:depth() return #self._dirs end
--- skip the current directory level
function M.Walk:skip() pop(self._dirs) end
function M.Walk:__call() --> path, ftype
  local pi = self.pi if pi > #self then return end
  while #self._dirs > 0 do
    local path, err = self._dirs[#self._dirs](self) -- DFS: top of stack
    if path then return path, err end
    pop(self._dirs) -- else _WalkDir is done, pop it.
  end
  pi = pi + 1; self.pi = pi;
  local path = self[pi]; if not path then return end
  local ftype = M.pathtype(path)
  if ftype == 'dir' then path = toDir(path); self:_deeper(path)
  else                   path = toNonDir(path) end
  return path, ftype -- emit the 'root' path
end
--- walk one level deeper by pushing onto _dirs stack.
function M.Walk:_deeper(path)
  if not self.maxDepth or #self._dirs <= self.maxDepth then
    push(self._dirs, M._WalkDir{base=path})
  end
end

--- Walk a single directory
M._WalkDir = mty'_WalkDir' {
  'ftypes [table]: path -> ftype map',
  '_i [int]: current index',
  'base [string]: base directory',
}
getmetatable(M._WalkDir).__call = function(T, t)
  local base, ftypes = t.base, {}
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then ftype = M.pathtype(path) end
    path = (ftype=='dir') and toDir(path) or toNonDir(path)
    push(t, path); ftypes[path] = ftype
  end
  sort(t, cmpDirsLast) -- always return files first
  t._i, t.ftypes = 0, ftypes
  return construct(T, t)
end
function M._WalkDir:__call(walk) --> path, ftype
  local i = self._i; if i >= #self then return end
  i = i + 1; self._i = i
  local path = self[i]; local ftype = self.ftypes[path]
  if i > 0 and ftype == 'dir' then walk:_deeper(path) end
  return path, ftype
end

--- Find the filename path going backwards.
function M.findBack(name, dir) --> path
  dir = dir or ctx.CWD
  while true do
    local path = pth.concat{dir, name}
    if M.exists(path) then return path end
    if dir == '/'       then return      end
    dir = pth.dir(dir)
  end
end

--- recursively copy [$from/] to new [$to/] directory.
function M.cpRecursive(from, to, except)
  assert(M.isDir(from),    'from must be a directory')
  assert(not M.exists(to), 'to must not exist')
  from, to = pth.toDir(from), pth.toDir(to)
  M.mkDirs(to);
  local w = M.Walk{from}
  for fpath, ftype in w do
    local path = fpath:sub(#from+1)
    if except and except[path] then w:skip()
    elseif ftype == 'dir' then M.mkDirs(to..path)
    else                       M.cp(fpath, to..path) end
  end
end

local RM_FNS = {
  dir = ds.noop,
  default = function(p) assert(M.rm(p))    end,
  dirDone = function(p) assert(M.rmdir(p)) end,
}
--- Recursively (force) remove the directory and all children.
--- Throw an error if any fail.
function M.rmRecursive(path)
  if not M.exists(path) then return end
  M.walk({path}, RM_FNS, nil)
end
--- Recursively (force) create the directory and any missing children.
function M.mkDirs(path)
  if type(path) == 'string' then path = pth(path) end
  local dir = ''; for _, c in ipairs(path) do
    dir = pc{dir, c}
    local ok, errno, errmsg = mkdir(dir)
    if ok or (errno == M.EEXIST) then -- directory created or exists
    else fmt.errorf('failed to create directory: %s (%s)', 
                    dir, errmsg) end
  end
end
--- Create a single directory. The parent must exist.
function M.mkDir(path, parents) --!> nil
  if parents then M.mkDirs(pth(path))
  else assertf(mkdir(path), "mkdir failed: %s", path) end
end

--- copy [$from] to [$to], creating the directory structure if necessary.
function M.forceCp(from, to)
  M.rmRecursive(to); M.mkDirs( (pth.last(to)) )
  M.cp(from, to)
end

--- write [$text] to [$path], creating the directory structure if necessary.
function M.forceWrite(path, text)
  M.rm(path); M.mkDirs( (pth.last(path)) )
  pth.write(path, text)
end

--- Force move a file or directory, creating directory structure
--- if necessary.
function M.forceMv(old, new)
  M.mkDirs( (pth.last(new)) )
  M.cp(old, new)
end

--- mkTree(tree) builds a tree of files and dirs at `dir` [+
--- * Dirs  are tables.
--- * Files are string or fd -- which are read+closed.
--- ]
--- Example: [{$$ lang=lua}
--- tree = {
---   a = {
---     ['a1.txt'] = 'stuff in a1.txt',
---     ['a2.txt'] = 'stuff in a.txt',
---     a3 = {
---       ['a4.txt'] = ctx.open'some/file.txt',
---     }
---   }
--- }
--- ]$
---
--- Builds a tree like [$
--- a/a1.txt    # content: stuff in a1.txt
--- a/a2.txt    # content: stuff in a2.txt
--- a/a3/a4.txt # content: stuff in a3.txt
--- ]
function M.mkTree(dir, tree, parents) --!> nil
  M.mkDir(dir, parents)
  for name, v in pairs(tree) do
    local p = pc{dir, name, type(v) == 'table' and '/' or nil}
    if fdType(v) then
      local f = M.fdWrite(assert(io.popen(p, 'w')), v)
      f:close(); v:close()
    elseif type(v) == 'string' then pth.write(p, v)
    elseif type(v) == 'table'  then M.mkTree(p, v)
    else error('invalid tree value of type '..type(v)) end
  end
end

--- civix's implementation of [@lap.Lap], enabling asynchronous file
--- reading/writing and async shell operations using pure lua coroutines.
function M.Lap() return lap.Lap {
  sleepFn=M.sleep, monoFn=M.monoSec, pollList=fd.PollList(),
}end

--- Run a system shell with arguments to override stdout, env, etc.
---
--- [$Sh{'echo', 'foo-bar'}()] or [$Sh'echo foo-bar'()] both create and run
--- (by calling) the 'echo' system command to print 'foo-bar' to stdout.
---
--- You can pipe with e.g. [$( Sh{'echo', 'foo-bar'} | Sh'cat' )()]
--- Note that you must still call [$()] on the final pipe result to run the pipe.
---
--- More complex usage can be done by manually calling [$:start()] and performing
--- the stdout/stdlog reads yourself. If your shell arguments would conflict
--- with field names (e.g. [$env]) you can use Sh:construct to manually construct
--- the object, though note the stdin/input behavior.
M.Sh = mty'Sh' {
  "args [table]: arguments to pass to shell",
  "stdin  [file|bool]: shell's stdin to send  (default=empty)",
  "stdout [file|bool]: shell's stdout         (default=empty)",
  "stderr [file|bool]: shell's stderr         (default=empty)",
  "env   [list]:   shell's environment {'FOO=bar', ...}",
  "cwd   [string]: current working directory",
  'input [string]: string input (set stdin instead)',
  -- After finished
  "out [string]: read of stdout after finished",
  "log [string]: read of stderr after finished",
  -- Private. WARNING: env must outlive the _sh subprocess.
  '_sh [userdata]: internal C implemented shell',
  "_prev [Sh]: used for '|' operation.",
}
M.Sh.construct = mty.construct
getmetatable(M.Sh).__call = function(T, cmd)
  local pk, self = ds.popk, {}
  if type(cmd) == 'string' then cmd = shim.parseStr(cmd)
  else
    cmd = ds.copy(cmd)
    self.stdin  = pk(cmd, 'stdin')
    self.stdout = pk(cmd, 'stdout')
    self.stderr = pk(cmd, 'stderr')
    self.env    = pk(cmd, 'env')
    self.cwd    = pk(cmd, 'cwd')
    if self.env then
      push(self.env, 'PWD='..(self.cwd or ctx.CWD))
    end
  end
  self.args = shim.expand(cmd)
  if type(self.stdin) == 'string' then
    self.stdin, self.input = true, self.stdin
  end
  return T:construct(self)
end

function M.Sh:__fmt(f) f:write'Sh'; f(self.args) end

local function _fnomaybe(f, default)
  if type(f) == 'boolean' then return f end
  return f and fd.fileno(f) or default
end
--- start the shell in the background. Noop if already started or done.
--- Example: [$sh{arg1, arg2, stdin=nostdin, stdout=true, stderr=ctx.stdlog}]
--- ["Note: See Sh for how filedescriptors are set]
function M.Sh:start() --> self
  if self._sh then return self end
  if self._prev then
    assert(not self.stdin);
    self._prev:start(); self.stdin = assert(self._prev.stdout)
  end
  local r, w, l = fd.newFD(), fd.newFD(), fd.newFD()
  local ex, _r, _w, _l = lib.sh(
    self.args[1], self.args, self.env,
    _fnomaybe(self.stdin), _fnomaybe(self.stdout, true),
    _fnomaybe(self.stderr, fd.sys.STDERR_FILENO),
    self.cwd
  )
  self._sh = assert(ex, 'INTERNAL: lib.sh returned nil')
  if _r then r:_setfileno(_r); r:toNonblock() else r = nil end
  if _w then w:_setfileno(_w); w:toNonblock() else w = nil end
  if _l then l:_setfileno(_l); l:toNonblock() else l = nil end
  self.stdin, self.stdout, self.stderr = w, r, l
  return self
end

function M.Sh:isDone() return self._sh:isDone() end
function M.Sh:rc()     return self._sh:rc()     end

--- wait for shell to complete, returns return code
function M.Sh:wait() --> int
  if ctx.ASYNC then
    while not self:isDone() do yield('sleep', 1e-4) end
  else self._sh:wait() end
  return self:rc()
end

function M.Sh:write(...) return self.stdin:write(...) end
function M.Sh:read(...)  return self.stdout:read(...) end

function M.Sh:__bor(cmd) --> Sh
  if not getmt(cmd) then cmd = M.Sh(cmd) end
  assert(not self._sh, 'self already started')
  assert(not cmd._sh,  'cmd already started')
  assert(not cmd._prev, 'cmd already has prev')
  assertNilOrTrue(self.stdout, 'self.stdout misconfigured')
  assertNilOrTrue(cmd.stdin,   'cmd.stdin misconfigured')
  cmd._prev = self
  return cmd
end

--- Writes self.input of first item in pipe.
function M.Sh:_finishInput(fns)
  if self._prev then return self._prev:_finishInput(fns) end
  if self.input then push(fns, function()
    self.stdin:write(self.input); self.stdin:close()
  end) end
end

--- Push fns to finish files (in sh or prev) by writing first input to stdin
--- and reading last (this) stdout/stderr to out/log.[{br}]
--- Note: This does not schedule the fns or wait for any to complete.
function M.Sh:finish(fns) --> self
  self:_finishInput(fns)
  if self.stdout  then push(fns, function() self.out = self.stdout:read'a' end) end
  if self.stderr  then push(fns, function() self.log = self.stderr:read'a' end) end 
  return self
end

--- Finish files (in sh or other) by writing other.input to stdin and reading
--- stdout/stderr. All processes are done asynchronously
function M.Sh:__call(fns) --> self
  fns = fns or {}
  self:start(); self:finish(fns); if #fns == 0 then return self end
  if ctx.ASYNC then ctx.all(fns) else M.Lap():run(fns) end
  return self
end

--- Create and run the Sh command.
M.sh = rawget(M,'sh') or function(cmd) --> out, err, Sh
  trace('sh%q', cmd)
  local rcOk; if type(cmd) == 'table' then rcOk = ds.popk(cmd, 'rc') end
  local sh = M.Sh(cmd)
  sh()
  local out, err = sh.out, sh.log
  local rc = sh:wait();
  if not rcOk and rc ~= 0 then shError(cmd, out, rc) end
  return sh
end

function M.isRoot() return os.getenv'EUID' == '0' end

return M