#!/usr/bin/env -S lua
local shim = require'shim'

--- Usage: [$civgame typo][{br}]
--- Ele extension which comprise a set of games for learning civstack.
local civgame = shim.cmd'civgame' {}

--- Ele action to execute when [$ele run civgame ...] is called.
function civgame.ELE(eleEd, ev)
end

if shim.isMain(ele) then require'ele'{run='civgame'} end

return civgame
