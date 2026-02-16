local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local T = require'civtest'
local pegl = require'pegl'
local M = require'pegl.lua'

local Config, Token,
  testing, EMPTY, EOF, assertParse, assertParseError
  = mty.from(pegl, [[
      Config, Token,
      testing, EMPTY, EOF, assertParse, assertParseError
]])

local num, str, exp1, exp, field, varset,
  config, lenientConfig, src
  = mty.from(M, [[
      num, str, exp1, exp, field, varset,
      config, lenientConfig, src
]])
local D = 'lib/pegl/'

local KW, N, NUM, HEX = mty.from(testing, 'KW,N,NUM,HEX')
local function SRC(...) return {..., EMPTY, EMPTY, EOF} end

local OP1 = function(sym) return {kind='op1', sym} end
local OP2 = function(sym) return {kind='op2', sym} end

T'easy'; do
  assertParse{dat='42  0x3A', spec={num, num}, expect={
    NUM'42', HEX'0x3A',
  }, config=config}
  assertParse{dat='  nil\n', spec={exp1}, expect=KW('nil')}
  assertParse{
    dat='true  \n false', spec={exp1, exp1},
    expect={KW('true'), KW('false')}}

  -- use exp instead
  assertParse{dat='  nil\n', spec={exp}, expect=KW('nil')}
end

