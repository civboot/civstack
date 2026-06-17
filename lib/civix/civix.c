#include <stdlib.h>

#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <assert.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>

#ifdef BSD
extern char** environ;
static void clearenv() { *environ = NULL; }
#endif

// ---------------------
// -- Utilities
typedef lua_State LS;
typedef struct stat STAT;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }
#define SERR strerror(errno)

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

static bool l_defaulttrue(LS *L, int index) {
  return lua_isnoneornil(L, index) || lua_toboolean(L, index);
}

// Return a string array with null-terminated end.
// Note: you MUST free it.
char** checkstringarray(LS *L, int index, int* lenOut) {
  lua_len(L, index); int len = luaL_checkinteger(L, -1); lua_pop(L, 1);
  // validate
  for(int i = 0; i < len; i++) {
    lua_geti(L, index, i + 1); (char*)luaL_checkstring(L, -1); lua_pop(L, 1);
  }
  // assign to array
  char** arr = malloc(sizeof(char*) * (len + 1)); ASSERT(L, arr, "OOM");
  for(int i = 0; i < len; i++) {
    lua_geti(L, index, i + 1); arr[i] = (char*)lua_tostring(L, -1);
    lua_pop(L, 1);
  }
  arr[len] = NULL; *lenOut = len;
  return arr;
}

static int l_strerrno(LS* L) {
  lua_pushstring(L, strerror(luaL_checkinteger(L, 1))); return 1;
}

// ---------------------
// -- Time
int gettime(LS *L, clockid_t clk_id) {
  struct timespec spec = {};
  clock_gettime(clk_id, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
} int l_epoch(LS *L) { return gettime(L, CLOCK_REALTIME);  }
  int l_mono(LS *L)  { return gettime(L, CLOCK_MONOTONIC); }

int l_nanosleep(LS*L) {
  struct timespec req, rem;
  req.tv_sec  = luaL_checkinteger(L, 1); req.tv_nsec = luaL_checkinteger(L, 2);
  while(nanosleep(&req, &rem)) req = rem;
  return 0;
}

// ---------------------
// -- Dir iterator and other functions

// mkdir(path, mode=0777) -> ok, errno
//   note: 0777 is octal.
int l_mkdir(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  mode_t mode = luaL_optinteger(L, 2, 0777);
  if(mkdir(path, mode)) {
    lua_pushnil(L); lua_pushinteger(L, errno); return 2;
  }
  lua_pushboolean(L, true); return 1;
}

static int rmfn(LS* L, char* name, int fn(const char*)) {
  const char* path = luaL_checkstring(L, 1);
  bool ok = !fn(path); lua_pushboolean(L, ok);
  if(ok) return 1;
  lua_pushstring(L, SERR);
  lua_pushinteger(L, errno);
  return 3;
}
// rm(path) -> ok, errmsg, errno: removes path
static int l_rm(LS* L)    { return rmfn(L, "rm",    unlink); }
static int l_rmdir(LS* L) { return rmfn(L, "rmdir", rmdir); }

// exists(path) --> bool
static int l_exists(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  lua_pushboolean(L, 0 == access(path, F_OK));
  return 1;
}

const char* DIR_META = "civix.Dir";
#define toldir(L) (DIR**)luaL_checkudata(L, 1, DIR_META)

static void DIR_gc(DIR** dir) {
  if(*dir) { closedir(*dir); *dir = NULL; }
}
static int l_dir_gc(LS *L) { DIR_gc(toldir(L)); return 0; }

// Each time called return next: (name, ftype) or nil
static int dir_iter(LS *L) {
	DIR** dir = (DIR**) luaL_checkudata(L, lua_upvalueindex(1), DIR_META);
  if(*dir == NULL) return 0; // already freed
  struct dirent* ent;
skip:
  if((ent = readdir(*dir)) == NULL) {
    DIR_gc(dir); return 0; // done, free *DIR immediately
  }
  if((0==strcmp(".", ent->d_name)) || (0==strcmp("..", ent->d_name)))
    { goto skip; }
  lua_pushstring(L, ent->d_name);
  switch(ent->d_type) {
#define DCASE(VAL, STR) case VAL: lua_pushstring(L, STR); break;
    DCASE(DT_BLK, "blk");   DCASE(DT_CHR, "chr");  DCASE(DT_DIR, "dir");
    DCASE(DT_FIFO, "fifo"); DCASE(DT_LNK, "link"); DCASE(DT_REG, "file");
    DCASE(DT_SOCK, "sock"); DCASE(DT_UNKNOWN, "unknown");
#undef DCASE
    default:         lua_pushnil(L);
  }
  return 2;
}

// return (name, ftype) iterator. Skips "." and ".."
static int l_dir(LS *L) {
  const char* path = luaL_checkstring(L, 1);
  DIR** dir = (DIR**)lua_newuserdata(L, sizeof(DIR*)); // stack: dir
  luaL_setmetatable(L, DIR_META);
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, SERR);
  lua_pushcclosure(L, dir_iter, 1);                    // stack: (empty)
  return 1;
}

