local mty = require'metaty'

--- Working with and representing time.
local M = mty.mod'ds.time'

local setmt        = setmetatable
local ty                = mty.from(mty,  'ty')
local mtype, floor, min, abs = mty.from(math, 'type,floor,min,abs')
local sfmt              = mty.from(string, 'format')

local NANO   = 1000000000 -- nanoseconds in a second
local MICRO  = 1000000    -- microseconds in a second
M.NANO, M.MICRO = NANO, MICRO

--- Represents a date time. The core fields are documented below, with
--- methods to convert to more "typical" reprsentations.
M.DateTime = mty'DateTime' {
  'y  [int]: the year',
  'yd [int]: the day of the year',
  's  [int]: seconds in day',
  'ns [int]: nanoseconds in second',
  'tz [Tz]: timezone offset, see [<#ds.time.Tz>].',
  'wd [int]: weekday, 1=sunday - 7=saturday',
}

--- Represents a Duration of time.
M.Duration = mty'Duration' {
  's[int]: seconds', 'ns[int]: nanoseconds',
}

--- Represents an Epoch: seconds and nano-seconds since 1970-01-01 at 12:00 pm.
M.Epoch = mty'Epoch' {
  's[int]: seconds', 'ns[int]: nanoseconds',
}

--- Usage: [$Tz:of(-6)] for a -6 hour offset.
M.Tz = require'metaty.freeze'.freezy(mty'Tz' {
  's [int]: second offset',
  'name [string]: calculated name',
})

local function splitFloat(sec)
  local s = floor(sec)
  return s, floor(NANO * (sec - s))
end
local function checkTime(s, ns)
  assert(mtype(s)  == 'integer',   'non-int seconds')
  assert(mtype(ns) == 'integer',  'non-int nano-seconds')
  assert(ns < NANO,               'nano-seconds too large')
end
local function splitTime(sec, ns)
  if mtype(sec) == 'float'  then return splitFloat(sec)
  elseif ty(sec) == M.Epoch then return sec.s, sec.ns   end
  ns = ns or 0
  checkTime(sec, ns)
  return sec, ns
end

local function durationSub(s, ns, s2, ns2)
  s, ns = s - s2, ns - ns2
  if ns < 0 then
    ns = NANO + ns
    s = s - 1
  end
  return s, ns
end

local function assertTime(t)
  assert(math.floor(t.s) == t.s,   'non-int seconds')
  assert(math.floor(t.ns) == t.ns, 'non-int nano-seconds')
  assert(t.ns < NANO, 'ns too large')
  return t
end

local function timeNew(T, s, ns)
  if mtype(s) == 'float' then
    assert(not ns, 'cannot provide nanosec with float seconds')
    s, ns = splitFloat(s)
  else
    ns = ns or 0
    checkTime(s, ns)
  end
  return setmt({s=s, ns=ns}, T)
end
local function fromSeconds(T, s)  return T(s) end
local function fromMs(ty_, s)     return ty_(s / 1000) end
local function fromMicros(ty_, s) return ty_(s / MICROS) end
local function asSeconds(time)    return time.s + (time.ns / NANO) end
local function timeFromPod(T, pod, v) return timeNew(T, v[1], v[2]) end
local function timeToPod(T, pod, v)   return {v.s, v.ns} end
local function timeLt(a, b)
  if a.s == b.s then return a.ns < b.ns end
                     return a.s < b.s
end

---------------------
-- Duration
getmetatable(M.Duration).__call = timeNew

M.Duration.fromSeconds = fromSeconds
M.Duration.fromMs = fromMs
M.Duration.asSeconds = asSeconds
function M.Duration:__sub(r)
  assert(ty(r) == M.Duration)
  return M.Duration(durationSub(self.s, self.ns, r.s, r.ns))
end
function M.Duration:__add(r)
  assert(ty(r) == M.Duration)
  return M.Duration(durationSub(self.s, self.ns, -r.s, -r.ns))
