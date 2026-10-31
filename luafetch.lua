#!/usr/bin/env lua

local ESC = string.char(27)
local function fg(n, s) return ESC .. "[3" .. n .. "m" .. s .. ESC .. "[0m" end
local function bold(n, s) return ESC .. "[1;3" .. n .. "m" .. s .. ESC .. "[0m" end

---------------------------------------------------------------- helpers
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function unquote(s)
  s = trim(s)
  local q = s:sub(1, 1)
  if (q == '"' or q == "'") and s:sub(-1) == q then
    s = s:sub(2, -2)
  end
  return s
end

local function sh(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return nil end
  local out = trim(p:read("*a"))
  p:close()
  if out == "" then return nil end
  return out
end

local function readfile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function dispwidth(s)
  if utf8 and utf8.len then return utf8.len(s) or #s end
  return #s
end

local IS_WIN = package.config:sub(1, 1) == "\\"
local UNAME = (not IS_WIN) and sh("uname -s") or nil

---------------------------------------------------------------- OS detection
local function detect_os()
  if IS_WIN then return "Windows" end
  if UNAME == "Darwin" then
    local v = sh("sw_vers -productVersion")
    return "macOS" .. (v and (" " .. v) or "")
  end
  if UNAME == "Linux" then
    local rel = readfile("/etc/os-release") or readfile("/usr/lib/os-release") or ""
    local kv = {}
    for k, v in rel:gmatch("([%w_]+)=([^\n]*)") do
      kv[k] = unquote(v)
    end
    return kv.PRETTY_NAME or kv.NAME or "Linux"
  end
  return UNAME or "Unknown"
end

local function initial_of(name)
  local l = (name or ""):match("%a")
  return l and l:upper() or "?"
end

---------------------------------------------------------------- font loading
local function script_dir()
  return (arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "./"
end

local function load_font(path)
  local data = readfile(path)
  if not data then return nil end
  local glyphs, cur = {}, {}
  local function flush()
    if #cur > 0 then glyphs[#glyphs + 1] = cur end
    cur = {}
  end
  for line in (data .. "\n"):gmatch("(.-)\r?\n") do
    if trim(line) == "" then
      flush()
    else
      cur[#cur + 1] = (line:gsub("%s+$", ""))
    end
  end
  flush()

  local font = {}
  for i, g in ipairs(glyphs) do
    -- strip common left indent
    local indent = math.huge
    for _, l in ipairs(g) do
      indent = math.min(indent, #l:match("^ *"))
    end
    g.width = 0
    for j, l in ipairs(g) do
      g[j] = l:sub(indent + 1)
      g.width = math.max(g.width, dispwidth(g[j]))
    end
    font[string.char(64 + i)] = g
  end
  return font
end

---------------------------------------------------------------- info getters
local function get_user() return os.getenv("USER") or os.getenv("USERNAME") or sh("whoami") or "user" end

local function get_host()
  local h = trim(readfile("/etc/hostname") or "")
  if h ~= "" then return h end
  return os.getenv("HOSTNAME") or os.getenv("COMPUTERNAME") or sh("hostname") or "localhost"
end

local function get_kernel()
  if IS_WIN then return sh("ver") end
  return sh("uname -r")
end

local function get_shell()
  local s = os.getenv("SHELL")
  if s then return s:match("([^/\\]+)$") end
  if IS_WIN then return os.getenv("PSModulePath") and "powershell" or "cmd" end
end

local function ppid_of(pid)
  local stat = readfile("/proc/" .. pid .. "/stat")
  return stat and tonumber(stat:match("%) %S+ (%d+)"))
end

local function get_terminal()
  local e = os.getenv
  if e("TERM_PROGRAM") then return e("TERM_PROGRAM"):lower() end
  if e("ALACRITTY_SOCKET") or e("ALACRITTY_LOG") then return "alacritty" end
  if e("KITTY_WINDOW_ID") then return "kitty" end
  if e("WEZTERM_EXECUTABLE") then return "wezterm" end
  if e("WT_SESSION") then return "Windows Terminal" end
  local me = readfile("/proc/self/stat") -- self -> shell -> terminal
  if me then
    local shell = tonumber(me:match("%) %S+ (%d+)"))
    local term = shell and ppid_of(shell)
    local comm = term and readfile("/proc/" .. term .. "/comm")
    if comm and trim(comm) ~= "" then return trim(comm) end
  end
  return e("TERM")
end

local function get_wm()
  if IS_WIN then return "DWM" end
  if UNAME == "Darwin" then return "Quartz Compositor" end

  local e = os.getenv
  local name

  -- X11: ask the X server which window is the WM, then read its name / pid
  if e("DISPLAY") then
    local root = sh("xprop -root _NET_SUPPORTING_WM_CHECK")
    local wid = root and root:match("(0x%x+)")
    if wid then
      local out = sh("xprop -id " .. wid .. " _NET_WM_NAME")
      name = out and out:match('"(.-)"')
      if not name then
        local p = sh("xprop -id " .. wid .. " _NET_WM_PID")
        local pid = p and p:match("(%d+)%s*$")
        local comm = pid and readfile("/proc/" .. pid .. "/comm")
        name = comm and trim(comm)
      end
    end
    if not name then
      local m = sh("wmctrl -m")
      name = m and m:match("Name:%s*([^\n]+)")
    end
  end

  -- Wayland: find the process listening on the compositor socket
  if not name and e("WAYLAND_DISPLAY") then
    local ss = sh("ss -xlpn")
    if ss then
      for line in ss:gmatch("[^\n]+") do
        if line:find(e("WAYLAND_DISPLAY"), 1, true) then
          name = line:match('users:%(%("([^"]+)"')
          if name then break end
        end
      end
    end
  end

  -- fallback: desktop environment variables
  if not name then
    name = e("XDG_CURRENT_DESKTOP") or e("DESKTOP_SESSION")
  end

  if not name then return nil end
  local st = e("XDG_SESSION_TYPE")
  if not st and e("WAYLAND_DISPLAY") then st = "wayland" end
  if not st and e("DISPLAY") then st = "x11" end
  return name .. (st and ("(" .. st .. ")") or "")
end

local function get_uptime()
  local secs
  local up = readfile("/proc/uptime")
  if up then
    secs = tonumber(up:match("^(%d+)"))
  else
    local bt = sh("sysctl -n kern.boottime")
    local sec = bt and bt:match("sec = (%d+)")
    if sec then secs = os.time() - tonumber(sec) end
  end
  if not secs then return nil end
  return string.format("%d days, %d hours, %d minutes",
    math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60))
end

---------------------------------------------------------------- main
local function main()
  local os_name = detect_os()
  local letter = initial_of(arg and arg[1] or os_name)
  local art_col = tonumber(os.getenv("LUAFETCH_COLOR") or "") or 7

  local home = os.getenv("HOME") or ""
  local candidates = {}
  local function add(p) if p then candidates[#candidates + 1] = p end end

  add(os.getenv("LUAFETCH_ART"))
  add(script_dir() .. "ascii.txt")
  add(home .. "/.config/luafetch/ascii.txt")
  add("/usr/share/luafetch/ascii.txt")

  local font
  for _, p in ipairs(candidates) do
    font = load_font(p)
    if font then break end
  end

  local glyph = font and font[letter] or {}
  local art_w = glyph.width or 0

  local rows = {
    { "OS", os_name, 1 },
    { "KER", get_kernel(), 2 },
    { "SH", get_shell(), 3 },
    { "TER", get_terminal(), 4 },
    { "WM", get_wm(), 5 },
    { "UP", get_uptime(), 3 },
  }

  local info = { get_user() .. "@" .. get_host() }

  -- width of the longest label (including the colon) so values line up
  local lw = 0
  for _, r in ipairs(rows) do
    if r[2] then lw = math.max(lw, #r[1] + 1) end
  end

  for _, r in ipairs(rows) do
    if r[2] then
      local label = r[1] .. ":"
      info[#info + 1] = bold(r[3], label) .. string.rep(" ", lw - #label) .. " " .. r[2]
    end
  end

  local offset = math.max(0, math.floor((#glyph - #info) / 2))
  local total = math.max(#glyph, #info + offset)
  local gap = (art_w > 0) and "    " or ""

  for i = 1, total do
    local left = glyph[i] or ""
    local pad = string.rep(" ", art_w - dispwidth(left))
    local right = info[i - offset] or ""
    io.write(fg(art_col, left), pad, gap, right, "\n")
  end
end

main()