// ---------------------
// -- Stat
const char* STAT_META = "civix.Stat";
#define tolstat(L) ((STAT**)luaL_checkudata(L, 1, STAT_META))
static void STAT_gc(STAT** st) { if(*st) { free(*st); *st = NULL; } }
static int l_stat_gc(LS* L)    { STAT_gc(tolstat(L)); return 0; }

// path -> (stat?, err)
static int l_stat(LS* L) {
  STAT** st = (STAT**)lua_newuserdata(L, sizeof(STAT*)); // stack: dir
  if (!st) { lua_pushnil(L); lua_pushstring(L, "OOM"); return 2; }
  *st = NULL; luaL_setmetatable(L, STAT_META);
  *st = malloc(sizeof(STAT));
  if (!*st) { lua_pushnil(L); lua_pushstring(L, "OOM"); return 2; }
  int rc = lua_isnumber(L, 1)
      ? fstat(lua_tonumber(L, 1), *st)
      : stat(luaL_checkstring(L, 1), *st);
  if(rc) { lua_pushnil(L); lua_pushstring(L, SERR); return 2; }
  return 1;
}

static int l_stat_mode(LS *L) {
  lua_pushinteger(L, (*tolstat(L))->st_mode); return 1;
}

// stat -> (sec, nsec)
static int l_stat_modified(LS *L) {
  STAT* st = *tolstat(L);
  lua_pushinteger(L, st->st_mtim.tv_sec);
  lua_pushinteger(L, st->st_mtim.tv_nsec);
  return 2;
}

// stat -> (size)
static int l_stat_size(LS *L) {
  STAT* st = *tolstat(L);
  lua_pushinteger(L, st->st_size); return 1;
}

// (fd, modified_s, modified_ns) --> error?
static int l_setmodified(LS* L) {
  int fno = luaL_checkinteger(L, 1);
  struct timespec times[2];
  times[0].tv_sec  = 0; times[0].tv_nsec = UTIME_OMIT; // omit access
  times[1].tv_sec  = luaL_checkinteger(L, 2);
  times[1].tv_nsec = luaL_checkinteger(L, 3);
  if(futimens(fno, times)) { lua_pushstring(L, strerror(errno)); return 1; }
  return 0;
}

// ---------------------
// -- Shell
const char* SH_META  = "civix.Sh";
#define tolsh(L) ((struct sh*)luaL_checkudata(L, 1, SH_META))

struct sh {
  pid_t pid; char** env; // note: env only set if needs freeing
  int rc; // return code of wait
};

// wait for pid to be complete. Set pid to 0 when done.
struct sh* sh_wait(struct sh* sh, int flags) {
  if(sh->pid) {
    siginfo_t infop = {0};
    if(waitid(P_PID, sh->pid, &infop, WEXITED | flags)) {
      fprintf(stderr, "ERROR: waitid failed (%s [%i])\n", SERR, errno);
      return sh;
    }
    if(infop.si_pid) {
      sh->pid = 0; sh->rc = infop.si_status;
    }
  }
  return sh;
}

static void sh_gc(struct sh* sh) {
  if(sh->pid) { kill(sh->pid, SIGKILL); sh_wait(sh, 0); }
  if(sh->env) { free(sh->env); sh->env = NULL; }
}
static int l_sh_gc(LS *L) { sh_gc(tolsh(L)); return 0; }

// () -> isDone: asynchronously determine whether Sh is done.
static int l_sh_isDone(LS *L) {
  lua_pushboolean(L, !sh_wait(tolsh(L), WNOHANG)->pid);
  return 1;
}

static int l_sh_rc(LS *L) {
  lua_pushinteger(L, tolsh(L)->rc);
  return 1;
}

// () -> : block until Sh is done.
static int l_sh_wait(LS *L) {
  sh_wait(tolsh(L), 0);
  return 0;
}

