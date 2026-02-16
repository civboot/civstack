local G = G or _G

--- Lua syntax in PEGL
---
--- http://parrot.github.io/parrot-docs0/0.4.7/html/languages/lua/doc/lua51.bnf.html
--- was used as a reference.
local M = G.mod and G.mod'pegl.lua' or {}

local mty = require'metaty'
local ds  = require'ds'
local add, sfmt = table.insert, string.format
local get = ds.get
local pegl = require'pegl'

local Key,
      Pat, Or, Not, Many, Maybe,
      Token, Empty, Eof, PIN, UNPIN,
      EMPTY, common
  = mty.from(pegl, [[
      Key,
      Pat, Or, Not, Many, Maybe,
      Token, Empty, Eof, PIN, UNPIN,
      EMPTY, common
]])
local num = Or{name='num', common.base16, common.base10}

local stmt = Or{name='stmt'}

local KEYWORDS = {
  'end', 'if', 'else', 'elseif', 'while', 'do', 'repeat', 'local', 'until',
  'then', 'function', 'return',
}
local keyW           = Key{name='keyword',       KEYWORDS}
local name           = {UNPIN, Not{keyW}, common.name}
local methname = ds.copy(name)
methname.name = 'methname'

-- uniary and binary operations
local op1 = Key{kind='op1', {'-', 'not', '#'}}
local op2 = Key{kind='op2', {
  -- standard binops
  '+', '-', '*', '^', '%', 'and', 'or',
  ['='] = {'='}, ['~'] = {'='}, --  ==  ~=
  ['/'] = {true, '/'},          --  /   //
  ['.'] = {true, '.'},          --  .   ..
  ['<'] = {true, '='},          --  <   <=
  ['>'] = {true, '='},          --  >   >=
}}

-----------------
-- Expression (exp)

-- We do exp a little different from the BNF. We create an `exp1` which is a
-- non-operated expression and then have `exp` implement a list of expression
-- operations.
--
-- The BNF uses a (confusing IMO) recursive definition which weaves
-- exp with var and prefixexp. Our definition deviates significantly because
-- you cannot do non-progressive recursion in recursive-descent (or PEG):
-- recursion is fine ONLY if you make "progress" (attempt to parse some tokens)
-- before you recurse.
--
-- exp1 ::=  nil       |  false      |  true       |  ...        |
--           Number    | unop exp    | String      | tbl         |
--           function  | name

local exp1 = Or{name='exp1', Key{{'nil', 'false', 'true'}}, Pat'%.%.%.', num}
add(exp1, {op1, exp1})

local exp = {name='exp'}    -- defined just below
add(exp1, {'(', exp, ')', kind='group'})

local call     = Or{kind='call'} -- function call (defined much later)
local methcall = {UNPIN, ':', methname, PIN, call, kind='methcall'}
local index    = {kind='index',
  UNPIN, '[', Not{Or{'[', '='}}, PIN, exp, ']'
}
local postexp  = Or{name='postexp', methcall, index, call}
ds.extend(exp, {exp1, Many{ Or{postexp, {name='op2exp', op2, exp}} }})

-- laststat ::= return [explist1]  |  break
-- block    ::= {stat [`;´]} [laststat[`;´]]
local explist  = Maybe{exp, Many{',', exp}}
local return_ = {'return', explist, kind='return'}
local laststmt = Or{name='laststmt', return_, 'break'}
local block = {name='block',
  Many{stmt, Maybe(';')},
  Maybe{laststmt, Maybe(';')}
}

M.unexpectedKeyW  = Key{name='unexpectedKey', KEYWORDS}
M.unexpectedGroup = Key{name='unexpectedGroup', {'(', ')', '{', '}', '[', ']'}}
M.unexpectedToken = Pat{name='unexpectedToken', '%S+'}

M.lenient = Or{
  stmt, ';',
  laststmt,
  M.unexpectedKeyW, M.unexpectedGroup, M.unexpectedToken,
}
M.lenientBlock = Many{M.lenient}

