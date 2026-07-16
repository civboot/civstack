local mty = require'metaty'
--- Example module
local Tm = mty.mod'TestMod'
--- Example function documentation.
function Tm.exampleFn(a) --> b
end
--- Example record documentation.
---
--- Has multiple lines.
Tm.A = mty'A' {
  'a [int]: example field doc',
    a = 'default',
  'b',
}
--- Example method documentation,
--- over multiple initial lines.
---
--- Next paragraph.
function Tm.A:exampleMeth(b) --> c
end

local Tm_DOC =
"[{h3 name=TestMod}Mod TestMod]\
Example module\
\
\
[*Types: ][<#TestMod.A>A] \
\
[*Functions] [+\
* [{*name=TestMod.exampleFn}fn exampleFn][$(a) -> b][{br}]\
  Example function documentation.\
]\
\
[{h4 name=TestMod.A}Record A]\
Example record documentation.\
\
Has multiple lines.\
\
[*Fields:][+\
* [{*name=TestMod.A.a}a] [$=\"default\"]\
  example field doc\
* [{*name=TestMod.A.b}b]\
]\
[*Methods] [+\
* [{*name=A.exampleMeth}fn:exampleMeth][$(b) -> c][{br}]\
  Example method documentation,\
  over multiple initial lines.\
  \
  Next paragraph.\
]\
"

local doc = require'doc'
local T = require'civtest'
local ds = require'ds'

local Dc = doc.Doc

local concat = table.concat

T'find' do
  T.eq(doc,         doc.tryfind'doc')
  T.eq(doc.tryfind, doc.tryfind'doc.tryfind')
end

T'fnsig' do
  local d = Dc{}
  T.eq({'(a) -> b'},       {d:fnsig{'M.a = function(a) --> b'}})
  T.eq({'(a) -> b'},       {d:fnsig{'function M.a(a) --> b'}})
  T.eq({'(a) -> b', true}, {d:fnsig{'function M:a(a) --> b'}})
end

T'stripComments'; do
  T.eq({'hello', 'good bye.'}, doc.stripComments{'--- hello', '--- good bye.'})
  T.eq({'indented is fine'}, doc.stripComments{'   --- indented is fine'})
end

T'extractCode'; do
  local d = Dc{}
  local cmt, code = d:extractCode(doc.find)
  T.eq({'Find the object/name.'},        cmt)
  T.eq({"function doc.find(obj) --> any"}, code)
  T.eq('(obj) -> any', d:fnsig(code))

  local cmt, code = d:extractCode(d.extractCode)
  T.eq({}, cmt)
  T.eq({"function doc.Doc:extractCode(loc) --> (commentLines, codeLines)"},
       code)
  T.eq({"(loc) -> (commentLines, codeLines)", true}, {d:fnsig(code)})

  local cmt, code = d:extractCode(Dc.fnsig)
  T.eq({"function doc.Doc:fnsig(code) --> (string, isMethod)"}, code)
  T.eq({"(code) -> (string, isMethod)", true}, {d:fnsig(code)})
end

T'Doc' do
  local d = Dc{}
  local function testDc(cxt, html)
    T.eq(cxt, concat(d)); ds.clear(d)
    if html then
      error'todo'
    end
  end
  d:link'foo.com';          testDc'[<foo.com>]'
  d:link('foo.com', 'foo'); testDc'[<foo.com>foo]'
  d:code('blah.blah');      testDc'[$blah.blah]'
end

T'mod_doc' do
  local d = Dc{}
  d:mod(Tm)
  T.eq(Tm_DOC, concat(d))
end

T'call_doc'; do
  local b = ds.bytearray()
  doc{require'metaty', to=b}
  T.matches('metaty: simple but effective Lua type system using metatable',
    tostring(b))
end