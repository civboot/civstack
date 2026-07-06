#include <stdlib.h>

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <unistd.h>
#include <pthread.h>
#include <fcntl.h>
#include <assert.h>
#include <poll.h>
#include <sys/stat.h>
#include "fd.h"

//***********************
//* APPLE
#if __APPLE__
#include <sys/socket.h>
static char EFD_BUF = 0;
#define EV_INIT(FDT)    do { int* s = (FDT)->socks; \
                             s[0] = -1; s[1] = -1; } while(0)
#define EV_OPEN(FDT) socketpair(AF_UNIX, SOCK_STREAM, 0, (FDT)->socks)
static void EV_POST(FDT* fdt) {
  assert( read(fdt->socks[0], &EFD_BUF, 1) == 1);
  assert(write(fdt->socks[0], &EFD_BUF, 1) == 1);
}
static void EV_WAIT(FDT* fdt) {
  assert(write(fdt->socks[1], &EFD_BUF, 1) == 1);
  assert( read(fdt->socks[1], &EFD_BUF, 1) == 1);
}
#define EV_FILENO(FDT) (FDT)->socks[0]
#define EV_DESTROY(FDT) if((FDT)->socks[0] >= 0) { \
  int* s = (FDT)->socks; \
  close(s[0]); s[0] = -1; \
  close(s[1]); s[1] = -1; \
}

//***********************
//* Linux / BSD
#else
#include <sys/eventfd.h>
static const uint64_t EFD_WRITE = 0xfffffffffffffffeUL;
static uint64_t EFD_READ = 0;
#define EFD_OK 8
#define EV_INIT(FDT) (FDT)->evfd = -1;
#define EV_OPEN(FDT) ((FDT)->evfd = eventfd(1, 0))
#define EV_POST(FDT) assert(read((FDT)->evfd,  &EFD_READ, 8)  == EFD_OK)
#define EV_WAIT(FDT) assert(write((FDT)->evfd, &EFD_WRITE, 8) == EFD_OK)
#define EV_FILENO(FDT) (FDT)->evfd
#define EV_DESTROY(FDT) if((FDT)->evfd >= 0) \
  { close((FDT)->evfd); (FDT)->evfd = -1; }
#endif

#define FD_EOF     (-1)
#define FD_RUNNING (-2)
#define LEN(FD)  ((FD)->ei - (FD)->si)

typedef lua_State LS;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// ----------------------
// -- FD CREATE / CLOSE

// Create a FD object
static void FD_init(FD* fd) {
  fd->code = 0; fd->fileno = -1;
  fd->pos = 0;  fd->fpos = 0;
  fd->size = 0; fd->si = 0; fd->ei = 0;
  fd->buf = NULL;
}
FD* FD_create(LS* L) {
  FD* fd = (FD*)lua_newuserdata(L, sizeof(FD));
  FD_init(fd);
  luaL_setmetatable(L, LUA_FD);
  return fd;
}
void FD_free(FD* fd) {
  if(fd->size) { free((char*)fd->buf); fd->size = 0; }
}

void FD_close(FD* fd) {
  if(fd->fileno >= 0) {
    close(fd->fileno); fd->fileno = -1;
  }
  FD_free(fd);
  fd->code = 0;
}

// ----------------------
// -- FDT CREATE / CLOSE
static void* FDT_run(void* d) {
  FDT* fdt = (FDT*) d;
  uint64_t unused;
  while(true) {
    EV_WAIT(fdt);
    if(fdt->stopped) break;
    fdt->meth(&fdt->fd);
  }
  fdt->stopped = 2;
  return NULL;
}

