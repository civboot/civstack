#include "ds.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

typedef lua_State LS;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// make a one-based-index be zero-based.
int index0(int i, size_t len) {
  if(i < 0) i = len + i;
  else      i = i - 1; // make zero-index.
  if(i < 0) i = 0;
  return i;
}

//***********
// C API

bytearray* bytearray_new(LS* L) {
  bytearray* b = (bytearray*) lua_newuserdata(L, sizeof(bytearray));
  *b = (bytearray){0};
  luaL_setmetatable(L, LUA_BYTEARRAY);
  return b;
}
bytearray* bytearray_close(bytearray* b) {
  if(b && b->dat) { free(b->dat); *b = (bytearray){0}; }
}

bytearray* asbytearray(LS* L, int index) {
  bytearray* b = luaL_testudata(L, index, LUA_BYTEARRAY);
  if(!b) luaL_error(L, "arg %I not a bytearray", index);
  return b;
}

bool bytearray_grow(bytearray* b, size_t sz) {
  if(sz <= b->sz) return true;
  sz += sz % 8; // make divisible by 8
  if(sz < (b->sz * 2)) sz = b->sz * 2; // at least double size
  uint8_t* dat = realloc(b->dat, sz); if(dat == NULL) return false;
  b->dat = dat; b->sz = sz;
  return true;
}

bool bytearray_extend(bytearray* b, uint8_t* dat, size_t len) {
  if(!bytearray_grow(b, b->len + len)) return false;
  memcpy(b->dat + b->len, dat, len);
  b->len += len;
  return true;
}

//***********
// Lua API

// concat(sep, ...) --> string
// concatenate all values (calling tostring on them) separated by sep.
static inline int l_string_concat(LS* L) {
  size_t slen; uint8_t const* sep = luaL_checklstring(L, 1, &slen);
  int lasti = lua_gettop(L);
  if(lasti == 1) { lua_pushstring(L, ""); return 1; }
  size_t vlen;
  // First compute the size and allocate the exact space we need
  size_t size = slen * (lasti - 2);  // size of all separators
  for(int i=2; i <= lasti; i++) {
    ASSERT(L, lua_tolstring(L, i, &vlen), "arg[%I] is not a string or number", i)
    size += vlen;
  }
  luaL_Buffer lb;
  char* b = luaL_buffinitsize(L, &lb, size); ASSERT(L, b, "OOM");
  const char* v = lua_tolstring(L, 2, &vlen);
  memcpy(b, v, vlen); b += vlen;
  for(int i = 3; i <= lasti; i++) {
    memcpy(b, sep, slen); b += slen;
    v = lua_tolstring(L, i, &vlen);
    memcpy(b, v, vlen); b += vlen;
  }
  luaL_pushresultsize(&lb, size);
  return 1;
}

// (t, update) -> t
static int l_update(LS* L) {
  if(!lua_istable(L, 1)) luaL_error(L, "arg[1] must be table");
  if(!lua_istable(L, 2)) luaL_error(L, "arg[2] must be table");
  lua_settop(L, 3); lua_pushnil(L); // stack: t, upd, k, nil
  while(lua_next(L, 2)) { // iterate through update
    lua_copy(L, 4, 3); lua_settable(L, 1);
    lua_pushnil(L);    lua_copy(L, 3, 4);
  }
  lua_settop(L, 1);
  return 1;
}

// push v to the end of table, returning the index
// (t, v) --> index
static int l_push(LS* L) {
  if(!lua_istable(L, 1)) luaL_error(L, "arg[1] must be table");
  lua_len(L, 1); lua_Integer i = lua_tointeger(L, -1) + 1;
  lua_settop(L, 2); lua_seti(L, 1, i);
  lua_pushinteger(L, i); return 1;
}

//***
// Bytearray

static int l_bytearray_extend(LS* L) { // --> bytearray
  int top = lua_gettop(L); uint8_t* s; size_t len;
  bytearray* b = asbytearray(L, 1);
  size_t extend_len = 0;
  // Grow the bytearray first
  for(int i = 2; i <= top; i++) {
    ASSERT(L, lua_tolstring(L, i, &len), "arg %I is not a string", i);
    extend_len += len;
  }
  ASSERT(L, bytearray_grow(b, b->len + extend_len), "OOM");
  // Then add data.
  for(int i = 2; i <= top; i++) {
    s = (uint8_t*)lua_tolstring(L, i, &len);
    ASSERT(L, bytearray_extend(b, s, len), "unreachable");
  }
  lua_settop(L, 1);
  return 1;
}

static int l_bytearray_call(LS* L) {
  bytearray* b = bytearray_new(L);
  lua_replace(L, 1);
  l_bytearray_extend(L);
  ASSERT(L, b, "failed to allocate new bytearray");
  return 1;
}

// b:len() -> len        : when called with no args returns len
// b:len(10, ' ') -> len : sets len to 10, filling with spaces.
static int l_bytearray_len(LS* L) {
  bytearray* b = asbytearray(L, 1);
  if(!lua_isinteger(L, 2)) { // bug: #b passes b twice (lua 5.8).
    lua_pushinteger(L, b->len);
    return 1;
  }
  int len = luaL_checkinteger(L, 2);
  if(len > b->len) {
    const uint8_t* fill = luaL_optstring(L, 3, ""); // default=0 char
    bytearray_grow(b, len);
    memset(b->dat + b->len, fill[0], len - b->len);
  }
  b->len = len; lua_pushinteger(L, len);
  return 1;
}
static int l_bytearray_size(LS* L) {
  lua_pushinteger(L, asbytearray(L, 1)->sz); return 1;
}
static int l_bytearray_pos(LS* L) {
  bytearray* b = asbytearray(L, 1);
  if(lua_isnumber(L, 2)) {
    int pos = lua_tointeger(L, 2);
    if(pos < 0) {
      pos += b->len;
      if(pos < 0) pos = 0;
    }
    b->pos = (pos > b->len) ? b->len : pos;
  }
  lua_pushinteger(L, b->pos);
  return 1;
}

