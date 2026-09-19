local mty = require'metaty'
local fmt = require'fmt'
local ds  = require'ds'
local Writer = require'lines.Writer'
local M = require'cxt'
local term = require'cxt.term'
local html = require'cxt.html'
local T = require'civtest'
local pegl = require'pegl'

local Config, Token       = mty.from'pegl  Config,Token'
local testing, EMPTY, EOF = mty.from'pegl  testing,EMPTY,EOF'
local KW, N, NUM, HEX     = mty.from(testing, 'KW, N, NUM, HEX')
local s = ds.simplestr

T'escape'; do
  T.eq('foo \\[bar\\] \\\\ baz', M.escape'foo [bar] \\ baz')
end

T'code'; do
  local hub = M._hasUnbalancedBrackets
  T.eq(false, hub'abc')
  T.eq(false, hub'[[a]b]')
  T.eq(true, hub'['); T.eq(true, hub']')
  T.eq(true, hub'[]]')

  local dollars = M._endDollars
  T.eq(0, dollars'foo bar')
  T.eq(1, dollars'foo]bar')
  T.eq(2, dollars'[$$$foo]$bar')

  T.eq(1,     dollars'some [code]')
  T.eq('[$$some [code]]$', M.code'some [code]')
  T.eq('[$some [code]',    M.code'some [code')
  T.eq('[$$some []code]$', M.code'some []code')
end


T'simple'; do
  M.assertParse('hi there', {'hi there'})
  M.assertParse('hi there [*bob]', {
    'hi there ', {'bob', b=true},
  })
  M.assertParse('The [$inline code]', {
    'The ', {'inline code', code=true, kind='code'},
  })
  M.assertParse('For [$inline], [$$any [brackets] need money]$', {
    'For ', {code=true, 'inline', kind='code'}, ', ',
    { code=true, kind='code',
      'any [brackets] need money'
    },
  })

  M.assertParse('[$$code]$.', { {'code', code=true}, '.'})

  M.assertParse('multiple\n [_lines]\n\n  with [*break]', {
    'multiple\n', {'lines', u=true},
    '\n', {p=true},
    'with ', {'break', b=true},
  })
  M.assertParse('has \\[ and \\] in it\n\\and \\\\foo', {
    'has ', '[ and ', '] in it\n', '\\and ', '\\foo',
  })

  M.assertParse('with \\[[@foo]\\] okay', {
    'with ', '[', {'foo', clone='foo'}, '] okay',
  })

  M.assertParse('empty [{}block works].', {'empty ', {'block works'}, '.'})
  M.assertThrows('[$ unclosed',    'Got EOF, expected')
  M.assertThrows('[$$ unclosed ]', 'Got EOF, expected')
  M.assertThrows('[$a[]]', "Unopened ']' found")

  M.assertParse('p1\n\np2\n  \np3', {
    'p1\n',
    {p=true}, 'p2\n',
    {p=true}, 'p3',
  })
end

T'block'; do
  M.assertParse([[
Some code:
[$$
This is a bit
  of code.
]$
]], {
    "Some code:\n",
    {"\nThis is a bit\n  of code.\n", code=true, block=true},
    '\n',
  })

end

T'attrs'; do
  pegl.assertParse{dat='i', spec=M.attr, expect={
      'i', pegl.EMPTY, kind='keyval',
    },
  }
  pegl.assertParse{dat='i}', spec=M.attrs,
    expect={kind='attrs',
      {'i', pegl.EMPTY, kind='keyval'},
      KW'}',
    },
  }
  M.assertParse('[,some] [{i}italic] blocks', {
    {'some', i=true}, ' ', {'italic', i=true}, ' blocks'
  })
  M.assertParse('go to [/the/right] path', {
    'go to ',
    {'the/right', path='the/right'},
    ' path',
  })
end

T'quote'; do
  M.assertParse([[
A quote:
["We work with being,[{br}]
  but non-being is what we use.

  -- Tao De Ching, Stephen Mitchel
]
]], {
    'A quote:\n',
    { quote=true,
      "We work with being,", {br=true}, "\n",
      "but non-being is what we use.\n",
      {p=true},
      "-- Tao De Ching, Stephen Mitchel\n",
    },
    '\n',
  }, true)
end

T'list'; do
  M.assertParse([[
A list:[+
* first item
* second item:[+
  * sub first
  * sub second
  ]

* third item
]
]],
  {
    "A list:", { list=true,
      {"first item"},
      {
        "second item:", { list=true,
          {"sub first"}, {"sub second"},
        },
        "\n", {p=true},
      },
      {"third item"},
    }, "\n"
  },
  true)

  -- bracketedStrRaw whitespace handling
  M.assertParse([[
A list:[+
*
  [$
  one block
  ]
* second block:

  [$
  start
    two block
  end
  ]
]
]], {
    "A list:", { list=true,
      {
        '\n',
        { code=true, block=true,
          '\n', 'one block\n',
        }, "",
      },
      {
        'second block:\n', {p=true},
        { code=true, block=true,
          '\n',
          'start\n', '  two block\n', 'end\n',
        }, "",
      },
    },
    '\n',
  },
  true)
end

T'nested'; do
  M.assertParse([[
[+
* list item

  [$$
  with inner code
  ]$
]
]],
  {
    { list=true,
      {
        "list item\n",
        {p=true},
        { block=true, code=true,
          "\n", "with inner code\n",
        }, ""
      },
    }, "\n"
  }, true)

end


