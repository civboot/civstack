
local T = require'civtest'
local M = require'shim'
local p, ps, e = M.parse, M.parseStr, M.expand

T'parse'; do
  T.eq({'a', 'b', c='42'},  ps'a --c=42 b')
  T.eq({c={'1', '2'}},      ps'--c=1 --c=2')
  T.eq({c={'1', '2', '3'}}, ps'--c=1 --c=2 --c=3')

  T.eq({'-ab', c='foo'}, p{'-ab', '--c=foo'})
  T.eq({'ab', '--', '--bob=1', c='foo'},
            p{'ab', '--c=foo', '--', '--bob=1'})
end

T'parseStr'; do
  T.eq({'a', 'b', c='42'}, ps'a   b --c=42')
  T.eq({c={'1', '2'}},     ps'--c=1   --c=2')
  T.eq({'-ab', c='foo'},   ps'-ab --c=foo')
end

T'expand'; do
  T.eq({'a', 'b', '--c=42'},           e{'a', 'b', c=42})
  T.eq({'a', 'b', '--c=42', '--d=hi'}, e(ps'a b --d=hi --c=42'))
end

T'list'; do
  T.eq({'12'},       M.list('12'))
  T.eq({'12', '34'}, M.list{'12', '34'})
  T.eq({'12 34'},    M.listSplit{'12 34'})
  T.eq({'12', '34'}, M.listSplit'12  \n  34')
  T.eq({'12', '34', '56', '78'},
             M.listSplit'12  \n  34 56 78')
end

T'duck'; do
  T.eq(true, M.boolean(true))
  T.eq(true, M.boolean'true')
  T.eq(true, M.boolean'yes')

  T.eq(false, M.boolean(false))
  T.eq(false, M.boolean'false')
  T.eq(nil, M.boolean(nil))
end

T'cmd' do
  local A = M.cmd'A' { 'a' }
  local v
  function A:__call() v = (self.a or 0) + 1; return self.a end
  T.eq(42, A{a=42})
  T.eq(43, v)
  T.eq('32', A'--a=32')

  function A.new(T, self)
    self.a = M.number(self.a)
    return M.constructNew(T, self)
  end
  T.eq(77, A{a='77'})
end