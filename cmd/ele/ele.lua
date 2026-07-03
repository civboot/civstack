#!/usr/bin/env -S lua
local shim = require'shim'

--- Usage: [$ele path/to/file.txt][{br}]
--- The ele commandline editor.
local ele = shim.cmd'ele' {
  'run [str]: lua module to call at start',
}

local lap = require'lap'
local fd = require'fd'
local ds = require'ds'
local pth = require'ds.path'
local info = require'ds.log'.info
local ac = require'asciicolor'
local vt = require'vt100'
local ix = require'civix'
local lson = require'lson'
local et = require'ele.types'

local ioopen = io.open
local iostdout, iostderr = io.stdout, io.stderr
local sysprint = G.print

local ELE_STATE = '/tmp/'..pth.cwd():gsub('/', '_')
                ..'_elestate.lson'

function ele:__call()
  local savedmode
  info('ele exe', self)
  local s = require'ele.Session':user{}
  if #self == 0 and ix.exists(ELE_STATE) then
    info('loading ele state from %s', ELE_STATE)
    s.ed:loadState(lson.load(ELE_STATE, et.State))
  end
  local keysend = s.keys:sender()
  local iofmt   = io.fmt

  local l = require'civix'.Lap{}:run(
  function() -- setup terminal and kickoff ele coroutines
    s.ed.display = vt.Term{
      fd=io.stdout,
      styler=ac.Styler{style=ac.loadStyle()},
    }
    io.stdout = nil
    G.print = ds.eprint
    info'ele: started display'
    s:handleEvents()
    lap.schedule(function()
      LAP_TRACE[coroutine.running()] = true
      info'start term:input()'
      s.ed.display:input(keysend)
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
    io.stderr = assert(ioopen('/tmp/ele.err', 'w'))
    io.fmt = require'vt100'.Fmt{to=io.stderr}
    savedmode = vt.start()

    fd.ioAsync()
    fd.stdin:toNonblock()
    fd.stdout:toNonblock()
  end,
  function() lap.sync() -- teardown: change to sync()
    fd.stdout:toBlock()
    fd.stdin:toBlock()
    fd.ioSync()

    vt.stop(io.stdout, savedmode)
    io.stderr = iostderr
    io.fmt    = iofmt
  end)
  return s, l
end

if shim.isMain(ele) then ele:main(arg) end
return ele