T'str'; do
  assertParse{dat=' "hi there" ', spec={str},
    expect={kind='doubleStr', '"hi there"'}}
  assertParse{dat=[[  'yo\'ya'  ]], spec={str},
    expect={kind='singleStr', [['yo\'ya']]}}
  assertParseError{dat=[[  'yo\'ya"  ]], spec={exp},
    errPat='Expected singleStr, reached end of line'
  }
  assertParse{dat=[[  'single'  ]], spec={str},
    expect={kind='singleStr', [['single']]}}
  assertParse{dat=[[  'single'  ]], spec={str},
    expect={kind='singleStr', [['single']]}}

  assertParse{dat="[[a ['string'] ]]", spec=str, config=config,
    expect={kind='bracketStr', "[[", "a ['string'] ", "]]"}}
  assertParse{dat="[====[\n[=[\n[[ wow ]]\n]=]\n]====]",
    spec=str, config=config,
    expect={kind='bracketStr',
      "[====[", "\n[=[\n[[ wow ]]\n]=]\n", "]====]",
    }}
end

T'decimal'; do
  assertParse{dat='-42 . 3343', spec={num}, expect=
    NUM{neg=true, '42','3343'}
  , config=config}
end

T'field'; do
  assertParse{dat=' 44 ',     spec={field},
    expect={kind='field', NUM'44'}}
  assertParse{dat=' hi ',     spec={field},
    expect={kind='field', {kind='name', 'hi'}}}
  assertParse{dat=' hi="x" ', spec={field},
    expect={kind='field',
      {kind='name', 'hi'}, KW('='), {kind='doubleStr', '"x"'},
    }
  }
  assertParse{dat='[hi] = 4', spec={field},
    expect = {
      kind='field',
      KW('['), {'hi', kind='name'}, KW(']'),
      KW('='), NUM'4',
    }
  }
end

T'table'; do
  assertParse{dat='{}', spec={exp}, 
    expect={kind='table',
      KW('{'), EMPTY, KW('}'),
    },
  }
  assertParse{dat='{4}', spec={exp},
    expect={kind='table',
      KW('{'),
      {kind='field', NUM'4'},
      EMPTY,
      KW('}'),
    },
  }
  assertParse{dat='{4, x="hi"}', spec={exp},
    expect={ kind='table',
      KW('{'),
      {kind='field', NUM'4'},
      KW(','),
      {kind='field',
        {kind='name', 'x'}, KW('='), {kind='doubleStr', '"hi"'}},
      EMPTY,
      KW('}'),
    },
  }
end

T'fnValue'; do
  assertParse{dat='function() end', spec={exp},
    expect = { kind='fnvalue',
      KW('function'), KW('('), EMPTY, KW(')'),
      EMPTY,
      KW('end'),
    },
  }
end

T'expression'; do
  assertParse{dat='x+3', spec=exp,
    expect={N'x', OP2'+', NUM'3'},
  }
  assertParse{dat='x()+3', spec=exp,
    expect= {
      N"x", {kind='call',
        KW"(", EMPTY, KW")",
      }, OP2'+', NUM'3'
    },
  }
end

T'require'; do
  assertParse{dat='local F = require"foo"', spec=src,
    expect = SRC(
      { kind='varlocal',
        KW('local'),
        {kind='name', 'F'},
        KW('='),
        {kind='name', 'require'}, {kind='callStr',
          {kind='doubleStr', '"foo"'},
        },
      }
    ),
  }
end

T'varset'; do
  local code1 = 'a = 7'
  local expect1 = {kind='varset', N'a', KW'=', NUM'7',
  }
  assertParse{dat=code1, spec=varset, expect=expect1}
end

T'comment'; do
  local expect = SRC(
    {kind='varset',
      N"x", KW"=", {kind="table",
        KW"{", EMPTY, KW"}",
      },
    })
  assertParse{dat='x = --line\n  {}', spec=src,
    expect=expect, config=config,
  }
  assertParse{dat='x = -- block{}\n{}', spec=src,
    expect = expect, config=config,
  }
  assertParse{dat='x\n=\n-- \n--block\n\n{}--hi\n--EOF', spec=src,
    expect = expect, config=config,
  }
end

T'function_'; do
  assertParse{ spec=src, config=config,
    dat=[[ local function f(a) end ]],
    expect = {
      {kind="fnlocal",
        KW"local", KW"function", N"f", KW"(", N"a", KW")", EMPTY, KW"end",
      }, EMPTY, EMPTY, EOF
    },
  }
end

T'fncall'; do
  local r, n, p = assertParse{dat='foo(4)', spec=src, config=config,
    expect = SRC({ kind="stmtexp",
      N"foo", {kind='call',
        KW"(", NUM'4', KW")",
      },
    })
  }
  local expect = [[{
  {
    N"foo", {
      KW"(", NUM{4}, KW")", 
      kind="call"
    }, 
    kind="stmtexp"
  }, EMPTY, EMPTY, EOF
}]]
  T.eq(expect, table.concat(config.newFmt()(r)))

  assertParse{dat='foo({__tostring=4})', spec=src, config=config,
    expect = SRC({ kind="stmtexp",
      N"foo", { kind='call',
        KW"(", { kind="table",
          KW"{",
            {N"__tostring", KW"=", NUM'4', kind="field"}, EMPTY,
          KW"}",
        }, KW")",
      },
    })
  }

  assertParse{dat='foo"4"', spec=src, config=config,
    expect = SRC({ kind="stmtexp",
      N"foo", {kind='callStr',
        {"\"4\"", kind="doubleStr"}
      },
    })
  }

  assertParse{dat='foo[[4]]', spec=src, config=config,
    expect = SRC({ kind="stmtexp",
      N"foo", {kind='callStr',
        {"[[", "4", "]]", kind="bracketStr"}
      },
    }),
  }
end

T'if_elseif_else'; do
  assertParse{dat='if n==nil then return "" end', spec=src, config=config,
    expect=SRC(
    { kind='if',
      KW"if",
        { kind='cond',
          N"n", OP2'==', KW"nil",
        }, KW"then", { kind='return',
        KW"return", {
          "\"\"", kind="doubleStr"
        },
      }, EMPTY, EMPTY, KW"end",
    })
  }
end

T'fnChain'; do
  assertParse{dat='x(1)(3)', spec=src, config=config,
    expect=SRC{ kind="stmtexp", N"x",
      { KW"(", NUM{1}, KW")", kind="call" },
      { KW"(", NUM{3}, KW")", kind="call" },
    }
  }

  local DAT=[[x "a ['string'] "]]
  assertParse{dat=DAT, spec=src, config=config,
    expect = SRC { kind="stmtexp",
        N"x", { kind="callStr",
        { "\"a ['string'] \"", kind="doubleStr" },
      },
    }
  }
end

T'src1'; do
  local code1 = 'a.b = function(y, z) return y + z end'
  local expect1 = SRC({kind='varset',
    N'a', OP2'.', N'b', KW'=', {kind='fnvalue',
      KW'function', KW'(', N'y', KW',', N'z', KW')',
      {kind='return', KW'return', N'y', OP2'+', N'z'},
      EMPTY,
      KW'end',
    },
  })
  assertParse{dat=code1, spec=src, expect=expect1}

  local code2 = code1..'\nx = y'
  local expect2 = ds.copy(expect1)
  table.remove(expect2) -- EOF
  table.remove(expect2) -- EMPTY
  ds.extend(expect2, SRC({kind='varset',
    N'x', KW'=', N'y',
  }))
  assertParse{dat=code2, spec=src, expect=expect2}
end

local function extendExpectAssert(code, spec, expect, extend, dbg)
  T.eq(EOF, table.remove(expect))
  T.eq(EMPTY, table.remove(expect))
  T.eq(EMPTY, table.remove(expect))
  ds.extend(expect, extend)
  table.insert(expect, EMPTY)
  table.insert(expect, EMPTY)
  table.insert(expect, EOF)
  assertParse{dat=code, spec=spec, expect=expect, config=config, dbg=dbg}
end

T'src2'; do
  local code = '-- this is a comment\n--\n-- and another comment\n'
  assertParse{dat=code, spec=src, expect={EMPTY, EOF}, config=config}

  local expect = {EMPTY, EMPTY, EOF}
  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {{kind='varlocal',
    KW'local', N'add', KW'=', N'table', OP2'.', N'insert'
  }})

  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {EMPTY, {kind='varlocal',
    KW'local', N'add', KW'=', N'table', OP2'.', N'insert'
  }})

  local code = code..'local last = function(t) return t[#t] end\n'
  extendExpectAssert(code, src, expect, {EMPTY, {kind='varlocal',
    KW'local', N'last', KW'=',
      {kind='fnvalue',
        KW'function', KW'(', N't', KW')',
        {kind='return',
          KW'return', N't', {kind='index',
            KW'[', OP1'#', N't', KW']',
          }
        },
        EMPTY, KW'end',
      },
    },
  })