FDT* FDT_create(LS* L) {
  FDT* fdt = (FDT*)lua_newuserdata(L, sizeof(FDT));
  FD_init(&fdt->fd); fdt->meth = NULL; fdt->stopped = 0;
  EV_INIT(fdt);
  luaL_setmetatable(L, LUA_FDT);
  if(EV_OPEN(fdt) < 0) goto error;
  if (pthread_create(
        &fdt->th, /*attr=*/ NULL,
      /*start_routine=*/FDT_run, /*arg=*/(void*)fdt)) {
    goto error;
  }
  return fdt;
error:
  fdt->stopped = 3; fdt->fd.code = errno;
  EV_DESTROY(fdt);
  return fdt;
}

// ----------------------
// -- FD ALLOCATE / DESTROY
// These methods are the logic used for both the threaded
// and non-threaded implementaiton of filedescriptors.
#define IO_SIZE   16384

static void FD_realloc(FD* fd, int size) {
  if(fd->size == 0) fd->buf = NULL;
  if(size < IO_SIZE) size = IO_SIZE;
  char* buf = realloc((char*)fd->buf, size);
  if(!buf) return FD_free(fd);
  fd->buf = buf; fd->size = size;
}

// ----------------------
// -- METHODS
// FD calls these semi-directly. FDT calls them through
// the thread.

// open buf, flags=ctrl
static void FD_open(FD* fd) {
  int code = 0, pos = 0;
  fd->fileno = open((char*)fd->buf, fd->ctrl, 0666);
  if(fd->fileno >= 0) {
    if(fd->ctrl & O_APPEND) {
      pos = lseek(fd->fileno, 0, SEEK_END);
      if(pos < 0) { pos = 0; code = errno; }
    }
  } else code = errno;
  fd->pos = pos; fd->fpos = pos; fd->code = code;
}

static void FD_tmp(FD* fd) {
  FILE* f = tmpfile();         if(!f)             goto error;
  fd->fileno = dup(fileno(f)); if(fd->fileno < 0) goto error;
  fclose(f); fd->code = 0;
  return;
error:
  if(f) fclose(f);
  fd->code = errno;
}


// find character index. If index==ei then not found.
static size_t FD_findc(FD* fd, size_t si, char c) {
  for(; si < fd->ei; si++) {
    if(c == fd->buf[si]) return si;
  }
  return fd->ei + 1;
}

// shift the buffer left, typically done before a
// read operation.
static void FD_shift(FD* fd) {
  if(fd->si == 0) return;
  if(fd->ei - fd->si > 0) {
    memmove((char*)fd->buf, (char*)fd->buf + fd->si, fd->ei - fd->si);
  }
  fd->ei -= fd->si; fd->si = 0;
}

// Read into buffer until EOF or error
// If ctrl < 0 then breaks at that negated character (i.e. '\n').
// if ctrl > 0 then stops reading when that amount is read
static void FD_read(FD* fd) {
  if(fd->size) FD_shift(fd);
  else         FD_realloc(fd, IO_SIZE);
  if(!fd->buf) { fd->code = errno; return; }
  int ctrl = fd->ctrl, code = 0;
  while(true) {
    if((ctrl > 0) && (LEN(fd) >= ctrl)) break;
    if(fd->size - fd->ei == 0) FD_realloc(fd, fd->size * 2);
    if(!fd->buf) { code = errno; break; }
    int rem = fd->size - fd->ei;
    int c = read(fd->fileno, (char*)fd->buf + fd->ei, rem);
    if(c < 0) { code = errno; break; }
    fd->ei += c;
    if(ctrl < 0) {
      int i = FD_findc(fd, fd->ei - c, (char) -ctrl);
      if(i <= fd->ei) break;
    }
    if(c == 0) { code = FD_EOF; break; } // EOF: signal to findc callers
  }
  fd->code = code;
}

// Write the contents of fd buf[si:ei)
//
// Note: size is unused and is typically zero to indicate
//   that buf is Lua owned.
static void FD_write(FD* fd) {
  if(fd->pos != fd->fpos) {
    off_t pos = lseek(fd->fileno, fd->pos, SEEK_SET);
    if(pos < 0) {
      fd->code = errno; return;
    }
    fd->pos = pos; fd->fpos = pos;
  }
  int c = write(fd->fileno, (char*)fd->buf + fd->si, LEN(fd));
  if(c >= 0) {
    fd->pos += c; fd->fpos = fd->pos;
    fd->si += c;  fd->code = 0;
  }
}

