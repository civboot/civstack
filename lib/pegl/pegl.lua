local G = G or _G

--- pegl: peg-like lua parser
local M = G.mod and G.mod'pegl' or {}

local mty     = require'metaty'
local fmt     = require'fmt'
local ds      = require'ds'
local log     = require'ds.log'
local lap     = require'lap'
local lines   = require'lines'
local T       = require'civtest'
local extend  = ds.extend

local ljoin, lines_sub = mty.from'lines  join,sub'
local push, pop = table.insert, table.remove
local concat, unpack = table.concat, table.unpack
local sfmt    = string.format
local srep = string.rep
local ty = mty.ty
local get, set = ds.get, ds.set
local info = mty.from'ds.log info'

local function lsub(...) return concat(lines_sub(...), '\n') end

local function zero() return 0 end

--- Tokens use a packed span to preserve space.
--- Maximums: line start|len = 2^24|2^16. cols=255
M.SPAN_PACK = '>I3I2I2I2'
function M.encodeSpan(l1, c1, l2, c2)
  return string.pack(M.SPAN_PACK, l1, c1, l2-l1, c2)
end
function M.decodeSpan(s)
  local l, c, l2, c2 = string.unpack(M.SPAN_PACK, s)
  return l, c, l + l2, c2
end

M.Token = mty'Token'{
  'kind [string]: optional, used for debugging',
  'style [string]: computed by acsyntax',
}
function M.Token:span(dec) --> l, c, l2, c2
  return M.decodeSpan(self[1])
end
-- TODO: remove `p`?
M.Token.encode = function(T, p, l, c, l2, c2, kind, style)
  return T{M.encodeSpan(l,c, l2,c2), kind=kind, style=style}
end
function M.Token:decode(dat) return lsub(dat, M.decodeSpan(self[1])) end
function M.Token:__fmt(f)
  f:write'Tkn';
  f:write(sfmt('(%s.%s %s.%s', self:span()))
  if self.kind  then f:write(' kind=', self.kind) end
  if self.style then f:write(' style=', self.style) end
  f:write')'
end
--- compare two tokens, commonly used in sorting algorithms.
function M.Token:lte(r) 
  local l1, c1 = self:span()
  local l2, c2 = r:span()
  if l1 < l2 then return true  end
  if l1 > l2 then return false end
  return c1 <= c2
end

local TOKEN_TY = {string=true, [M.Token]=true}
function M.firstToken(list) --> t, listWithToken
  if TOKEN_TY[ty(list)] then return list, nil end
  local t = list[1]; while not TOKEN_TY[ty(t)] do
    list = t; t = list[1]
  end
  return t, list