// (command, argList, envList=nil, stdin, out, err, CWD) -> (sh, r, w)
// Note: all file-descriptors are integers
// Note: file descriptors are only returned if they have been created
//   by pipe(), they are not returned if they were passed in.
#define CLOSE(fno) if(fno >= 0) { close(fno); }
static int l_sh(LS *L) {
  const char* command = luaL_checkstring(L, 1);
  int _unused;
  char **argv = checkstringarray(L, 2, &_unused);
  bool createdChR = false, createdChW = false, createdChL = false;

  int topi = lua_gettop(L); // FIXME: remove
  struct sh* sh = (struct sh*)lua_newuserdata(L, sizeof(struct sh));
  ASSERT(L, sh, "OOM");
  *sh = (struct sh) {0};
  luaL_setmetatable(L, SH_META);
  if(!lua_isnoneornil(L, 3)) {
    sh->env = checkstringarray(L, 3, &_unused);
  }

  // ch_r=child-read, pr_w=parent-write, etc
  int rw[2];
  int ch_r = -1, ch_w = -1; int pr_r = -1, pr_w = -1, pr_l = -1, ch_l = -1;
  // process stdin
  if(lua_isinteger(L, 4)) ch_r = lua_tointeger(L, 4);
  else if (lua_toboolean(L, 4)) {
    createdChR = true; if(pipe(rw)) goto error;
    ch_r = rw[0]; pr_w  = rw[1];
  }
  // process stdout
  if(lua_isinteger(L, 5)) ch_w = lua_tointeger(L, 5);
  else if (lua_toboolean(L, 5)) {
    createdChW = true; if(pipe(rw)) goto error;
    pr_r = rw[0]; ch_w  = rw[1];
  }
  // process stderr
  if(lua_isinteger(L, 6)) ch_l = lua_tointeger(L, 6);
  else if (lua_toboolean(L, 6)) {
    createdChL = true; if(pipe(rw)) goto error;
    pr_l = rw[0]; ch_l  = rw[1];
  }
  const char* cwd = luaL_optstring(L, 7, NULL);

  int pid = fork(); if(pid == -1) goto error;
  else if(pid == 0) { // child
    CLOSE(pr_r); CLOSE(pr_w); CLOSE(pr_l);
    if(sh->env) {
      char **env = sh->env;
      clearenv();
      while(*env) { putenv(*env); env += 1; }
    }
    if(cwd) chdir(cwd);
    if(ch_w != STDOUT_FILENO) { dup2(ch_w,  STDOUT_FILENO); close(ch_w); }
    else if(ch_w < 0) close(STDOUT_FILENO);
    if(ch_r != STDIN_FILENO)  { dup2(ch_r,  STDIN_FILENO);  close(ch_r); }
    else if (ch_r < 0) close(STDIN_FILENO);

    if(ch_l != STDERR_FILENO) { dup2(ch_l,  STDERR_FILENO); close(ch_l); }
    else if (ch_l < 0) close(STDERR_FILENO);
    execvp(command, argv);
    if(errno) fprintf(stderr, "execvp\"%s\"(%s [%i])\n",
          command, SERR, errno);
    _exit(1);
  } // else parent
  sh->pid = pid;
  // only return if we created the fileno. Also, close child-side pipes
  if(createdChW) { close(ch_w); lua_pushinteger(L, pr_r); } else lua_pushnil(L);
  if(createdChR) { close(ch_r); lua_pushinteger(L, pr_w); } else lua_pushnil(L);
  if(createdChL) { close(ch_l); lua_pushinteger(L, pr_l); } else lua_pushnil(L);
  return 4;
  error:
    if(createdChW) CLOSE(ch_w); if(createdChR) CLOSE(ch_r);
    if(createdChL) CLOSE(ch_l);
    if(pr_r) close(pr_r);    if(pr_w) close(pr_w); if(pr_l) close(pr_l);
    luaL_error(L, "failed sh: %s", SERR); return 0;
}
#undef CLOSE


// ---------------------
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"strerrno", l_strerrno},
  {"epoch", l_epoch}, {"mono", l_mono},
  {"nanosleep", l_nanosleep},
  {"dir", l_dir},
  {"stat", l_stat}, {"setmodified", l_setmodified},
  {"mkdir", l_mkdir}, {"rm",  l_rm}, {"rmdir", l_rmdir},
  {"exists", l_exists},
  {"sh", l_sh},
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(LS *L) {
  luaL_newlib(L, civix_lib);

  luaL_newmetatable(L, DIR_META);
    L_setmethod(L, "__gc", l_dir_gc);
  lua_setfield(L, -2, "Dir");

  luaL_newmetatable(L, STAT_META);
    L_setmethod(L, "__gc", l_stat_gc);
    lua_createtable(L, 0, 3); // __index table
      L_setmethod(L, "mode",     l_stat_mode);
      L_setmethod(L, "modified", l_stat_modified);
      L_setmethod(L, "size",     l_stat_size);
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "Stat");

  luaL_newmetatable(L, SH_META);
    L_setmethod(L, "__gc", l_sh_gc);
    lua_createtable(L, 0, 3); // __index table
      L_setmethod(L, "isDone", l_sh_isDone);
      L_setmethod(L, "wait",   l_sh_wait);
      L_setmethod(L, "rc",     l_sh_rc);
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "Sh");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  // st_mode constants
  setconstfield(L, S_IFMT);
  setconstfield(L, S_IFSOCK); setconstfield(L, S_IFLNK);
  setconstfield(L, S_IFREG);  setconstfield(L, S_IFBLK);
  setconstfield(L, S_IFDIR);  setconstfield(L, S_IFCHR);
  setconstfield(L, S_IFIFO);

  // important errno's
  setconstfield(L, EEXIST);
  return 1;
}
