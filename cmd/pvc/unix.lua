local G = G or _G
--------------------------------
-- Unix Version Control Functions
-- These shell out to unix for functionality instead of using civboot owned
-- algorithms.
local M = G.mod and mod'pvc.unix' or {}

local ix = require'civix'
local pth = require'ds.path'

local push = table.insert
local sfmt = string.format
local trace = require'ds.log'.trace
local info = require'ds.log'.info
local NULL = '/dev/null'

local EMPTY_DIFF = [[
--- %s
+++ %s
@@ -0,0 +0,1 @@
+
]]

local function diffCheckPath(p, pl) --> p, pl
  if not p then return NULL, NULL end
  local st = ix.stat(p); if not st then
    error(p..' is in .pvcpaths but does not exist')
  end
  if st:size() == 0 then error(
    p..' has a size of 0, which patch cannot handle'
  )end
  return p, pl
end

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
--- the [$l] variables are the "label" to use.
--- when the coresponding value is nil then the label is [$/dev/null]
function M.diff(a,al, b,bl) --> string?
  a, al = diffCheckPath(a, al)
  b, bl = diffCheckPath(b, bl)
  local o, e, sh = ix.sh{
    'diff', '-N', a, '--label='..al, b, '--label='..bl,
    unified='0', stderr=ctx.stdlog, rc=true}
  trace('diff rc=%i', sh:rc())
  if sh:rc() > 1 then
    error('diff failed:\n'..(e or o or '(no std err or out)'))
  end
  if o then
    if sh:rc() ~= 1 then error('unknown return code: '..sh:rc()) end
    if o:sub(1,3) ~= '---' then
      error(sfmt('non-diff output from diff %q %q:\n%s\n%s',
                                            al,bl,  o,  e))
    end
    return o
  end
  -- https://stackoverflow.com/questions/44427545]])
  error((a or b)..[[ is empty, which pvc does not support.
Solution: Add a newline (or any other content) to the file,
          or delete the file.]])
end

local function patchArgs(cwd, path)
  return {'patch', '-p0', '-fu', input=pth.abs(path), CWD=cwd}
end

--- forward patch
function M._patch(cwd, path)
  cwd = pth.toDir(cwd)
  local args = patchArgs(cwd, path); push(args, '-N')
  trace('sh%q', args)
  return ix.sh(args) or ''
end

--- reverse patch
function M._rpatch(cwd, path)
  cwd = pth.toDir(cwd)
  local args = patchArgs(cwd, path); push(args, '-R')
  trace('sh%q', args)
  return ix.sh(args)
end

--- incorporate all changes that went into going from base to change into to
function M.merge(to, base, change) --> ok, err
  assert(to, 'must provide to')
  base, change = base or NULL, change or NULL
  trace('merging t:%s b:%s c:%s', to, base, change)
  local cmd = {
    'merge', '-A', to, base, change,
    rc=true,
  }
  info('unix.merge %q', cmd)
  local o, e, sh = ix.sh(cmd)
  trace('merge rc=%i', sh:rc())
  if sh:rc() == 0 then return true end
  return nil, e
end

return M