-----------------
-- String (+exp1)
local function quoteImpl(p, char, pat, kind)
  p:skipEmpty()
  local l, c = p.l, p.c
  if not p:consume(char) then return end
  while true do
    local c1, c2 = p.line:find(pat, p.c)
    if c2 then
      p.c = c2 + 1
      local bs = string.match(p.line:sub(c1, c2), pat)
      if ds.isEven(#bs) then
        return Token:encode(p, l, c, p.l, c2, kind)
      end
    else
      if p.line:sub(#p.line) ~= '\\' then
        return p:error("Expected "..kind..", reached end of line")
      end
      p:incLine()
      if p:isEof() then return p:error("Expected "..kind..", reached EOF") end
    end
  end
end

local function singleStr(p) return quoteImpl(p, "'", "(\\*)'", 'singleStr') end
local function doubleStr(p) return quoteImpl(p, '"', '(\\*)"', 'doubleStr') end

local function bracketStrImpl(p)
  local l, c = p.l, p.c
  local start = p:consume('%[=*%['); if not start then return end
  local _, cs, _, cs2 = start:span()
  local pat = '%]'..string.rep('=', cs2 - cs - 1)..'%]'
  l, c = p.l, p.c
  while true do
    local c2, ce = p.line:find(pat, p.c) if c2 then
      local t = {kind='bracketStr', start,
        Token:encode(p, l,   c,  p.l, c2-1),
        Token:encode(p, p.l, c2, p.l, ce),
      }; p.c = ce + 1
      return t
    else
      p:incLine()
      if p:isEof() then return p:error(
        "Expected closing "..pat:gsub('%%', '')..", reached EOF"
      )end
    end
  end
end
local function bracketStr(p)
  p:skipEmpty()
  return bracketStrImpl(p)
end
local str = Or{name='str', singleStr, doubleStr, bracketStr}
add(exp1, str)


-----------------
-- Table (+exp1)

-- field ::= `[´ exp `]´ `=´ exp  |  Name `=´ exp  |  exp
local fieldsep = Key{{',', ';'}}
local field = Or{kind='field',
  {UNPIN, '[', exp, ']', '=', exp},
  {UNPIN, name, '=', exp},
  exp,
}
-- fieldlist ::= field {fieldsep field} [fieldsep]
-- tableconstructor ::= `{´ [fieldlist] `}´
local fieldlist = {name='fieldlist',
  field, Many{UNPIN, fieldsep, field}, Maybe(fieldsep)}
local tbl = {kind='table', '{', Maybe(fieldlist), '}'}
add(exp1, tbl)

-- fully define function call
-- call ::=  `(´ [explist1] `)´  |  tableconstructor  |  String
ds.extend(call, {
  {kind='call', '(', explist, ')'},
  {kind='callTbl', tbl},
  {kind="callStr", str},
})

-----------------
-- Function (+exp1)

-- namelist ::= Name {`,´ Name}
-- parlist1 ::= namelist [`,´ `...´]  |  `...´
-- funcbody ::= `(´ [parlist1] `)´ block end
-- function ::= `function` funcbody
local namelist = {name, Many{',', name}}
local parlist = Or{name='parlist',
  Pat'%.%.%.',
  -- NeedLint: `...` only valid at the end
  {name, Many{ ',', Or{Pat'%.%.%.', name} }},
  Empty
}
local fnbody = {name='fnbody', '(', parlist, ')', block, 'end'}
local fnvalue = {'function', fnbody, kind='fnvalue'}
add(exp1, fnvalue)
add(exp1, name)

-----------------
-- Statement (stmt)
local elseif_  = {'elseif', {kind='cond', exp}, 'then', block, kind='elseif'}
local else_    = {'else', block, kind='else'}
local funcname = {name, Many{'.', name}, Maybe{UNPIN, ':', name}, kind='funcname'}