end
M.Duration.__lt = timeLt
M.Duration.__fmt = nil
function M.Duration:__tostring() return self:asSeconds()..'s' end
M.Duration.__toPod   = timeToPod
M.Duration.__fromPod = timeFromPod
function M.Duration:asMs() --> int
  return (self.s * 1000) + (self.ns // MICRO)
end

M.ZERO = M.Duration(0, 0)

---------------------
-- Epoch: time since the unix epoch. Interacts with duration.
getmetatable(M.Epoch).__call = timeNew

M.Epoch.fromSeconds = fromSeconds
M.Epoch.asSeconds   = asSeconds
function M.Epoch:__sub(r)
  assert(self);     assert(r)
  assertTime(self); assertTime(r)
  local s, ns = durationSub(self.s, self.ns, r.s, r.ns)
  if ty(r) == M.Duration then return M.Epoch(s, ns) end
  assert(ty(r) == M.Epoch, 'can only subtract Duration or Epoch')
  return M.Duration(s, ns)
end
M.Epoch.__lt = timeLt
M.Epoch.__fmt = nil
function M.Epoch:__tostring()
  return string.format('Epoch(%ss)', self:asSeconds())
end
M.Epoch.__toPod   = timeToPod
M.Epoch.__fromPod = timeFromPod

---------------------
-- Algorithm to convert seconds since the epoch to DateTime.
-- Original implementation in C by Alexey Frunze 2026 (CC0 - Public Domain)
-- https://stackoverflow.com/a/11197532/1036670
local daysSinceJan1st = { -- days since jan 1st per month.
  noleap = {[0]=0,31,59,90,120,151,181,212,243,273,304,334,365}, -- 365 days, non-leap
  leap   = {[0]=0,31,60,91,121,152,182,213,244,274,305,335,366}, -- 366 days, leap
}

--- Leap years are every 4 years. The only exception is on the century,
--- except every 4th century (since 1600) there is still a leap year.
--- Therefore:
--- * 1600 WAS a leap year, as well as 1604, 1608, etc.
--- * 1700 was NOT a leap year, but 1704, 1708, etc was.
--- * 1800 was NOT a leap year, but 1804, 1808, etc was.
--- * 1900 was NOT a leap year, but 1904, 1908, etc was.
--- * 2000 WAS a leap year, as well as 2004,2008,etc.
function M.isLeap(year)
  return (year % 4 == 0) and ((year%100 ~= 0) or (year % 400 == 0))
end
local isLeap = M.isLeap

--- Compute DateTime in a future-proof manner (works past 2100, etc).
function M.DateTime._ofFuture(T, s)
  -- Re-bias from 1970 to 1601:
  -- 1970 - 1601 = 369 = 3*100 + 17*4 + 1 years (incl. 89 leap days) =
  -- (3*100*(365+24/100) + 17*4*(365+1/4) + 1*365)*24*3600 seconds
  s = s + 11644473600
  local wd = floor(s / 86400 + 1) % 7 -- day of week


  -- Remove multiples of 400 years (incl. 97 leap days)
  local quadricentennials = s // 12622780800 -- 400*365.2425*24*3600
  s =                        s % 12622780800

  -- Remove multiples of 100 years (incl. 24 leap days), can't be more than 3
  -- (because multiples of 4*100=400 years (incl. leap days) have been removed)
  local centennials = min(3, s // 3155673600) -- 100*(365+24/100)*24*3600
  s =          s - (centennials * 3155673600)

  -- Remove multiples of 4 years (incl. 1 leap day), can't be more than 24
  -- (because multiples of 25*4=100 years (incl. leap days) have been removed)
  local quadrennials = min(24, s // 126230400) -- 4*(365+1/4)*24*3600
  s =           s - (quadrennials * 126230400)

  -- Remove multiples of years (incl. 0 leap days), can't be more than 3
  -- (because multiples of 4 years (incl. leap days) have been removed)
  local annuals = min(3, s // 31536000) -- 365*24*3600
  s =          s - (annuals * 31536000)
  assert(mtype(s) == 'integer', 'not supported on 32bit integer systems')

  return T {
    y = 1601 + (quadricentennials * 400) + (centennials * 100)
             + (quadrennials * 4)        + annuals,
    yd = s // 86400,
    s  = s %  86400,
    wd = wd + 1,
  }
end

--- Compute DateTime of epoch seconds, doesn't work starting in 2100.
function M.DateTime._ofFast(T, s)
  -- Re-bias from 1970 to Wed 1969-01-01 to be on a leap year boundary.
  -- Every 4 years there will be a leap year.
  s = s + 31536000 -- 365*24*3600
  local wd = floor(s / 86400 + 3) % 7 -- day of week

  -- Remove multiples of 4 years (incl. 1 leap day)
  local quadrennials = s // 126230400 -- 4*(365+1/4)*24*3600
  s =   s - (quadrennials * 126230400)

  -- Remove multiples of years (incl. 0 leap days), can't be more than 3
  -- (because multiples of 4 years (incl. leap days) have been removed)
  local annuals = min(3, s // 31536000) -- 365*24*3600
  s =          s - (annuals * 31536000)
  assert(mtype(s) == 'integer', 'not supported on 32bit integer systems')

  return T {
    y  = 1969 + (quadrennials * 4) + annuals,
    yd = s // 86400,
    s  = s %  86400,
    wd = wd + 1,
  }
end

M.DateTime.of = function(T, s, tz)
  tz = tz or M.LOCAL or M.Z
  local s, ns = splitTime(s)
  s = s + tz.s
  -- check if before 2100-01-01T00:00:00Z
  local dt = s < 4102470000 and T:_ofFast(s)
                             or T:_ofFuture(s)
  dt.ns, dt.tz = ns, tz
  return dt
end

function M.DateTime:isLeap() return isLeap(self.y) end

--- Get the month and day of the month.
--- To get the year use [$DateTime.y].
function M.DateTime:date() --> month, day
  local yd = self.yd
  local dayLookup = self:isLeap() and daysSinceJan1st.leap
                 or daysSinceJan1st.noleap
  for m=1,12 do
    if yd < dayLookup[m] then
      return m, 1 + yd - dayLookup[m-1]
    end
  end
  error('year-day is impossible value: '..yd)
end

--- Get the time of day in hour,min,sec.
--- To get ns, use [$DateTime.ns]
function M.DateTime:time() --> hour,min,sec
  local s = self.s
  return s // 3600, (s % 3600) // 60, s % 60
end

function M.DateTime:__tostring() --> string
  local M, d = self:date()
  local h,m,s = self:time()
  return sfmt('%04i-%02i-%02iT%02i:%02i:%02i%s',
    self.y,M,d, h,m,s, self.tz.name)
end

function M.DateTime:_epochFast() --> Epoch
  local y69 = self.y - 1969 -- years since 1969
  local leaps = y69 // 4
  return M.Epoch(
    (leaps * 31622400)            -- 366*24*3600 years with leap day
    + ((y69 - leaps) * 31536000)  -- 365*24*3600 years w/out leap day
    + (self.yd * 86400)           -- 24 * 3600 days
    + self.s
    - 31536000                    -- subtract 1969 offset year.
    - self.tz.s,
    self.ns)
end

--- Convert a DateTime to an Epoch
function M.DateTime:epoch() --> Epoch
  local y = self.y
  return y > 1969 and y < 2100 and self:_epochFast()
      or error'epoch past year 2100 not yet implemented'
end

function M.Tz.of(T, hours, minutes)
  hours   = hours or 0
  minutes = minutes or 0
  assert(mtype(hours) == 'integer' and mtype(minutes) == 'integer')
  assert(minutes >= 0)
  return T {
    s = hours * 3600 + minutes * 60,
    name = hours == 0 and minutes == 0 and 'Z'
      or sfmt('%s%02i:%02i', hours > 0 and '+' or '-', abs(hours), minutes),
  }:freeze()
end
function M.Tz:__tostring() return sfmt('Tz<%s>', self.name) end

--- Zero timezone
M.Z = M.Tz:of(0)
M.LOCAL = false  -- override to use local timezone

return M
