local T = require'civtest'

T'Rand'; do
  -- Unseeded rand is deterministic.
  local r = require'asciigame.Rand'{}
  T.eq({1,1,36},  {r(1,1), r(1,1), r(1,100)})
  T.eq({1,6,1},   {r(1,10), r(1,10), r(1,10)})
  T.eq({916,841}, {r(1,1000), r(1,1000)})
end
