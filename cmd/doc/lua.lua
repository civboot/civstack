local G = G or _G

local ERROR = [[
doc module requires global `mod` function/class, such as one of:

  require'pkg'()
  mod = require'pkg'.mod

See lib/pkg/README.md for details
https://github.com/civboot/civstack/tree/main/lib/pkg

Note: also requires PKG_LOC and PKG_NAMES globals to be defined.
]]

local M = mod and mod'doc.lua' or error(ERROR)

local Keyword = {
  __name='keyword', __tostring = function() return 'keyword' end
}
function M.keyword() return setmetatable({}, Keyword) end

local function undocumented(name)
  local t = {}
  for k, v in pairs(_G[name]) do local k=k
    k = name..'.'..k; if not rawget(M, k) then t[k] = v end
  end
  return t
end

do
  local function makemod(name)
    local m = G[name]
    setmetatable(m, getmetatable(m) or {__name='Mod<'..name..'>'})
  end

  makemod'coroutine'
  makemod'debug'
  makemod'io'
  makemod'math'
  makemod'os'
  makemod'package'
  makemod'string'
  makemod'table'
  makemod'utf8'
end

--------------------
-- Global Functions

--- Get the next key in the table. Used for iterating through tables.
--- If [$key=nil] returns the first key. Returns [$nil] when [$key] is
--- the last key.
M.next = next--(tbl, key) --> nextKey

--- call a function but catch errors. Returns [$ok] followed by the function
--- results. If not ok, returns the error.
M.pcall = pcall--(fn, ...) --> ok, fn(...)

--- select elements in varargs [$...] at and after index.
---
--- Special value: if [$index='#'] then returns length of [$...]
M.select = select--(index, ...) -> ...