// attempt to seek using only buffer, else update FD.
// return true if complete (no syscall needed)
static bool FD_seekpre(FD* fd, off_t offset, int whence) {
  if((whence == SEEK_SET) && (offset == 0)) goto hard;
  off_t want = offset; switch(whence) {
    case SEEK_CUR /*1*/: want += fd->pos; // make absolute, fallthrough
    case SEEK_SET /*0*/:
      if((fd->pos <= want) && (want <= fd->pos + LEN(fd))) {
        fd->si += want - fd->pos; fd->pos = want;
        return true;
      } // fallthrough
  }
hard:
  fd->off = offset; fd->ctrl = whence;
  return false;
}

static void FD_seek(FD* fd) {
  off_t pos = lseek(fd->fileno, fd->off, fd->ctrl);
  if(pos == -1) { fd->code = errno; return; }
  fd->pos = pos; fd->fpos = pos;
  if(fd->size) { fd->si = 0; fd->ei = 0; } // read buffer only
  fd->code = 0;
}

static int _FD_flush(FD* fd) {
  struct stat sbuf = {0};
  if(fstat(fd->fileno, &sbuf))             return errno;
  if(sbuf.st_mode != S_IFREG)              return 0;
  if(fsync(fd->fileno))                    return errno;

  // Discard unused data that was read
  if((fd->size == 0) || LEN(fd) == 0)      return 0;
  if(lseek(fd->fileno, fd->pos, SEEK_SET)) return errno;
  fd->fpos = fd->pos; fd->si = 0; fd->ei = 0;
  return 0;
}
static void FD_flush(FD* fd) {
  fd->code = _FD_flush(fd);
}

// ----------------------
// -- FD/T LUA METHODS
// These are used by both FD and FDT

#define toFD(L) ((FD*)luaL_checkudata(L, 1, LUA_FD))
#define toFDT(L) ((FDT*)luaL_checkudata(L, 1, LUA_FDT))
#define fdGetFD(V)  (V)
#define fdGetFDT(V) (&(V)->fd)
static FD* asfd(LS* L) {
  FD* fd = luaL_testudata(L, 1, LUA_FD);  if(fd) return fd;
      fd = luaL_testudata(L, 1, LUA_FDT); if(fd) return fd;
  luaL_error(L, "arg 1 not FD or FDT"); return NULL;
}

static void assertReady(LS* L, FD* fd, const char* name) {
  ASSERT(L, fd->code >= FD_EOF, "%s while not ready", name);
}

// (fd, till=-1) -> string
//
// pop a string from the buffer. till can be:
//
// * zero: pop whole buffer
// * negative: pop the buffer until that character.
//     Return nil character not found.
// * positive: pop exactly that many characters or nil.
//
// note: if result would be '' returns nil instead
static int l_FD_pop(LS* L) {
  FD* fd = asfd(L); assertReady(L, fd, "pop");
  int till = luaL_optnumber(L, 2, 0);
  if(!fd->buf) { return 0; } // nil (no buffer)
  if(till == 0) till = fd->ei;
  else if(till < 0) {
    till = FD_findc(fd, fd->si, (char)(-till));
    if(till >= fd->ei) return 0; // nil (not found)
    till++; // include character in found
  } else {
    till += fd->si;
    if(till > fd->ei) return 0; // nil (not enough bytes)
  }
  if(till  == fd->si) return 0; // nil instead of empty
  lua_pushlstring(L, (char*)fd->buf + fd->si, till - fd->si);
  fd->pos += till - fd->si;
  fd->si = till;
  return 1;
}

