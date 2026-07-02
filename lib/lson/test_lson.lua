
local T = require'civtest'
local M = require'lson'
local mty = require'metaty'
local ds  = require'ds'
local pod = require'pod'
local lines = require'lines'

local Tm = mod'Tm'

local function testString(encoded, decoded)
  local de = mty.construct(M.De, {l=1, c=1, line=encoded})
  T.eq(decoded, M._deString(de))
end
T'string'; do
  testString([["example string"]],     [[example string]])
  testString([["example \"string\""]], [[example "string"]])
end

T'skipWs'; do
  local de = M.De(lines'  a\n  b')
  de:skipWs(); T.eq('a', de.line:sub(de.c,de.c))
  de.c = de.c + 1
  de:skipWs(); T.eq('b', de.line:sub(de.c,de.c))
end

local function ltest(t, enc, expectEncoding, P)
  enc = enc or M.Json{}
  enc(t, P)
  local encoded = table.concat(enc)
  if expectEncoding then
    T.eq(expectEncoding, encoded)
  end
  local de = M.De(lines(encoded))
  print(encoded)
  local decoded = de(P)
  T.eq(t, decoded)
  return enc, de
end

T'lax'; do
  T.eq({1, 2},   M.decode'[1 2]')
  T.eq({a=2, 1}, M.decode'{1:1 "a":2}')
  T.throws('1.4: missing pattern ":"',
    function() M.decode'{1 "a":2}' end)
end

T'bytes'; do
  T.eq('abc',     M.decode '|abc|')
  T.eq('a\nc',    M.decode '|a\\nc|')
  T.eq('a\\nc',   M.decode[[|a\\nc|]])
  T.eq('a\\nc |', M.decode[[|a\\nc \||  ]])
end

T'round'; do
  local L = M.Lson
  ltest({1, 2, 3},       nil,  '[1,2,3]')
  ltest({1, 2, 3},       L{},  '[1 2 3]')
  ltest({'a', 'b', 'c'}, nil,  '["a","b","c"]')
  ltest({'a', 'b', 'c'}, L{},  '[|a| |b| |c|]')

  ltest({1, a=2},       nil,  '{"a":2,1:1}')
  ltest({1, a=2},       L{},  '{|a|:2 1:1}')

  ltest({1, a={3,4}},   nil,  '{"a":[3,4],1:1}')
  ltest({1, a={3,4}},   L{},  '{|a|:[3 4] 1:1}')

  ltest({1, a={b=3,4}}, nil,  '{"a":{"b":3,1:4},1:1}')
  ltest('abc',          nil,  '"abc"')
  ltest('abc',          L{},  '|abc|')

  ltest('hi\n\there',   nil,  '"hi\\n\\there"')
  ltest('hi\n\there',   L{},  '|hi\\n\there|')

  ltest('hi\\th|ere',    nil,  [["hi\\th|ere"]])
  ltest('hi\\th|ere',    L{},  [[|hi\th\|ere|]])

  ltest('hello "happy bob"', nil,  [["hello \"happy bob\""]])
  ltest('hello "happy bob"', L{},  [[|hello "happy bob"|]])

  ltest([[\p \s]],    nil, [["\\p \\s"]])
  ltest([[\p \s \n]], L{}, [[|\p \s \\n|]])

  ltest(true,              nil,  'true')
  ltest(ds.none,           nil,  'null')
  ltest({[ds.none]=false}, nil, '{null:false}')

end

T'lson_pod'; do
  Tm.A = mty'A' { 'a1 [builtin]', 'a2 [Tm.A]', 'ls {str}' }
  T.eq(Tm.A, pod(Tm.A))
  local a = Tm.A{ a1='hi'}
  ltest(a, nil, [[{"a1":"hi"}]], Tm.A)
  a = Tm.A{a1={key='bye'}}
  ltest(a, nil, [[{"a1":{"key":"bye"}}]], Tm.A)
  a.a1, a.ls = nil, {'a', 'b'}
  ltest(a, nil, [[{"ls":["a","b"]}]], Tm.A)

  ltest({
      a=Tm.A{a1='a1value'}
    }, nil,
    [[{"a":{"a1":"a1value"}}]],
    pod.Map{K=pod.str, V=Tm.A})

end

T'lson_run_testing_pod'; do
  local tp = require'pod.testing'
  local encLson = function(v, P) return table.concat(Lson{}(v, P)) end
  local encJson = function(v, P) return table.concat(Json{}(v, P)) end
  tp.testAll(M.lson, M.decode)
  tp.testAll(M.json, M.decode)
end