-- varlist `=´ explist
-- NeedLint: check that all items in first explist are var-like
local varset = {UNPIN, explist, '=', PIN, explist, kind='varset'}

ds.extend(stmt, {
  {Pat'#%!.*', kind='shexe'}, -- shell execute
  ';',  -- unused ';' permitted

  {Pat'::', name, Pat'::', kind='loc'},

  -- do block end
  {'do', block, 'end', kind='do'},

  -- while exp do block end
  {'while', exp, 'do', block, 'end', kind='while'},

  -- repeat block until exp
  {'repeat', block, 'until', exp, kind='repeat'},

  -- if exp then block {elseif exp then block} [else block] end
  {'if', {kind='cond', exp}, 'then', block,
    Many{elseif_}, Maybe(else_), 'end', kind='if'},

  -- for Name `=´ exp `,´ exp [`,´ exp] do block end
  {kind='fori',
    UNPIN, 'for', name, '=', PIN,
    exp, ',', exp, Maybe{',', exp}, 'do', block, 'end',
  },

  -- for namelist in explist1 do block end
  {kind='for',
    'for', namelist, 'in', explist, 'do', block, 'end'
  },

  -- funcname ::= Name {`.´ Name} [`:´ Name]
  -- function funcname funcbody
  {'function', funcname, fnbody, kind='fndef'},

  -- local function Name funcbody
  {UNPIN, 'local', 'function', PIN, name, fnbody, kind='fnlocal'},

  -- local namelist [`=´ explist1]
  {'local', namelist, Maybe{'=', explist}, kind='varlocal'},

  varset,

  -- catch-all exp
  -- NeedLint: only a fncall is actually valid syntax
  {exp, kind='stmtexp'},
})

local function skipComment(p)
  if not p.line then return end
  local c, c2 = p.line:find('^%-%-', p.c)
  if not c then return end
  local l = p.l; p.c = c2+1
  local t = bracketStrImpl(p)
  if t and mty.ty(t) ~= Token then
    local l1, c1 = t[1]:span()
    return Token:encode(p, l1, c1, select(3, t[#t]:span()))
  end
  if t then t.c = c; return t
  else
    p.l, p.line = l, get(p.dat,l)
    local _, c2 = p.line:find('^.*', c2+1)
    return Token:encode(p, l, c, l, c2)
  end
end

local src = {name='src', block, Eof}
M.config = pegl.Config{skipComment=skipComment}
M.lenientConfig = ds.copy(M.config, {lenient=true})

local function parse(dat, spec, config)
  config = config or M.config
  if not config.skipComment then config.skipComment = skipComment end
  return pegl.parse(dat, spec, config)
end

--- The default lua syntax highlighter.
M.highlighter = require'pegl.acsyntax'.Highlighter {
  config = M.lenientConfig,
  spec   = M.lenientBlock,
  -- todo: define most of these in pegl.BASE_STYLE and copy+update it.
  style = {
    -- Code Syntax
    keyword = 'keyword', ['return'] = 'keyword', ['break'] = 'keyword',
    ['nil'] = 'literal', ['true'] = 'literal',   ['false'] = 'literal',
    base2     = 'num',    base10    = 'num',    base16     = 'num',
    singleStr = 'string', doubleStr = 'string', bracketStr = 'string',

    ['='] = 'symbol',
    op1 = 'symbol', op2 = 'symbol',
    [';'] = 'meta', [','] = 'meta',

    funcname = 'api',
    field = 'key', -- key in map/struct/etc
    methname = 'dispatch',
    comment = 'comment',

    name = 'none',
  },
  builtin = {
    -- truly builtin (special functionality)
    'self', '_G', '_ENV', '_VERSION',

    -- modules
    'io', 'os', 'coroutine', 'debug',
    'math', 'table', 'string',

    -- builtin functions
    'require',
    'print', 'warn', 'assert', 'error',
    'load', 'loadfile', 'dofile', 'collectgarbage',
    'pcall', 'xpcall',
    'pairs', 'ipairs', 'next',
    'rawequal', 'rawget', 'rawset',
    'setmetatable', 'getmetatable',
    'tonumber', 'tostring', 'type',
    'select',

    -- conventional names
    'M', 'G',
  },
}

return ds.update(M, {
  src=src,
  skipComment=skipComment,
  exp=exp, exp1=exp1, stmt=stmt,
  num=num, str=str,
  field=field,
  explist=explist,
  varset=varset,
  name=name, call=call,
})