static int l_FD_codestr(LS* L) {
  FD* fd = asfd(L);
  int code = lua_isnoneornil(L, 2)
      ? fd->code : lua_tointeger(L, 2);
  char* str; switch(code) {
    case  0: str = "FD_READY";   break;
    case -1: str = "FD_EOF";     break;
    case -2: str = "FD_RUNNING"; break;
    default: str = strerror(code);
  }
  lua_pushfstring(L, "%s [%I fd#%I]", str, code, fd->fileno);
  return 1;
}

#define FD_intfield(FIELD) \
  static int l_FD_##FIELD(LS* L) \
  { lua_pushinteger(L, asfd(L)->FIELD); return 1; } \

FD_intfield(code);
FD_intfield(fileno);
FD_intfield(pos);
FD_intfield(ctrl);
static int l_FDT_evfileno(LS* L)
{ lua_pushinteger(L, EV_FILENO(toFDT(L))); return 1; }

static int l_FD_setfileno(LS* L) {
  asfd(L)->fileno = luaL_checkinteger(L, 2); return 0;
}

// ----------------------
// -- FD LUA METHODS

// return true while still running previous
#define FDT_READY(FDT) \
  if((FDT)->fd.code == FD_RUNNING) { \
    lua_pushboolean(L, true); return 1; \
  }
#define FDT_START(FDT, METH) \
  (FDT)->meth = METH; \
  (FDT)->fd.code = FD_RUNNING; \
  EV_POST(fdt); \
  return 0;

// FD_read(fd, till=0) -> (code)
// Note: this interacts with FD_pop.
//
// read from file into buf. The amount depends on `till`
// * zero: read till EOF
// * positive: read at least this amount of bytes
// * negative: read until the negated character
//
// Returns the code for convinience.
// Note: call l_FD_pop() for the read string.
static int l_FD_read(LS* L) {
  FD* fd = toFD(L);
  fd->ctrl = luaL_optnumber(L, 2, 0);
  FD_read(fd);
  lua_pushinteger(L, fd->code); return 1;
}
static int l_FDT_read(LS* L) {
  FDT* fdt = toFDT(L); FDT_READY(fdt);
  fdt->fd.ctrl = luaL_optnumber(L, 2, 0);
  FDT_START(fdt, FD_read);
}
#undef PRE_READ

// FD_write may have to be called multiple times (O_NONBLOCK).
// It requires passing in the string repeatedly, so we don't
// need to own the string.
static int l_FD_write(LS* L) {
  FD* fd = toFD(L);
  FD_free(fd);
  fd->buf = (char*)luaL_checklstring(L, 2, (size_t*)&fd->ei);
  if(!lua_isnoneornil(L, 3)) fd->si = luaL_checkinteger(L, 3);
  if(!lua_isnoneornil(L, 4)) {
    size_t ei = luaL_checkinteger(L, 4);
    if(ei < fd->ei) fd->ei = ei;
  }
  FD_write(fd);
done:
  lua_pushinteger(L, fd->code); return 1;
}

// FDT_write may only be called once. We copy the string
// so the pthread owns it
static int l_FDT_write(LS* L) {
  FDT* fdt = toFDT(L); FDT_READY(fdt);
  size_t len; const char* s = luaL_checklstring(L, 2, &len);
  if(len == 0) return 0;
  int si = luaL_optinteger(L, 3, 0);
  int ei = luaL_optinteger(L, 3, len);
  FD* fd = &fdt->fd;
  if(fd->size < ei - si) FD_realloc(fd, ei - si);
  if(!fd->size) { fd->code = errno; return 0; }
  memmove((char*)fd->buf, s + si, ei - si);
  fd->si = 0; fd->ei = ei - si;
  FDT_START(fdt, FD_write);
}

