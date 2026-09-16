local iotype = ctx.fileType

local IFile = require'ds.IFile'
local G = require'metaty'.G
local T   = require'civtest'
local ds = require'ds'
local ix = require'civix'
local info = require'ds.log'.info

local fin = false
local function generalTest()

-- Note: most test coverage is in things that
-- use IFile (i.e. U3File).
T'IFile'; do
  local fi = IFile:create(1)
  fi:set(1, 'a'); fi:set(2, 'b'); fi:set(3, 'c')
  T.eq(3, #fi)
  T.eq('a', fi:get(1))
  T.eq('b', fi:get(2))
  T.eq('c', fi:get(3))
  T.eq(nil, fi:get(4))
end

fin=true; end -- generalTest

generalTest();
if G.NOLIB then return end

-----------
-- Tests with fd.

local fd   = require'fd'

T.SUBNAME = '[ioStd]'
fin=false; generalTest(); assert(fin)

T.SUBNAME = '[ioSync]'; ctx:push(fd.CTX_IO_SYNC)
fin=false; generalTest(); assert(fin)
T.eq(fd.CTX_IO_SYNC, ctx:pop())

T.SUBNAME = ''