static int l_bytearray_tostring(LS* L) {
  bytearray* b = asbytearray(L, 1);
  lua_pushlstring(L, b->dat, b->len);
  return 1;
}

static int l_bytearray_sub(LS* L) {
  bytearray* b = asbytearray(L, 1);
  size_t len = b->len;
  int si = index0(luaL_optinteger(L, 2, 1), len);

  // note: ei is inclusive, so is effectively 0-index already.
  int ei = luaL_optinteger(L, 3, len); 
  if(ei < 0)        ei = len + ei + 1;
  if(ei < 0)        ei = 0;
  else if(ei > len) ei = len; 

  if(si >= ei) lua_pushstring(L, "");
  else         lua_pushlstring(L, b->dat + si, ei - si);
  return 1;
}

// replace b[i:i+#str] with str, growing b if needed.
// (b, i, str) --> nil
static int l_bytearray_replace(LS* L) {
  bytearray* b = asbytearray(L, 1);
  int si = index0(luaL_checkinteger(L, 2), b->len);
  size_t len; const char* s = luaL_checklstring(L, 3, &len);
  size_t ei = si + len;
  bytearray_grow(b, ei);
  memcpy(b->dat + si, s, len);
  if(ei > b->len) b->len = ei;
  return 0;
}

static int l_bytearray_close(LS* L) {
  bytearray_close(asbytearray(L, 1));
  return 0;
}

static int bytearray_read(LS* L, bytearray* b, int num) {
  int ei = b->pos + num;
  if(ei > b->len) ei = b->len;
  lua_pushlstring(L, b->dat + b->pos, ei - b->pos);
  b->pos = ei;
  return 1;
}

// File-like read. Does not support  "n"
// (b, opt) --> str
static int l_bytearray_read(LS* L) {
  bytearray* b = asbytearray(L, 1);
  if(b->pos >= b->len) return 0;
  if(lua_isnumber(L, 2))
    return bytearray_read(L, b, lua_tointeger(L, 2));
  size_t len; const uint8_t* opt = luaL_optlstring(L, 2, "l", &len);
  ASSERT(L, len > 0, "invalid read opt: %s", opt);
  switch(opt[len-1]) {
    case 'n': luaL_error(L, "read 'n' not supported");
    case 'a': return bytearray_read(L, b, b->len);
    case 'l':
    case 'L': break;
    default: luaL_error(L, "invalid read opt: %s", opt);
  }
  uint8_t incl = (opt[len-1] == 'l') ? 0 : 1; // incl newline
  uint8_t* dat = b->dat;
  for(size_t i = b->pos; i < b->len; i++) {
    if(dat[i] == '\n') {
      bytearray_read(L, b, i - b->pos + incl);
      if(!incl) b->pos += 1;
      return 1;
    }
  }
  return bytearray_read(L, b, b->len); // newline not found, return rest.
}

// (b, string...) --> b
static int l_bytearray_write(LS* L) {
  int top = lua_gettop(L);
  bytearray* b = asbytearray(L, 1);
  size_t len; const uint8_t* s;
  size_t write_len = 0;
  for(int i=2; i <= top; i++) {
    lua_tolstring(L, i, &len);
    write_len += len;
  }
  ASSERT(L, bytearray_grow(b, b->pos + write_len), "OOM");
  uint8_t* dat = b->dat + b->pos;
  for(int i=2; i <= top; i++) {
    s = lua_tolstring(L, i, &len);
    // fprintf(stderr, "@@ ds.c: %.*s\n", s, len);
    memcpy(dat, s, len);
    dat += len;
  }
  b->pos += write_len;
  if(b->pos > b->len) b->len = b->pos;
  return 1;
}

static const struct luaL_Reg ds_lib[] = {
  {"string_concat", l_string_concat},
  {"update", l_update},
  {"push",   l_push},
  {NULL, NULL},
};

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_ds_lib(LS *L) {
  luaL_newlib(L, ds_lib);

  luaL_newmetatable(L, LUA_BYTEARRAY);
    // bytearray fields/metamethods
    L_setmethod(L, "__gc",       l_bytearray_close);
    L_setmethod(L, "__tostring", l_bytearray_tostring);
    L_setmethod(L, "__len",      l_bytearray_len);
    lua_pushstring(L, "bytearray"); lua_setfield(L, -2, "__name");

    lua_newtable(L); // bytearray metatable
      lua_pushstring(L, "bytearray type"); lua_setfield(L, -2, "__name");
      L_setmethod(L, "__call", l_bytearray_call); // constructor
    lua_setmetatable(L, -2);

    // fields
    L_setmethod(L, "len",        l_bytearray_len);
    L_setmethod(L, "size",       l_bytearray_size);
    L_setmethod(L, "pos",        l_bytearray_pos);

    L_setmethod(L, "extend",     l_bytearray_extend);
    L_setmethod(L, "sub",        l_bytearray_sub);
    L_setmethod(L, "replace",    l_bytearray_replace);

    L_setmethod(L, "read",       l_bytearray_read);
    L_setmethod(L, "write",      l_bytearray_write);
    L_setmethod(L, "close",      l_bytearray_close);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "bytearray");
  return 1;
}