// (fd, offset, whence) -> (code)
// Seek to offset+whence
static int l_FD_seek(LS* L) {
  FD* fd = toFD(L);
  off_t offset = luaL_checkinteger(L, 2);
  int whence   = luaL_checkinteger(L, 3);
  if(FD_seekpre(fd, offset, whence)) fd->code = 0;
  else FD_seek(fd);
  return 0;
}
static int l_FDT_seek(LS* L) {
  FDT* fdt = toFDT(L); FDT_READY(fdt);
  off_t offset = luaL_checkinteger(L, 2);
  int whence   = luaL_checkinteger(L, 3);
  fdt->fd.code = FD_RUNNING;
  if(FD_seekpre(&fdt->fd, offset, whence)) fdt->fd.code = 0;
  else { fdt->meth = FD_seek; EV_POST(fdt); }
  return 0;
}

static int l_FD_flush(LS* L) { FD_flush(toFD(L)); return 0; }
static int l_FDT_flush(LS* L) {
  FDT* fdt = toFDT(L); FDT_READY(fdt);
  FDT_START(fdt, FD_flush);
}

static int l_FD_create(LS* L)  { FD_create(L);  return 1; }
static int l_FDT_create(LS* L) { FDT_create(L); return 1; }

// open(path, flags) -> FD
static int l_FD_open(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  const int flags = luaL_checkinteger(L, 2);
  FD* fd = FD_create(L);
  fd->buf = (char*)path; fd->ctrl = flags;
  fd->code = FD_RUNNING; FD_open(fd);
  return 1;
}
static int l_FDT_open(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  const int flags = luaL_checkinteger(L, 2);
  FDT* fdt = FDT_create(L); FD* fd = &fdt->fd;
  fd->buf = (char*)path; fd->ctrl = flags;
  fdt->meth = FD_open; fd->code = FD_RUNNING;
  EV_POST(fdt);
  return 1; // return fd
}

static int l_FD_tmp(LS* L) {
  FD* fd = FD_create(L);
  FD_tmp(fd);
  return 1;
}
static int l_FDT_tmp(LS* L) {
  FDT* fdt = FDT_create(L); FD* fd = &fdt->fd;
  fdt->meth = FD_tmp; fd->code = FD_RUNNING;
  EV_POST(fdt);
  return 1;
}

static int l_FD_close(LS* L) {
  FD_close(toFD(L));
  return 0;
}
static int l_FDT_close(LS* L) {
  FDT* fdt = toFDT(L); assertReady(L, &fdt->fd, "close");
  fdt->meth = FD_close; fdt->fd.code = FD_RUNNING;
  EV_POST(fdt);
  return 0;
}
void FDT_destroy(FDT* fdt) {
  if(!fdt->stopped) {
    fdt->stopped = 1;
    EV_POST(fdt); pthread_join(fdt->th, NULL);
  }
  EV_DESTROY(fdt);
  FD_close(&fdt->fd);
}
static int l_FDT_destroy(LS* L) { FDT_destroy(toFDT(L)); return 0; }

// (fd) -> code, flags
static int l_FD_getflags(LS* L) {
  FD* fd = asfd(L);
  int fl = fcntl(fd->fileno, F_GETFL);
  fd->code = (fl < 0) ? errno : 0;
  lua_pushinteger(L, fd->code);
  lua_pushinteger(L, fl);
  return 2;
}

// (fd, flags) -> code
static int l_FD_setflags(LS* L) {
  FD* fd = asfd(L); fd->code = FD_RUNNING;
  int fl = fcntl(fd->fileno, F_SETFL, luaL_checkinteger(L, 2));
  fd->code = (fl < 0) ? errno : 0;
  lua_pushinteger(L, fd->code);
  return 1;
}

// () -> (r, w): return read/write pipes
static int l_pipe(LS* L) {
  FD *r = FD_create(L); FD *w = FD_create(L);
  int rw[2]; ASSERT(L, !pipe(rw), "pipe() %s", strerror(errno));
  r->fileno = rw[0]; w->fileno = rw[1];
  return 2;
}