end
function M.lastToken(list) --> t, listWithToken
  if TOKEN_TY[ty(list)] then return list, nil end
  local t = list[#list]; while t and not TOKEN_TY[ty(t)] do
    list = t; t = list[#list]
  end
  return t, list
end

function M.nodeSpan(t)
  local fst, lst = M.firstToken(t), M.lastToken(t)
  local l1, c1 = fst:span()
  return l1, c1, select(3, lst:span())
end

--- The config spec defines custom behavior when parsing. It's attributes
--- can be set to change how the parser skips empty (whitespace) and handles comments.
M.Config = mty'Config' {
[==[skipEmpty [fn(p) -> nil]: default=skip whitespace [+
    * must be a function that accepts the `Parser`
      and advances it's `l` and `c` past any empty (white) space. It must also set
      `p.line` appropriately when `l` is moved.
    * The return value is ignored.
    * The default is to skip all whitespace (spaces, newlines, tabs, etc). This
      should work for _most_ languages but fails for languages like python.
    * Recommendation: If your language has only a few whitespace-aware nodes (i.e.
      strings) then hand-roll those as recursive-descent functions and leave
      this function alone.
  ]]==],

  'skipComment [fn(p) -> Token]: function for behavior of found comment',

[==[tokenizer [fn(p) -> nil] Requires: [+
    * must return one token. The default is to return a single punctuation character
      or a whole word ([$_%w])
    * Objects like [$Key] can use the single punctuation characters in a Trie-like
      performant data structure.
  ]]==],

  'dbg [boolean]: if true, prints out huge amounts of debug information of parsing.',

[==[lenient [bool]: if set, syntax errors do not cause failure.
   Instead, all errors act as if the current block missed but was UNPIN.
]==],
}

--- The parser tracks the current position of parsing in `dat` and has several
--- convienience methods for hand-rolling your own recursive descent functions.
---
--- [" Note: the location is **line/col based** (not position based) because it
---    is designed to work with an application that stores the strings as lines
---    (a text editor) ]
M.Parser = mty'Parser'{
  'dat [lines]: reference to the underlying data.\n'
..'Must look like a table of lines',
  'l [int]: line, incremented when [$c] is exhausted',
  'c [int]: column in [$line]',
  'line [string]: the current line ([$dat:get(l)])',
  'lines',
  'config [Config]',
  'stack [list]', 'stackL [list]', 'stackC [list]',
  'stackLast [{item, l, c}]',
  'commentLC [table]: table of cached {line={col=CommentToken}}',
  'comments {Token}: list of comment tokens',
  'dbgLevel [number]', dbgLevel = 0,
  'path [string]',
  'firstError {l=int,c=int, [1]=str}: first error.',
}

function M.fmtSpec(s, f)
  if type(s) == 'string'   then return f(s) end
  if type(s) == 'function' then return f(s) end
  if s.name or s.kind then
    return f:write('<', s.name or s.kind, '>')
  end
  if ty(s) ~= 'table' then f:write(mty.tyName(ty(s))) end

  f:level(1); f:write(f.tableStart)
  for i, sub in ipairs(s) do
    f(sub); if i < #s then f:write' ' end
  end
  f:level(-1); f:write(f.tableEnd)
end
function M.specToStr(s, fmt)
  local fmt = fmt or fmt.Fmt:pretty()
  M.fmtSpec(s, fmt)
  return concat(fmt)
end

--- Create a parser spec record. These have the fields [$kind] and [$name]
--- and must define the [$parse] method.
function M.specTy(name)
  local s = mty(name){'kind [string]', 'name [string]', __fmt=M.fmtSpec}
  s.get, s.set = rawget, rawset
  s.extend = ds.defaultExtend
  return s
end

--- [$Pat{'%w+', kind='word'}] will create a Token with the span matching the
--- [$%w+] pattern and the kind of [$word] when matched.
M.Pat = M.specTy'Pat'
getmetatable(M.Pat).__call = function(T, t)
  if type(t) == 'string' then t = {t} end
  assert(#t > 0, 'must specify a pattern')
  return mty.construct(T, t)
end

local KEY_FORM =
  "construct Keys like Keys{{'kw1', 'kw2', kw3=true, kw4={sub-keys}, kind=...}"

local function constructKeys(keys)
  assert(ty(keys) == 'table', KEY_FORM)
  for i=1,#keys do
    keys[keys[i]] = true;
    keys[i] = nil end
  for k, v in pairs(keys) do
    if k == true then assert(v == true)
    else fmt.assertf(
      type(k) == 'string', 'number key after list items: %s', k)
    end
    if ty(v) == 'table' then keys[k] = constructKeys(v)
    elseif v ~= true then fmt.errorf('%s: %q', KEY_FORM, v) end
  end
  return keys
end

--- The table given to [$Key] forms a Trie which is extremely performant. Key depends
--- strongly on the [$tokenizer] passed to Config.
---
--- Example: [$$Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}]$ will match
--- tokens "myKeyword" and "+" followed by "+" (but not "+" not followed by
--- "+").
---
--- To also match "+" use [$$['+']={true, '+'=true}]$
---
--- ["Note: The `Key` constructor converts all list items into
---         [$value=true], so [${'a', 'b'}] is converted to [${a=true, b=true}]]
M.Key = mty'Key' {
  'keys [table]', 'name [string]', 'kind [string]',
  __fmt = M.fmtSpec,
}
getmetatable(M.Key).__call = function(T, t)
  local keys = assert(table.remove(t, 1), 'must provide keys at index 1')
  t['keys'] = constructKeys(keys)
  return mty.construct(T, t)
end

--- choose one spec
---
--- Example: [$Or{'keyword', OtherSpec, Empty}] will match one of the three
--- specs given.  Note that [$Empty] will always match (and return
--- [$pegl.EMPTY]).  Without [$Empty] this could return [$nil], causing a
--- parent [$Or] to match a different spec.
---
--- ["Note: [$Maybe(spec)] literally expands to [$Or{spec, Empty}]]
---
--- Prefer [$Key] if selecting among multiple string or token paths as [$Or] is
--- not performant ([$O(N)] vs Key's [$O(1)])
M.Or = M.specTy'Or'
function M.Maybe(spec) return M.Or{spec, M.Empty} end
--- match a Spec multiple times
--- Example: [$Many{'keyword', OtherSpec, min=1, kind='myMany'}] will match the
--- given sequence one or more times ([$min=0] times by default). The parse
--- result is a list with [$kind='myMany'].
M.Many = mty'Many' {
  'min [int]', min = 0,
  'kind [string]', 'name [string]',
  'yield [int]: call lap.yield() on every int loop',
  __fmt = M.fmtSpec,
}

--- A Sequence of parsers. Note that [$Parser] treats [$Seq{'a'}] and [${'a'}]
--- identically (you can use plain tables instead).
---
--- Raw strings are treated as keywords (the are parsed literally and have
--- [$key] set to themselves). Functions are called with the [$parser] as the
--- only argument and must return the node/s they parsed or [$nil] for a
--- non-error match.
---
--- A sequence is a list of either other parsers
--- ([$Seq, {}, "keyword", fn(p), Not, Or, etc]} and/or plain strings which are
--- treated as keywords and will have [$kind] be set to themselves when parsed.
---
--- If the first spec matches but a later one doesn't an [$error] will be thrown
--- (instead of [$nil] returned) unless [$UNPIN] is used. See the PIN/UNPIN
--- docs for details.
---
--- [{h4}PIN/UNPIN: Syntax Error Reporting]
--- PEGL implements syntax error detection ONLY in Sequence specs (table specs i.e.
--- `{...}`) by throwing an [$error] if a "pinned" spec is missing. [+
---
--- * By default, no error will be raised if the first spec is missing. After the
---   first spec, [$pin=true] and any missing specs to throw an error with context.
---
--- * [$PIN] can be used to force [$pin=true] until [$UNPIN] is (optionally)
---   specified.
---
--- * [$UNPIN] can be used to force [$pin=false] until [$PIN] is (optionally)
---   specified.
---
--- * PIN / UNPIN only affect the [,current] sequence (they do not pin
---   sub-sequences).
--- ]
M.Seq = M.specTy'Seq'
M.Not = M.specTy'Not'
function M.Not:parse(p) return not M.parseSeq(p, self) end

-- Used in Seq to "pin" or "unpin" the parser, affecting when errors
-- are thrown.
M.PIN   = ds.sentinel('PIN',   {name='PIN',   kind=false})
M.UNPIN = ds.sentinel('UNPIN', {name='UNPIN', kind=false})

-- Denotes a missing node. When used in a spec simply returns Empty.
-- Example: Or{Integer, String, Empty}
M.EMPTY = ds.sentinel('EMPTY', {kind='EMPTY', __len=zero})
M.Empty = ds.sentinel('Empty', {parse = function() return M.EMPTY end})

function M.isEmpty(t) return mty.eq(M.EMPTY, t) end
function M.notEmpty(t) return not mty.eq(M.EMPTY, t) end

-- Denotes the end of the file
M.EOF = ds.sentinel('EOF', {kind='EOF', __len=zero})
M.Eof = ds.sentinel('Eof', {
  __tostring = function() return 'Eof' end,
  parse = function(self, p)
    p:skipEmpty(); if p:isEof() then return M.EOF end
  end
})

-------------------
-- Root and Utilities

function M.skipWs1(p)
  if p.c > #p.line then p:incLine(); return
  else
    local c, c2 = p.line:find('^%s+', p.c)
    if c then p.c = c2 + 1; return end
  end
  return true
end

function M.skipEmpty(p)
  local loop, sc, cmt, cL, cached = true, p.config.skipComment, nil, nil
  while loop and not p:isEof() do
    loop = not M.skipWs1(p)
    if sc then
      -- cL=cached comments at line. Load from cache or parse with sc.
      cL = p.commentLC[p.l]
      cmt = (cL and cL[p.c]) or sc(p)
      if cmt then -- found comment, advance past it.
        p:dbg('COMMENT: %s.%s', p.l, p.c)
        cL = p.commentLC[p.l]
        if not cL then cL = {}; p.commentLC[p.l] = cL end
        if not cL[p.c] then -- not yet cached
          cL[p.c] = cmt
          push(p.comments, cmt)
        end
        p.l, p.c = select(3, cmt:span()); p.c = p.c + 1
      end
    end
  end
end
M.Config.skipEmpty = M.skipEmpty

function M.skipEmptyMinimal(p)
  while not p:isEof() do
    if p.c > #p.line then p:incLine()
    else return end
  end
end

function M.defaultTokenizer(p)
  if p:isEof() then return end
  return p.line:match('^%p', p.c) or p.line:match('^[_%w]+', p.c)
end
M.Config.tokenizer = M.defaultTokenizer

local UNPACK_SPECS = ds.Set{'table', M.Seq, M.Many, M.Or}
local function shouldUnpack(spec, t)
  local r = (
    type(t) == 'table'
    and UNPACK_SPECS[ty(spec)]
    and ty(t) ~= M.Token
    and not spec.kind
    and not t.kind
  )
  return r
end

-- Create node with optional kind.
-- This may just return `true`, which means no node is
-- generated but parsing should not fail.
local function node(spec, t, kind) --> {token, kind=kind}
  if type(t) ~= 'boolean' and t and kind then
    if type(t) == 'table' and not t.kind then t.kind = kind
    else t = {t, kind=kind} end
  end
  if shouldUnpack(spec, t) and #t==1 then t = t[1] end
  return t
end

-------------------
-- Key

function M.Key:parse(p)
  p:skipEmpty()
  local c, keys, found = p.c, self.keys, false
  while true do
    local k = p.config.tokenizer(p); if not k    then break end
    keys = keys[k];                if not keys then break end
    p.c = p.c + #k
    if keys == true then found = true; break end
    found = keys[true]
  end
  if found then
    local kind = self.kind or lsub(p.dat, p.l, c, p.l, p.c - 1)
    return M.Token:encode(p, p.l, c, p.l, p.c -1, kind)
  end
  p.c = c
end

-------------------
-- Pat

function M.Pat:parse(p)
  p:skipEmpty()
  for _, pat in ipairs(self) do
    local t = p:consume(pat)
    if t then
      t.kind = self.kind
      p:dbgMatched(t.kind or pat)
      return t
    end
  end
end

-------------------
-- Seq (table)
local function _seqAdd(p, out, spec, t)
  if type(t) == 'boolean' then -- skip
  elseif shouldUnpack(spec, t) then
    p:dbgUnpack(spec, t)
    extend(out, t)
  else push(out, t) end
end

function M.parseSeq(p, seq)
  p:skipEmpty()
  local out, pin = {}, nil
  p:dbgEnter(seq)
  for i, spec in ipairs(seq) do
    if     spec == M.PIN   then pin = true;  goto continue
    elseif spec == M.UNPIN then pin = false; goto continue
    end
    local t = p:parse(spec)
    if not t then
      p:dbgMissed(spec)
      p:dbgLeave()
      return p:checkPin(pin, spec)
    end
    _seqAdd(p, out, spec, t)
    pin = (pin == nil) and true or pin
    ::continue::
  end
  local out = node(seq, out, seq.kind)
  p:dbgLeave(out)
  return out
end

M.Seq.parse = function(seq, p) return M.parseSeq(p, seq) end

-------------------
-- Or

function M.Or:parse(p)
  p:skipEmpty()
  p:dbgEnter(self)
  local state = p:state()
  for _, spec in ipairs(self) do
    local t = p:parse(spec)
    if t then
      t = node(spec, t, self.kind)
      p:dbgLeave(t)
      return t
    end
    p:setState(state)
  end
  p:dbgLeave()
end

-------------------
-- Many

function M.Many:parse(p)
  p:skipEmpty()
  local out = {}
  p:dbgEnter(self)
  local y = self.yield
  while true do
    local t = M.parseSeq(p, self)
    if not t then break end
    if ty(t) ~= M.Token and #t == 1 then push(out, t[1])
    else _seqAdd(p, out, self, t) end
    if y and y == 1 then
      y = self.yield; lap.yield()
    end
  end
  if #out < self.min then
    p:dbgMissed(self, ' got count=%s', #out)
    out = nil
  end
  p:dbgLeave(self)
  return node(self, out, self.kind)
end

-------------------
-- Misc

local SPEC_TY = {
  ['function'] = function(p, fn) p:skipEmpty() return fn(p) end,
  string = function(p, kw)
    p:skipEmpty();
    local tk = p.config.tokenizer(p)
    if kw == tk then
      local c = p.c; p.c = c + #kw
      return M.Token:encode(p, p.l, c, p.l, p.c - 1, kw)
    end
  end,
  table = function(p, tbl) return M.parseSeq(p, tbl) end,
}

--- Parse a spec, returning the nodes or throwing a syntax error.
---
--- [$config] is used to define settings of the parser such as how to skip
--- comments and whether to use debug mode.
function M.parse(dat, spec, config) --> list[Node]
  local p = M.Parser:new(dat, config)
  local n = p:parse(spec)
  return n, p
end

function M.Parser:assertNode(expect, node, config) --> strTokens
  local result = self:toStrTokens(node)
  if not mty.eq(expect, result) then
    local eStr = concat(self.config.newFmt()(expect))
    local rStr = concat(self.config.newFmt()(result))
    if eStr ~= rStr then
      print('\n#### EXPECT:'); print(eStr)
      print('\n#### RESULT:'); print(rStr)
      print()
      T.showDiff(io.fmt, eStr, rStr)
    else
      print('\n#### FORMATTED:'); print(eStr)
      print('## Note: They format the same but they differ')
      T.eq(t.expect, result)
    end
    error'failed parse test'
  end
  return result
end

--- Parse the [$dat] with the [$spec], asserting the resulting "string tokens"
--- are identical to [$expect].
---
--- The input is a table of the form: [{$$ lang=lua}
---   {dat, spec, expect, dbg=nil, config=default} --> nil
--- ]$
function M.assertParse(t) --> result, node, parser
  assert(t.dat, 'dat'); assert(t.spec, 'spec')


  local config = (t.config and ds.copy(t.config)) or M.Config{}
  config.dbg   = t.dbg or config.dbg
  local node, parser = M.parse(t.dat, t.spec, config)
  if not t.expect and t.parseOnly then return nil, node, parser end
  local result = parser:assertNode(t.expect, node)
  return result, node, parser
end

function M.assertParseError(t)
  T.throws(
    t.errPat,
    function() M.parse(assert(t.dat), assert(t.spec)) end,
    t.plain)
end

-------------------
-- Parser Methods

M.Parser.__tostring = function() return 'Parser()' end
M.Parser.new = function(T, dat, config)
  dat = (type(dat)=='string') and lines(dat) or dat
  return mty.construct(T, {
    dat=dat, l=1, c=1, line=get(dat,1), lines=#dat,
    config=config or M.Config{},
    stack={}, stackL={}, stackC={}, stackLast={},
    commentLC={}, comments={},
  })
end

--- the main entry point and used recursively.
--- Parses the spec, returning the node, which is a table of nodes that are
--- eventually tokens.
function M.Parser:parse(spec) --> node
  local Ty = ty(spec)
  local specFn = SPEC_TY[Ty]
  if specFn then return specFn(self, spec)
  else           return spec:parse(self) end
end
--- consume the pattern, advancing the column if found
function M.Parser:consume(pat, plain) --> Token
  local t = self:peek(pat, plain)
  if t then self.c = select(4, t:span()) + 1 end
  return t
end
--- identical to `consume` except it does not advance the column
function M.Parser:peek(pat)
  if self:isEof() then return nil end
  local c, c2 = self.line:find(pat, self.c)
  if c == self.c then
    return M.Token:encode(self, self.l, c, self.l, c2)
  end
end
function M.Parser:sub(t) --> string
  return lsub(self.dat, t:span())
end
function M.Parser:incLine()
  self.l, self.c = self.l + 1, 1
  self.line = get(self.dat,self.l)
end
function M.Parser:isEof() return not self.line end --> isAtEndOfFile
function M.Parser:skipEmpty()
  self.config.skipEmpty(self)
  return self:isEof()
end
--- get the current parser state [${l, c, line}]
function M.Parser:state() return {l=self.l, c=self.c, line=self.line} end
--- restore the current parser state [${l, c, line}]
function M.Parser:setState(st) self.l, self.c, self.line = st.l, st.c, st.line end
-- convert to token strings for test assertion
function M.Parser:toStrTokens(n)
  if not n then return nil end
  if ty(n) == M.Token then
    local t = self:tokenStr(n)
    return n.kind and {t, kind=n.kind} or t
  elseif #n == 0 then return n end
  local t={} for _, n in ipairs(n) do push(t, self:toStrTokens(n)) end
  t.kind=n.kind
  return t
end
--- recursively mutate table converting all Tokens to strings
function M.Parser:makeStrTokens(t) --> t
  for k, v in pairs(t) do
    if ty(v) == M.Token       then t[k] = self:tokenStr(v)
    elseif type(v) == 'table' then self:makeStrTokens(v) end
  end
  return t
end
function M.Parser:tokenStr(t) return t:decode(self.dat) end --> string
-- recurse through the start of list and trim the start of first token
function M.Parser:trimTokenStart(list)
  local t, list = M.firstToken(list); assert(list)
  if type(t) == 'string' then return end
  local l1, c1, l2, c2 = t:span()
  local line = get(self.dat,l1)
  local s = self:tokenStr(t); c1 = line:find('[^ ]', c1) or c1
  list[1] = M.Token:encode(self, l1, c1, l2, c2)
end

-- recurse through the end of list and trim the end of last token
function M.Parser:trimTokenLast(list, trimNl)
  local t, list = M.lastToken(list); assert(list)
  if not t or type(t) == 'string' then return end
  local l1, c1, l2, c2 = t:span()
  local line = get(self.dat,l2)
  while line:sub(c2,c2) == ' ' do c2 = c2 - 1 end
  if trimNl and l2 > l1 and c2 == 0 then
    l2 = l2 - 1; c2 = #get(self.dat,l2)
  end
  list[#list] = M.Token:encode(self, l1, c1, l2, c2)
end

local function fmtStack(p)
  local b = {}; for i, v in ipairs(p.stack) do
    if v == true then -- skip
    else
      if type(v) ~= 'string' then v = fmt(v) end
      push(b, sfmt('%s(%s.%s)', v, p.stackL[i], p.stackC[i]))
    end
  end
  local x, y, z = unpack(p.stackLast)
  push(b, sfmt('%s(%s.%s)', x, y or '?', z or '?'))
  return concat(b, '\n  ')
end
function M.Parser:checkPin(pin, expect)
  if not pin then return end
  if self.line then self:error(fmt.format(
    "parser expected: %q\nGot: %s",
    expect, self.line:sub(self.c))
  )else self:error(
    "parser reached EOF but expected: "..fmt(expect)
  )end
end
function M.Parser:error(msg)
  local lmsg = sfmt('[LINE %s.%s]', self.l, self.c)
  local err = fmt.format("ERROR\nPath: %s\n%s%s\n%s\nCause: %s\nParse stack:\n  %s",
    rawget(self.dat, 'path') or self.path or '(rawdata)',
    lmsg, self.line or '(eof)', srep(' ', #lmsg + self.c - 1)..'^',
    msg, fmtStack(self))
  if not self.firstError then self.firstError = {l=self.l, c=self.c, err} end
  if not self.config.lenient then error(err) end
  log.warn('lenient parsing error (%i.%i): %s', self.l, self.c, msg)
end

function M.Parser:parseAssert(spec)
  local n = self:parse(spec); if not n then return self:error(fmt.format(
    "parser expected: %q\nGot: %s",
    spec, self.line:sub(self.c))
  )end
  return n
end

function M.Parser:dbgEnter(spec)
  push(self.stack, spec.kind or spec.name or true)
  push(self.stackL, self.l); push(self.stackC, self.c)
  if not self.config.dbg then return end
  self:dbg('ENTER: %s', fmt(spec))
  self.dbgLevel = self.dbgLevel + 1
end

function M.Parser:dbgLeave(n)
  local sl = self.stackLast
  sl[1], sl[2], sl[3] = pop(self.stack), pop(self.stackL), pop(self.stackC)
  if not self.config.dbg then return n end
  self.dbgLevel = self.dbgLevel - 1
  self:dbg('LEAVE: %s(%s.%s)', fmt(n or sl[1]), sl[2], sl[3])
  return n
end
function M.Parser:dbgMatched(spec)
  if self.config.dbg then self:dbg('MATCH: %s', fmt(spec)) end
end
function M.Parser:dbgMissed(spec, note)
  if self.config.dbg then self:dbg('MISS: %s%s', fmt(spec), (note or '')) end
end
function M.Parser:dbgUnpack(spec, t)
  if self.config.dbg then self:dbg('UNPACK: %s :: %s', fmt(spec), fmt(t)) end
end
function M.Parser:dbg(fmtstr, ...)
  if not self.config.dbg then return end
  local msg = sfmt(fmtstr, ...)
  fmt.print(sfmt('%%%s%s (%s.%s)',
    string.rep('* ', self.dbgLevel), msg, self.l, self.c))
end

local _10pat = M.Pat'[0-9]+'
local _16pat = '[a-fA-F0-9]+'
M.common = G.mod and G.mod'pegl.common' or {}

M.common.nameStr = '[%a_][%w_]*'

--- Most common programatic name: a non-decimal word
--- character followed by word characters.
M.common.name = M.Pat{M.common.nameStr, kind='name'}

--- Most common programatic ty name, with same rules
--- as normal name (but different context)
M.common.ty   = M.Pat{M.common.nameStr, kind='ty'}

--- base 2 number
--- Note: does not support negatives or decimals.
M.common.base2 = M.Pat{'0b[01]+', kind='base2'}

--- base 10 number, supporting negatives and decimals.
M.common.base10 = {kind='base10',
  M.UNPIN, M.Maybe'-', _10pat, M.Maybe{'.', _10pat}
}

--- base 16 number, supporting negatives and decimals.
M.common.base16 = {kind='base16',
  M.UNPIN, M.Maybe'-',  M.Pat('0x'.._16pat),
  M.Maybe{'.', M.Pat(_16pat)},
}

function M.isKeyword(t) return #t == 1 and t.kind == t[1] end

-- Debugging keywords(KW), names(N) and numbers(NUM/HEX)
M.testing = {}
local function KW(kw)    return {kw, kind=kw} end -- keyword
local neg, dot = KW'-', KW'.'
local function NumT(kind, t)
  if type(t) == 'string' then t = {t} end; assert(#t <= 3)
  return ds.extend({kind=kind, (t.neg and neg) or M.EMPTY, tostring(t[1])},
    t[2] and {dot, tostring(t[2])} or {M.EMPTY})
end
function M.testing.N(name)  return {name, kind='name'} end -- name
function M.testing.TY(ty)   return {ty,   kind='ty'} end -- ty
function M.testing.NUM(n)   return NumT('base10', n) end
function M.testing.HEX(h)   return NumT('base16', h) end
M.testing.KW = KW

-- formatting parsed so it can be copy/pasted
local function fmtKindNum(name, f, t)
  f:write(name..sfmt('{%s%s%s}',
    mty.eq(t[1],M.EMPTY) and '' or 'neg=1 ', t[2],
    (mty.eq(t[3],M.EMPTY) and '') or (','..t[4])
  ))
end
M.fmtKinds = {
  EOF   = function(f, t) f:write'EOF'   end,
  EMPTY = function(f, t) f:write'EMPTY' end,
  name  = function(f, t) f:write(sfmt('N%q',  t[1])) end,
  ty    = function(f, t) f:write(sfmt('TY%q', t[1])) end,
  base10 = function(...) fmtKindNum('NUM', ...) end,
  base16 = function(...) fmtKindNum('HEX', ...) end,
}
-- Override Fmt.table with an instance of this for copy/paste debugging
M.FmtPegl = mty'FmtPegl' {
  'kinds [table]: kind -> fmtFn', kinds=M.fmtKinds,
}
function M.FmtPegl:__call(f, t)
  if M.isKeyword(t) then f:write(sfmt('KW%q', t[1])); return end
  local fmtK = t.kind and self.kinds and self.kinds[t.kind]
  if fmtK then fmtK(f, t) else fmt.Fmt.table(f, t) end
end
M.Config.newFmt = function()
  local f = fmt.Fmt:pretty{}
  f.table = M.FmtPegl{}
  return f
end

return M