T'table'; do
  local doc = [[
[{table}
# [*h]1     | h2   | h3
+ [{}+r1.1] | r1.2 | r1.3
+ [{}|r2.1] | r2.2 | r2.3
]
]]
  local noIndent = M.assertParse(doc,
  { -- src
    { table=true,
      { header=true,
        {"", {b=true, 'h'}, '1'},
        {"h2"},
        {"h3"},
      },
      { row = 1,
        {"", {"+r1.1"}, ""}, -- note: trimToken* causes ""
        {"r1.2"},
        {"r1.3"},
      },
      { row = 2,
        {"", {"|r2.1"}, ""},
        {"r2.2"},
        {"r2.3"},
      },
    },
    '\n',
  })
  local docIndent = [[
[{table}
  # [*h]1 | h2   | h3
  + [{}+r1.1] | r1.2 | r1.3
  + [{}|r2.1] | r2.2 | r2.3
]
]]
  M.assertParse(docIndent, noIndent)
end

T'named'; do
  M.assertParse([[
[{n=n1 href=hi.com}N1]
[@n1]
]],
  { -- src
    {'N1', name='n1', href='hi.com'},
    '\n',
    {'N1', href='hi.com'},
    '\n',
  })

  M.assertParse([[
[{: href=hi.com}N 2]
see [@N_2], I like [<@N_2>links]
]],
  { -- src
    {'N 2', name='N_2', href='hi.com'},
    '\n', 'see ',
    {'N 2', href='hi.com'}, ', I like ',
    {'links', href='hi.com'},
    '\n',
  })
end

T'htmlEncode'; do
  local he = html.htmlEncode
  T.eq('foo',                         he'foo')
  T.eq('foo bar',                     he'foo bar')
  T.eq('foo &nbsp;bar',               he'foo  bar')
  T.eq('&nbsp;foo &nbsp;bar',         he' foo  bar')
  T.eq('&nbsp; foo &nbsp;bar',        he'  foo  bar')
  T.eq('&nbsp; &nbsp;foo &nbsp;bar',  he'   foo  bar')
  T.eq('&nbsp; code &nbsp; &nbsp;inline',
     he'  code    inline')

  T.eq('<br>\n&nbsp; &nbsp;$ &nbsp; &nbsp; &nbsp;shortcut',
     he'\n   $      shortcut')
end

T'html'; do
  html.assertHtml('hi <b>there</b> bob\n', 'hi [*there] bob')
  html.assertHtml('code <span class=code>code</span>.\n', 'code [$$code]$.')
  html.assertHtml('p1\n\n<p>p2\n\n<p>p3\n', 'p1\n\np2\n  \np3')
  html.assertHtml(
    'name <a id="named" href="#named" class=anchor><b>thing</b></a>\n',
    'name [{*name=named}thing]')
  html.assertHtml(
    'hi <b>there</b>\n'
  ..'newline\n',
    'hi [*there]\n  newline')
  html.assertHtml(
[[
listing:<ul>
  <li>one</li>
  <li>two<ul>
    <li>three</li>
    <li>four</li>
  </ul></li>
</ul>
]],
[[
listing:[+
* one
* two[+
  * three
  * four
  ]
]
]]
)

  html.assertHtml(
[[
<div class=table><table>
  <tr>
    <th><b>h</b>1</th>
    <th>h2</th>
    <th>h3</th>
  </tr>
  <tr>
    <td>r1.1</td>
    <td>r1.2</td>
    <td>r1.3</td>
  </tr>
  <tr>
    <td>r2.1</td>
    <td>r2.2</td>
    <td>r2.3</td>
  </tr>
</table></div>
]],
[[
[{table}
# [*h]1 | h2   | h3
+ r1.1  | r1.2 | r1.3
+ r2.1  | r2.2 | r2.3
]
]])

  html.assertHtml(
[[
Some <span class=code>inline code</span> and: <div class=code-block>code 1<br>
code 2
</div>
next line.
]],
[[
Some [$inline code] and: [$$
code 1
code 2
]$
next line.
]])

  html.assertHtml(
[[
Code block: <div class=code-block>echo "foo bar" &nbsp;# does baz<br>
echo "blah $$$ blah"
</div>
end of code block.
]],
[[
Code block: [{$$ lang=sh}
echo "foo bar"  # does baz
echo "blah $$$ blah"
]$
end of code block.
]])

  html.assertHtml(
[[
list <ul>
  <li>code:
  <div class=code-block>some code<br>
more code
</div></li>
</ul>
]],
[[
list [+
* code:
  [$
  some code
  more code
  ]
]
]])
end

T'term'; do
  local f = fmt.Fmt{}
  term{'[$code] not code', out=f}
  T.eq('code not code\n', f:tostring())

  f = fmt.Fmt{}
  local _, node, p = term.convert([[
[{h1}Heading 1]
Some text
... more text

Code:
[{$$ lang=lua}
function foo() return 'hello world' end
]$

[*bold] [,italic] [/path/to/thing] [+
  * item 1
  * item 2 [$with code]
]
the end
]], f)
  T.eq(
"########################################\
# Heading 1\
Some text\
... more text\
\
Code:\
\
function foo() return 'hello world' end\
\
bold italic path/to/thing \
  * item 1\
  * item 2 with code\
the end\
", f:tostring())

  f = fmt.Fmt{}
local _, node, p = term.convert(
--"[{h1}[:doc_test] [/lib/doc/test.lua:1] [@Ty<doc_test>]]\
"[{h1}[:doc_test] [/lib/doc/test.lua:1] [@Ty<doc_test>] ]\
[{table}\
+ [*Methods, Etc]\
+ [:Example]      [@Ty<Example>]       | [/lib/doc/test.lua:11]\
+ [:__name]       [@string]            | \
]", f)
  local expect =
"########################################\
# doc_test lib/doc/test.lua:1 Ty<doc_test> \
\
  + Methods, Etc\
  + Example      Ty<Example>\9lib/doc/test.lua:11\
  + __name       string\9 "
  T.eq(expect, f:tostring())
end