// ---------------------
// -- PollList
const char* LUA_PL = "fd.PollList";
#define toPL(L) \
  ((PL *)luaL_checkudata(L, 1, LUA_PL))

typedef struct _PL {
  int size;
  struct pollfd* fds;
} PL;

static void PL_realloc(LS* L, PL* pl, int size) {
  struct pollfd* fds = realloc(pl->fds, size * sizeof(struct pollfd));
  ASSERT(L, fds, "OOM: realloc pollfds size=%I", size);
  for(int i=pl->size; i < size; i++) {
    fds[i].fd = -1; fds[i].revents = 0;
  }
  pl->fds = fds; pl->size = size;
}
static int l_PL_new(LS* L) {
  PL* pl = (PL*)lua_newuserdata(L, sizeof(PL));
  pl->size = 0; pl->fds = NULL;
  luaL_setmetatable(L, LUA_PL);
  return 1;
}
static int l_PL_resize(LS* L) {
  PL_realloc(L, toPL(L), luaL_checkinteger(L, 2)); return 0;
}
static int l_PL_destroy(LS* L) {
  PL* pl = toPL(L);
  if(pl->fds) { free(pl->fds); pl->size = 0; pl->fds = NULL; }
  return 0;
}
static int l_PL_size(LS* L) { lua_pushinteger(L, toPL(L)->size); return 1; }

// (pl, index, fileno, events)
// Note: indexes are 0-based
static int l_PL_set(LS* L) {
  PL* pl = toPL(L);
  int index  = luaL_checkinteger(L, 2);
  int fileno = luaL_checkinteger(L, 3);
  int events = luaL_checkinteger(L, 4);
  pl->fds[index].fd      = fileno;
  pl->fds[index].events  = events;
  pl->fds[index].revents = 0;
  return 0;
}

// (pl, timeoutMs) -> {filenos}
static int l_PL_ready(LS* L) {
  PL* pl = toPL(L);
  int timeoutMs = luaL_checkinteger(L, 2);
  int count = poll(pl->fds, pl->size, timeoutMs);
  lua_createtable(L, count, 0);
  int ti = 1;
  for(int i = 0; i < pl->size; i++) {
    if(pl->fds[i].revents) {
      lua_pushinteger(L, pl->fds[i].fd);
      lua_seti(L, -2, ti); ti++;
      pl->fds[i].revents = 0;
    }
  }
  return 1;
}

// ----------------------
// -- DEFINE LIBRARY

// (io.file) -> (fileno)
static int l_fileno(LS* L) {
  luaL_Stream* fs = (luaL_Stream *)luaL_checkudata(L, 1, LUA_FILEHANDLE);
  lua_pushinteger(L, fileno(fs->f));
  return 1;
}

// fmode(fileno) -> st_mode (see fd.fmode())
static int l_fstmode(LS* L) {
  int fd = luaL_checkinteger(L, 1); struct stat sbuf = {0};
  if(fstat(fd, &sbuf)) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }
  lua_pushinteger(L, sbuf.st_mode);
  return 1;
}

// (fileno) -> (isatty)
static int l_isatty(LS* L) {
  lua_pushboolean(L, isatty(luaL_checkinteger(L, 1)));
  return 1;
}