end


local ERR_EXPECT = [[
ERROR
Path: (rawdata)
[LINE 2.16]    x = 1 + {2 3} -- '2 3' is invalid
                          ^
Cause: parser expected: "}"
Got: 3} -- '2 3' is invalid
Parse stack:
  src(1.3)
  block(1.3)
  stmt(1.3)
  fnlocal(1.3)
  fnbody(1.19)
  block(2.5)
  stmt(2.5)
  varset(2.5)
  exp(2.9)
  op2exp(2.11)
  exp(2.13)
  exp1(2.13)
  table(2.13)]]

local BAD_LUA = [[
  local function x()
    x = 1 + {2 3} -- '2 3' is invalid
  end
]]
T'error'; do
  T.throws(ERR_EXPECT, function()
    pegl.parse(BAD_LUA, src, Config{dbg=false})
  end)
end

local function assertLenient(t)
  t.spec   = t.spec   or M.lenientBlock
  t.config = t.config or lenientConfig
  local r, n, p = assertParse(t)
  local ee = t.firstError
  local fe = p.firstError
  T.eq({ee.l,ee.c}, {fe.l, fe.c})
  T.contains(ee.contains, table.concat(fe, '\n'))
end

T'lenient'; do
  assertLenient{
    dat=BAD_LUA,
    expect= {
      KW"local", KW"function",
      { kind="stmtexp",
        N"x",
        { kind="call",
          KW"(", EMPTY, KW")",
        },
      },
      { kind="varset",
        N"x", KW"=", NUM{1},
      },
      "+", KW"{", NUM{2}, NUM{3}, KW"}", KW"end"
    },
    firstError = {l=2,c=16, contains="'2 3' is invalid"},
  }

  assertLenient{
    dat = [[string'not done]],
    expect = {N'string', "'not", N'done'},
    firstError={l=1,c=8, contains="Expected singleStr, reached end of line"},
  }
end

local function testLuaPath(path)
  local text = pth.read(path)
  assertParse{dat=text, spec=src, config=config, parseOnly=true}
end


T'parseSrc'; do
  -- testLuaPath('/patience/patience2.lua')
  testLuaPath(D..'pegl.lua')
  testLuaPath(D..'lua.lua')
end
