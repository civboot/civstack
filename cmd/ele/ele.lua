#!/usr/bin/env -S lua
local shim = require'shim'

--- Usage: [$ele path/to/file.txt][{br}]
--- The ele commandline editor.
local ele = shim.cmd'ele' {
  'run [str]: lua module to call at start',
}

local mty = require'metaty'
local lap = require'lap'
local fd = require'fd'
local ds = require'ds'
local pth = require'ds.path'
local log = require'ds.log'
local ac = require'asciicolor'
local vt = require'vt100'
local ix = require'civix'
local lson = require'lson'
local et = require'ele.types'

local ioopen = ctx.open
local info = log.info
local iostdout, iostderr = ctx.stdout, ctx.stdlog
local sysprint = G.print

local byte = mty.from(string, 'byte')

local ELE_STATE = '/tmp/'..ctx.CWD:gsub('/', '_')
                ..'_elestate.lson'

function ele:__call()
  local savedmode
  info('ele exe', self)
  local s = require'ele.Session':user{}
  if #self == 0 and ix.exists(ELE_STATE) then
    info('loading ele state from %s', ELE_STATE)
    s.ed:loadState(lson.load(ELE_STATE, et.State))
    assert(s.ed:namedBuffer'nav')
  end
  local keysend = s.keys:sender()
  local rawKeyRecv = lap.Recv()
  local rawKeySend = rawKeyRecv:sender()
  local iofmt   = ctx.fmtlog

  local l = require'civix'.Lap{}:run(
  function() -- setup terminal and kickoff ele coroutines
    s.ed.display = vt.Term{
      fd=ctx.stdout,
      styler=ac.Styler{style=ac.loadStyle()},
    }
    ctx.stdout = nil
    G.print = ds.eprint
    info'ele: started display'
    s:handleEvents()
    lap.schedule(function() while s.ed.run do
      rawKeySend(byte(ctx.read(1)))
    end end)
    lap.schedule(function()
      LAP_TRACE[coroutine.running()] = true
      info'start term:input()'
      while s.ed.run do
        local ok, err = ds.try(s.ed.display.input, s.ed.display, keysend, rawKeyRecv)
        (ok and info or log.error)('display.input exited with: %s', err)
      end
      info'exit term:input()'
    end)
    lap.schedule(function()
      s:draw()
    end)
    lap.schedule(function()
      info'ele: start highlight'
      s:highlight()
    end)
    info'ele: started'
    if #self > 0 then
      for _, path in ipairs(self) do
        info('arg path: %q', path)
        s.ed:buffer(path)
      end
      s.ed:focus(self[1])
    else
      info('saving ele state to %s', ELE_STATE)
      lap.schedule(function() while s.ed.run do
        lap.sleep(1)
        pth.write(ELE_STATE, lson.lson(s.ed:state(), true))
      end end)
    end
    if self.run then
      info('ele --run=%q', self.run)
      require(self.run)(s.ed)
      s.ed.redraw = true
    end
    info'ele: end of setup'
  end,
  function() lap.async() -- setup: change to async()
    ctx.stdlog = assert(ioopen('/tmp/ele.err', 'w'))
    ctx.fmtlog = require'vt100'.Fmt{to=ctx.stdlog}
    savedmode = vt.start()

    fd.ioAsync()
    fd.stdin:toNonblock()
    fd.stdout:toNonblock()
  end,
  function() lap.sync() -- teardown: change to sync()
    fd.stdout:toBlock()
    fd.stdin:toBlock()
    fd.ioSync()

    vt.stop(ctx.stdout, savedmode)
    ctx.stdlog = iostderr
    ctx.fmtlog    = iofmt
  end)
  return s, l
end

if shim.isMain(ele) then ele:main(arg) end
return ele