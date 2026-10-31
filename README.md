# luafetch

Minimal system fetch in pure Lua. Shows your OS initial in a big ASCII font next to system info.

```
  .g8"""bgd      blck@gentoo
.dP'     `M      OS:  Gentoo Linux
dM'       `      KER: 7.2.11-gentoo-dist-bin
MM               SH:  bash
MM.    `7MMF'    TER: alacritty
`Mb.     MM      WM:  dwm(x11)
  `"bmmmdPY      UP:  0 days, 1 hours, 8 minutes
```

## Requirements

- Lua 5.1+
- `xprop` (optional, for WM detection on X11)

## Install

```sh
git clone https://github.com/youruser/luafetch.git
cd luafetch
doas install -Dm755 luafetch.lua /usr/local/bin/luafetch
doas install -Dm644 ascii.txt /usr/share/luafetch/ascii.txt
```

Use `sudo` instead of `doas` if you prefer. The first line of `luafetch.lua` must be `#!/usr/bin/env lua`.

No root? Install for your user only (make sure `~/.local/bin` is in your `PATH`):

```sh
mkdir -p ~/.local/bin ~/.config/luafetch
install -m755 luafetch.lua ~/.local/bin/luafetch
cp ascii.txt ~/.config/luafetch/
```

## Usage

```sh
luafetch        # detect OS, show its initial
luafetch x      # force a letter
LUAFETCH_COLOR=6 luafetch
```

| Variable         | Description                      |
| ---------------- | -------------------------------- |
| `LUAFETCH_ART`   | path to a custom font file       |
| `LUAFETCH_COLOR` | art color, `0`-`7` (default `7`) |

## Font file

`ascii.txt` holds 26 glyphs, A to Z in order, separated by blank lines. It is searched in:

1. `$LUAFETCH_ART`
2. next to the script
3. `~/.config/luafetch/ascii.txt`
4. `/usr/share/luafetch/ascii.txt`

## Info shown

`OS`, `KER` (kernel), `SH` (shell), `TER` (terminal), `WM`, `UP` (uptime). Anything that can't be detected is hidden.

## Update / remove

```sh
git pull                                  # then re-run the install commands
doas rm /usr/local/bin/luafetch
doas rm -r /usr/share/luafetch
```

## Status

Tested on Linux. macOS and BSD should work. Windows is experimental.