static const struct luaL_Reg fd_lib[] = {
  {"openFD", l_FD_open},   {"openFDT", l_FDT_open},
  {"tmpFD",  l_FD_tmp},    {"tmpFDT",  l_FDT_tmp},
  {"newFD",  l_FD_create}, {"newFDT",  l_FDT_create},
  {"pollList", l_PL_new},
  {"fileno", l_fileno},    {"fstmode", l_fstmode},
  {"isatty", l_isatty},
  {"pipe", l_pipe},
  {NULL, NULL},
};

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_fd_lib(LS *L) {
  luaL_newlib(L, fd_lib);

    #define FD_METHODS  (/*native=*/ 11 + /*lua=*/ 3)
    luaL_newmetatable(L, LUA_FD);
      L_setmethod(L, "__gc", l_FD_close);
      lua_createtable(L, 0, FD_METHODS);
        // fields
        L_setmethod(L, "code",     l_FD_code);
        L_setmethod(L, "fileno",   l_FD_fileno);
        L_setmethod(L, "pos",      l_FD_pos);
        L_setmethod(L, "_setfileno", l_FD_setfileno);

        // true methods
        L_setmethod(L, "_close",   l_FD_close);
        L_setmethod(L, "codestr",  l_FD_codestr);
        L_setmethod(L, "_write",   l_FD_write);
        L_setmethod(L, "_getflags",l_FD_getflags);
        L_setmethod(L, "_setflags",l_FD_setflags);
        L_setmethod(L, "_read",    l_FD_read);
        L_setmethod(L, "_seek",    l_FD_seek);
        L_setmethod(L, "_pop",     l_FD_pop);
        L_setmethod(L, "_flush",   l_FD_flush);
      lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "FD");

    luaL_newmetatable(L, LUA_FDT);
      L_setmethod(L, "__gc", l_FDT_destroy);
      lua_createtable(L, 0, FD_METHODS);
        // fields
        L_setmethod(L, "code",     l_FD_code);
        L_setmethod(L, "fileno",   l_FD_fileno);
        L_setmethod(L, "pos",      l_FD_pos);
        L_setmethod(L, "_setfileno", l_FD_setfileno);

        // true methods
        L_setmethod(L, "_close",   l_FDT_close);
        L_setmethod(L, "codestr",  l_FD_codestr);
        L_setmethod(L, "_write",   l_FDT_write);
        L_setmethod(L, "_getflags",l_FD_getflags);
        L_setmethod(L, "_setflags",l_FD_setflags);
        L_setmethod(L, "_read",    l_FDT_read);
        L_setmethod(L, "_seek",    l_FDT_seek);
        L_setmethod(L, "_pop",     l_FD_pop);
        L_setmethod(L, "_flush",   l_FDT_flush);
        L_setmethod(L, "_evfileno",l_FDT_evfileno);
      lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "FDT");

  luaL_newmetatable(L, LUA_PL);
    L_setmethod(L, "__gc", l_PL_destroy);
    lua_createtable(L, 0, 4); // __index table
      L_setmethod(L, "size",    l_PL_size);
      L_setmethod(L, "resize",  l_PL_resize);
      L_setmethod(L, "set",     l_PL_set);
      L_setmethod(L, "ready",   l_PL_ready);
    lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "PL");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  setconstfield(L, FD_EOF);  setconstfield(L, FD_RUNNING);

  // open constants
  setconstfield(L, O_RDONLY); setconstfield(L, O_WRONLY);
  setconstfield(L, O_RDWR);   setconstfield(L, O_APPEND);
  setconstfield(L, O_CREAT);  setconstfield(L, O_TRUNC);
  setconstfield(L, O_NONBLOCK);

  // st_mode constants
  setconstfield(L, S_IFMT);
  setconstfield(L, S_IFSOCK); setconstfield(L, S_IFLNK);
  setconstfield(L, S_IFREG);  setconstfield(L, S_IFBLK);
  setconstfield(L, S_IFDIR);  setconstfield(L, S_IFCHR);
  setconstfield(L, S_IFIFO);

  // seek constants
  setconstfield(L, SEEK_SET); setconstfield(L, SEEK_CUR);
  setconstfield(L, SEEK_END);

  // poll constants
  setconstfield(L, POLLIN);   setconstfield(L, POLLOUT);

  // important errors
  setconstfield(L, EWOULDBLOCK); setconstfield(L, EAGAIN);
  setconstfield(L, EBADF);

  // std descriptors
  setconstfield(L, STDIN_FILENO); setconstfield(L, STDOUT_FILENO);
  setconstfield(L, STDERR_FILENO);

  return 1;
}