--- Get the type of [$val]. Possible return values are: [+
---   * data: nil number string boolean table
---   * other: function thread userdata
--- ]
--- [" See also: metaty.ty(v) for metatypes]
M.type = type--(val) --> string

--- Sets the metatable on the table which can get gotten with
--- [$getmetatable] and affects the behavior of operators.
---
--- All metamethods: [$$
--- __index    (i.e. t[k])     NOTE: these are only called
--- __newindex (i.e. t[k] = v)       when key is missing!
---
--- __call     (i.e. t())
--- __tostring (i.e. tostring(t))
---
--- +         -        *        /       //        %
--- __add     __sub    __mul    __div   __idiv    __mod
---           __unm
---
--- &         |        ~        <<      >>        ^
--- __band    __bor    __bnot   __shl   __shr     __pow
---
--- ==        <        <=       #        ..
--- __eq      __lt     __le     __len    __concat
---
--- __name
--- ]$
---
--- [" See also metaty metamethods: __fields   __fmt]
M.setmetatable = setmetatable-->(t, mt) -> t

--- See setmetatable.
M.getmetatable = getmetatable--(t) --> mt

--- Convert any value to a string by calling __tostring or using lua's default.
M.tostring = tostring--(v) --> string

-------------------------------
-- string
--- the builtin lua string module.
---
--- string literal values can use [+
---   * [$'single quotes']
---   * [$"double quotes"]
---   * [$$[==[raw string with any number of = symbols ]==]]$
--- ]
---
--- [$\] characters can be used to escape special characters,
--- except in raw bracketed strings. Common escaped characters
--- are [$\'] (literal [$']), [$\n] (newline) and [$\t] (tab).
M.string = string

--- concatenate all items in ... with sep.
---
--- Note: this is an addon to from metaty.
M['string.concat'] = string.concat--(sep, ...) --> string

--- Find the pattern in the subj (subject) string, starting at the index.
--- returns the si (start index), ei (end index) and match groups
--- (see [<#string.match>]).
---
--- [{$$ lang=lua}
--- T.eq({2, 4},       {find('%w+', ' bob is nice')})
--- T.eq({2, 7, 'is'}, {find(' bob is nice', '%w+ (%w+)')})
--- ]$
---
--- Character classes for matching specific sets: [$$
---   .   all characters
---   %a  letters
---   %c  control characters
---   %d  digits
---   %l  lower case letters
---   %p  punctuation characters
---   %s  space characters
---   %u  upper case letters
---   %w  alphanumeric characters
---   %x  hexadecimal digits
---   %z  the character with representation 0
--- ]$
---
--- Magic characters, [$.] indicates one character, more indicates many
--- [$$
---   %.     selects a character class or escapes a magic char
---   (...)  create a group
---   [...]  create your own character class
---   [^..]  inversion of [...]
---   +.     match one or more of previous class  (NOT group)
---   *.     match zero or more of previous class (NOT group)
---   ?      match zero or one of previous class  (NOT group)
---   ^...   if at pat[1], match only beggining of text
---   ...$   if at pat[#pat], match only end of text
---   %1-9   matches the previously matched group index EXACTLY
--- ]$
M['string.find'] = string.find--(subj, pat, index=1) --> (si, ei, ...matches)

--- Return the capture groups of pat or the whole match if no capture groups.
--- index: where to start the search and can be negative.
---
--- See also: string.find.
M['string.match'] = string.match--(subj, pat, index=1) --> ...groups


--- Return an iterator function that when called returns the next capture group.
--- index: where to start the search and can be negative.
---
--- See also: string.find.
M['string.gmatch'] = string.gmatch--(subj, pat, index=1) --> iterator()

--- Return substring by index. [$("1234"):sub(3,4) == "34"]
---
--- ["Note: This is confusingly named considering string.gsub uses pattern
---         matching. Such is life.]
M['string.sub'] = string.sub--(subj, si, ei) --> str[si:ei]

--- Substittue all matches of pattern with repl, returning the new string.
---
--- [$repl] can be a: [+
---  * [@string]: replace with the string except [$%1-9] will be
---    a matched group from [$pat] and [$%%] is a literal [$%].
---  * [@table]: the table will be queried for every match using
---    the first capture as key.
---  * [$function(...matches) -> string]: the function will be called
---    with all match groups for each match.
--- ]
---
--- See also: string.find for pattern documentation.
M['string.gsub'] = string.gsub--(subj, pat, repl, index=1) --> string

--- Format values into a fmt string, i.e: [$format('%s: %i', 'age', 42)]
---
--- Directives: [{table}
---   + [$%%] | literal % char
---   + [$%d] | decimal
---   + [$%o] | octal
---   + [$%x] | hexidecimal (%X uppercase)
---   + [$%f] | floating point
---   + [$%s] | string
--- ]
---
--- Directive control structure (ignore spaces): [$$
---   % (specifier width)? directive
--- ]$
---
--- Where [$width] is an integer and [$specifier] can be one of [{table}
---   + [$+] | right justify to width (the default)
---   + [$-] | left justify to width
---   + [$ ] | prefix a positive number with a space
---   + [$#] | prefix o, x or X directives with 0, 0x and 0X respectively
---   + [$0] | left-pad a number with zeros
--- ]
---
--- Examples: [{$$ lang=lua}
---   sfmt = string.format
---   T.eq('age: 42',    sfmt('%s: %i',   'age', 42))
---   T.eq('age:    42', sfmt('%s: %5i',  'age', 42))
---   T.eq('age: 42   ',     sfmt('%s: %-5i', 'age', 42))
---   T.eq('age: 00042', sfmt('%s: %05i', 'age', 42)
--- ]$
M['string.format'] = string.format--(fmt: str, ...) --> str

--- Get ASCII (integer) codes for [$$s[si:ei]]$.
---
--- Example: [$T.eq({98, 99}, {string.byte('abcd', 2, 3)})]
M['string.byte'] = string.byte--(str, si=1, ei=si) --> ...ints

--- convert character codes to string and concatenate
M['string.char'] = string.char-- char(c1, c2, ...) --> string

--- repeat str n times with separator
M['string.rep'] = string.rep-- rep(str, n, sep) -> string

--- pack the values as bytes into the string using the strtys.
---
--- strtys is a string of the form: [{table}
---   + [$ <  >  =] | (start only) little / big / native endian
---   + [$ !#     ] | (start only) max alignment = [$#] bytes
---   + [$ b B    ] | signed / unsigned byte
---   + [$ h H l L] | native short(h) and long(l) + unsigned vers
---   + [$ i# I#  ] | signed/unsigned int with [$#] bytes
---   + [$ f d    ] | native float / double
---   + [$ T      ] | size_t
---   + [$ c#     ] | fixed-sized string of [$#] bytes (unaligned)
---   + [$ z      ] | zero-terminated string        (unaligned)
---   + [$ s#     ] | counted string of size [$#] bytes
---   + [$ x      ] | one byte of padding
---   + [$ Xo     ] | align to option [$o], i.e. [$Xi4]
---   + [$ j J n  ] | lua Integer / Unsigned / Number
--- ]
---
--- Example: [{$$ lang=lua}
--- T.eq(string.pack('>i2i2', 0x1234, 0x5678) == '\x12\x34\x56\x78')]
--- ]$
M['string.pack'] = string.pack--(strtys, ...values) -> string

--- See [@string.pack] for the fmt
M['string.unpack'] = string.unpack--(strtys, str) -> ...

--- Get the size which is used by strtys.
M['string.packsize'] = string.packsize--(strtys) -> int

--- not documented: see [$string] module
for k, v in pairs(undocumented'string') do M[k] = v end

-------------------------------
-- table
--- the builtin lua table module
---
--- Tables act as BOTH a map (of keys -> values) and a list (ordered values
--- starting at index=1).
---
--- You can access the keys with [$$t[key]]$ or if they are a string without
--- special characters with [$t.key].
---
--- Examples: [{$$ lang=lua}
--- t = {'first', 'second', 'third', key='hi'}
--- T.eq('first', t[1])
--- T.eq('third', t[3])
--- T.eq('hi',    t.key)
--- T.eq(#t, 3) -- the length of the "list" part
--- ]$
---
--- [" WARNING: A table's length is defined as ANY index who's next value
---   is [$nil`]. That means using a table as a list with "holes" likely
---   won't work for you.
--- ]
M.table = table

--- update to with from, return to.
---
--- Note: this is an addon from metaty.
M['table.update'] = table.update--(to, from) --> to

--- concatenate a table of strings with optional separator.
---
--- Examples: [{$$ lang=lua}
--- concat = table.concat
--- T.eq(1..' = '..3, concat{1, ' = ', 3})
--- T.eq('1, 2, 3',   concat({1, 2, 3}, ', ')
--- ]$
M['table.concat'] = table.concat--(t, sep='') --> string

--- remove an item from a table, returning it.
--- The table is shifted if index < #table which may cost up to O(n)
M['table.remove'] = table.remove--(t, index=#table) --> t[index]

--- sort a table in place using a comparison function [$cmp] who's behavior
--- must be: [$cmp(a, b) --> makeAFirst]
M['table.sort'] = table.sort--(list, cmp=lt) --> nil

--- insert or push to table (list-like)
---
--- Example: [{$$ lang=lua}
--- local push = table.insert
--- local t = {}
---
--- -- push/append behavior
--- push(t, 'd')            -- {'d'
--- push(t, 'e')            -- {'d', 'e'}
---
--- -- insert behavior
--- table.insert(t, 'b', 1) -- {'b', 'd', 'e'}
--- table.insert(t, 'c', 2) -- {'b', 'c', 'd', 'e'}
--- T.eq({'b', 'c', 'd', 'e'}, t)
--- ]$
M['table.insert'] = table.insert

--- Move values from one list to another.
--- Note that [$si=startIndex] and [$ei=endIndex] (inclusive).
---
--- Equivalent to the following, though done in a way
--- that will properly handle overlapping data: [{$$ lang=lua}
--- ti = siTo
--- for fi=siFrom,eiFrom do
---   to[ti] = from[fi]; ti = ti + 1
--- end
--- ]$
M['table.move'] = table.move --(from, siFrom, eiFrom, siTo, to=from) -> to

-------------------------------
-- io module

--- the builtin lua io (input/output) module
---
--- Module Functions: [{table}
--- + [$ input(file=nil)  ->  file  ]   |  get/set stdin
--- + [$ output(file=nil) ->  file  ]   |  get/set stdout
--- + [$ tmpfile() -> file          ]   |  note: removed on program exit
--- + [$ popen()   -> file          ]   |  see io.popen
--- + [$ lines(path or file) -> iter]   |  close when done, fail=error
--- + [$$ type(f) -> "[closed ]file" ]$ |  get whether f is a file
--- ]
---
--- File Methods: [{table}
--- + [$ read(format="l")  ] | read a file according to format
--- + [$ lines(format="l") ] | get iterator for reading format
--- + [$ write(a, b, ...)  ] | write strings a, b, ... in order
--- + [$ flush()           ] | flush (save) all writes
--- + [$ seek(whence, offset)] | see seek section below
--- + [$ setvbuf("no|full|line", sizeHint=appropriateSize)] see function
--- ]
---
--- Format paramater used in read/etc [{table}
--- + format |  behavior                | (in Lua<=5.2)
--- + a      |  read all text                        *a
--- + l      |  read next line, skip EOL             *l
--- + L      |  read next line, keep EOL             *L
--- + n      |  read and return a number             *n
--- + number |  read an exact number of bytes, EOF=nil
--- + 0      |  EOF=nil, notEOF=''
--- ]
---
--- seek [{table}
--- + [$ whence="set" ] | offset from beginning of file (0)
--- + [$ whence="cur" ] | offset from current position
--- + [$ whence="end" ] | offset from end of file (use negative)
--- + [$ seek()       ] | get current position
--- + [$ seek'set'    ] | set to beginning
--- + [$ seek'end'    ] | set to end
--- ]
M.io = io

--- Execute shell command in separate process.
---
--- See also: [+
---   * [$os.execute()]: docs on file:close()
---   * [/lib/civix][$.sh()]: ergonomic blocking shell.
--- ]
M['io.popen'] = io.popen--(command, mode='r|w') -> file

--- not documented: see [$io] module
for k, v in pairs(undocumented'io') do M[k] = v end

-------------------------------
-- os module

--- the builtin lua os module
---
--- Useful functions: [{table}
--- + [$exit(rc=0, close=false)] | exit program with return code
--- + [$date()]                  | get the date. See os.date
--- + [$execute'command']        | execute command, see os.execute
--- + [$getenv(varname)]         | get environment variable
--- + [$remove(path)]            | rm path
--- + [$rename(old, new)]        | mv old new
--- + [$tmpname() -> path]       | create temporary file
--- + [$clock()]                 | seconds used by process (performance)
--- ]
---
--- Recommendations: [+
--- * use civix.epoch() (nanosec precision) vs os.time() (sec precision)
--- ]
M.os = os

--- Execute shell command via C's `system` API. Returns: [+
---   * ok:      true on command success, false if rc>0
---   * "exit":  always literal "exit" if command completed
---   * rc:      the return code of the command
--- ]
--- [{$$ lang=lua}
---   os.execute'shell command' -> (ok, "exit", rc)
---   os.execute()              -> isShellAvailable
--- ]$
---
--- Prints whatever was executed. There are no ways to
--- redirect the output besides piping in the command
--- string itself.
---
--- Recommendation:
---   For all but the simplest cases use io.popen instead
M['os.execute'] = os.execute--(string) --> (ok, "exit", rc)

--- not documented: see [$os] module
for k, v in pairs(undocumented'os') do M[k] = v end

-------------------------------
-- math
--- The builtin lua math module.
M.math = math

M['math.type'] = math.type--(v) --> ("float" | "integer" | nil)
M['math.max']  = math.max --(x, ...) --> max according to [$<]
M['math.min']  = math.min --(x, ...) --> min according to [$<]
M['math.cos']  = math.cos  --(x) --> cos(x) in radians
M['math.sin']  = math.sin  --(x) --> sin(x) in radians
M['math.tan']  = math.tan  --(x) --> tan(x) in radians
M['math.acos'] = math.acos --(x) --> arccos(x) in radians
M['math.asin'] = math.asin --(x) --> arcsin(x) in radians
M['math.atan'] = math.atan --(n, d) --> arctan(n / d) in radians
M['math.exp'] = math.exp --(x) --> e^x (where e is the natural log base)
--- the maximum value for a Lua integer
M['math.maxinteger'] = math.maxinteger
--- the maximum value of any other numeric valuej
M['math.huge'] = math.huge

--- currently not documented
for k, v in pairs(undocumented'math') do M[k] = v end

--- [$type] which will return
---
---

---------------------
-- Keywords

--- for is a looping construct with two forms:
---
--- Numeric: [{$$ lang=lua}
---   for i=si,ei,period do -- period=1 by default
---     ... do something with i
---   end
---
---   -- is basically the same as
---   local i = si
---   while i <= ei do i = i + si
---     ... do something with i
---   end
--- ]$
---
--- Generic: [{$$ lang=lua}
---   for i, v, etc in (nextfn, state, _index) do
---     .. do something with i, v, ...
---   end
---
---   -- is almost the same as
---   while true do
---     local i, v, etc = nextfn(state, _index)
---     if i == nil then break end
---     _index = i -- note: C internal, _index from lua doesn't change
---     ... code using i, v, etc here
---   end
--- ]$
---
--- The goal in writing a stateless iterator function is to match this
--- loop's API as much as possible.
---
--- Example rewriting ipairs: [{$$ lang=lua}
---   local function rawipairs(t, i)
---     i = i + 1
---     if i > #t then return nil end
---     return i, t[i]
---   end
---   local function myipairs_(t)
---     return rawipairs, t, 0
---   end
---   for i, v in myipairs{5, 6, 7} do
---     iterates through (1, 5) -> (2, 6) -> (3, 7)
---   end
--- ]$
---
--- Example rewriting pairs using [$next(t, key)]: [{$$ lang=lua}
---   function mypairs(t)
---     return next, t, nil
---   end
---   for k, v in mypairs{a=1, b=2, c=3} do
---     iterates through ('a', 1) -> ('b', 2) -> ('c', 3)
---   end
--- ]$
---
--- See also: [@metaty.split] is a more complex example.
M['for'] = function() end
PKG_LOOKUP['for'] = M['for']

--- [$local x = (expression)]
---
--- Define a local (instead of a global) variable. Prefer local variables for
--- most things unless you are: [+
--- * modifying the fundamentals of the language (i.e. replacing 'require')
--- * implementing a "protocol" for libraries to communicate global state
--- * managing true physical state (i.e. robotics, terminal output, etc)
--- * you are the top-level application (i.e. a game, CLI, etc) and global state
---   is the best solution.
--- ]
M['local'] = M.keyword()
PKG_LOOKUP['local'] = M['local']

-- boolean [$true] value
M['true'] = M.keyword()
PKG_LOOKUP['true'] = M['true']

-- boolean [$false] value
M['false'] = M.keyword()
PKG_LOOKUP['false'] = M['false']

--- [$nil] value, the the absense of a value. Used for: [+
---   * a variable is not set or has been set to [$nil]
---   * a table key is not set or has been set to [$nil]
--- ]
M['nil'] = M.keyword()
PKG_LOOKUP['nil'] = M['nil']

-- store items in this module in PKG_* variables
for k, obj in pairs(M) do
  local name = PKG_NAMES[obj]
  if name then
    local newname = name:sub(9) -- remove "doc.lua."
    PKG_NAMES[obj] = newname
    PKG_LOOKUP[name] = nil; PKG_LOOKUP[newname] = obj
  end
end

return M
