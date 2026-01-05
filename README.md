# i3-volume

Volume control with on-screen display notifications. Works with any window manager, such as [i3wm], [bspwm], and [KDE], as a standalone script, or with statusbars such as [i3status-rust], [polybar], [i3blocks], [i3status], and more.

[![License: GPL v2][license-badge]][license] ![build][build]

## Quick Start

### Basic Commands

```bash
volume up              # Increase volume by default step (5%)
volume down            # Decrease volume by default step (5%)
volume set 50         # Set to 50%
volume set +10         # Increase by 10% (relative)
volume mute           # Toggle mute
volume mic mute        # Toggle microphone mute
```

**Command Aliases:** `up` = `raise` = `increase`, `down` = `lower` = `decrease`, `prev` = `previous`

### With Notifications

```bash
volume -n up 5         # Increase with notification
volume -n -N dunst up 5  # Use dunst for notifications
```

### For Status Bars

```bash
volume -j \",󰕾,󰕿,󰖀\" output \"%i %n %c%v %p \n\" # i3status-rust
volume output i3blocks  # i3blocks format (mouse wheel auto-handled)
volume output polybar   # polybar format
```

See [Installation](https://github.com/hastinbe/i3-volume/wiki/Installation) for setup instructions.

## Key Features

- 🎚️ **Volume Control**: Increase, decrease, set, mute with decimal and dB support
- 🎤 **Microphone Control**: Control input volume and mute state
- 🎯 **Per-Application Volume**: Control individual app volumes independently
- 📊 **Multiple Sinks**: Switch between audio devices, sync volumes across sinks
- 🎨 **Notifications**: Support for dunst, notify-osd, xob, XOSD, herbe, volnoti, KOSD
- 🔌 **Plugin System**: Custom notification and output format plugins
- ⚙️ **Per-Sink Configuration**: Different settings for different audio devices
- 📈 **Advanced Features**: Volume profiles, boost, balance, normalization, smooth fade transitions

[See all features →](https://github.com/hastinbe/i3-volume/wiki/Features)

## Installation

Read the [installation instructions](https://github.com/hastinbe/i3-volume/wiki/Installation) to get started. For specific setups:

- [i3wm](https://github.com/hastinbe/i3-volume/wiki/Installation#i3wm)
- [i3status-rust](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3status-rust)
- [polybar](https://github.com/hastinbe/i3-volume/wiki/Installation#polybar)
- [i3blocks](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks)

## Usage Examples

### Basic Volume Control

```bash
volume up 10           # Increase by 10%
volume down 5          # Decrease by 5%
volume set 50          # Set to 50%
volume set +10         # Increase by 10% (relative)
volume set -5          # Decrease by 5% (relative)
volume set 45.5        # Set to 45.5% (decimal support)
volume set -6dB        # Set to -6dB (dB support)
volume -f 1000 up 10   # Fade volume up by 10% over 1 second
volume -d up 10        # Test what would happen (dry-run mode)
```

### Advanced Features

```bash
# Per-application volume control
volume app list                # List all applications with audio
volume app firefox up 5        # Increase Firefox volume by 5%
volume app mpv set +10         # Increase mpv volume by 10% (relative)

# Volume profiles
volume profile save quiet      # Save current settings as "quiet"
volume profile load loud       # Load saved "loud" profile

# Temporary volume boost
volume boost 20 60             # Boost by 20% for 60 seconds

# Stereo balance
volume balance -10             # Shift 10% to left speaker
volume balance +10             # Shift 10% to right speaker

# Sink management
volume list sinks              # List all audio devices
volume switch                  # Switch to next audio device
volume sync                    # Sync volume across all sinks
```

**Full Command Reference:** See [MANUAL.md](MANUAL.md) or run `volume help` for complete usage.

## On-Screen Notifications

| [notify-osd] | [dunst] | [xob] |
| ------------ | ------- | ----- |
| ![notify-osd notifications](https://github.com/hastinbe/i3-volume/wiki/images/notify-osd.png) | ![dunst notifications](https://github.com/hastinbe/i3-volume/wiki/images/dunst.png) | ![xob notifications](https://github.com/hastinbe/i3-volume/wiki/images/xob.png) |

| [XOSD] | [herbe] | [volnoti] |
| ------ | ------- | --------- |
| ![xosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/xosd.png) | ![herbe notifications](https://github.com/hastinbe/i3-volume/wiki/images/herbe.png) | ![volnoti notifications](https://github.com/hastinbe/i3-volume/wiki/images/volnoti.png) |

| [KOSD] |
| ------ |
| ![kosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/kosd.png) |

Read about [notifications](https://github.com/hastinbe/i3-volume/wiki/Notifications) for more information.

## Configuration

`i3-volume` looks for a configuration file at `~/.config/i3-volume/config` or `$XDG_CONFIG_HOME/i3-volume/config`.

### Basic Configuration

```bash
# Enable notifications with dunst
NOTIFICATION_METHOD="dunst"
DISPLAY_NOTIFICATIONS=true
USE_DUNSTIFY=true

# Set default step size
DEFAULT_STEP=10

# Set maximum volume
MAX_VOL=100
```

### i3blocks Configuration

**Note:** When using `i3blocks`, mouse wheel events are automatically handled. Scrolling up or down on the volume block will increase or decrease the volume without any additional configuration.

```bash
STATUSLINE="i3blocks"
SIGNAL="SIGRTMIN+10"
NOTIFICATION_METHOD="dunst"
USE_DUNSTIFY=true
DISPLAY_NOTIFICATIONS=true
USE_FULLCOLOR_ICONS=true
PORT_ALIASES[analog-output-speaker]=Speaker
```

### Per-Sink Configuration

Configure different settings for different audio devices:

```bash
# Global defaults
DEFAULT_STEP=5
MAX_VOL=100

# Per-sink overrides
SINK_MAX_VOL[USB Audio]=150        # Headphones can go louder
SINK_DEFAULT_STEP[USB Audio]=2     # Smaller steps for headphones
SINK_DISPLAY_NOTIFICATIONS[USB Audio]=false  # Disable notifications
```

**Supported per-sink settings:**
- `SINK_MAX_VOL[sink_identifier]` - Maximum volume limit
- `SINK_DEFAULT_STEP[sink_identifier]` - Default step size
- `SINK_DISPLAY_NOTIFICATIONS[sink_identifier]` - Enable/disable notifications
- `SINK_BALANCE[sink_identifier]` - Balance setting (-100 to +100)

See [Configuration wiki](https://github.com/hastinbe/i3-volume/wiki/Configuration) for all options and examples.

## Command Reference

### Volume Control
- `up [value]`, `down [value]`, `set <value>`, `mute`
- Aliases: `raise`/`increase` for up, `lower`/`decrease` for down
- Supports decimals and dB: `set 45.5`, `set -6dB`, `set +10`

### Microphone
- `mic up/down/set/mute` - Control microphone volume
- Aliases: `mic raise`/`mic increase` for up, `mic lower`/`mic decrease` for down
- Relative operations: `mic set +10`, `mic set -5`

### Applications
- `app list` - List apps with audio
- `app <name> up/down/set/mute` - Control app volume
- Aliases: `app <name> raise`/`app <name> increase` for up, `app <name> lower`/`app <name> decrease` for down
- Relative operations: `app <name> set +10`, `app <name> set -5`

### Sinks & Devices
- `list sinks/sources` - List audio devices
- `switch/next/prev` - Switch between sinks (alias: `previous` for `prev`)
- `sync` - Sync volume across sinks

### Advanced
- `profile save/load/list/delete` - Volume profiles
- `boost <amount> [timeout]` - Temporary volume boost
- `balance [value]` - Stereo balance (-100 to +100)
- `normalize [cmd]` - Normalize volumes across sources
- `fade <from> <to> [duration]` - Smooth volume transitions
- `fade option`: Use `-f <duration_ms>` with `up`, `down`, `set`, or `mute` for smooth transitions
- `undo` - Restore previous volume
- `history [count]` - View volume history

**Full Reference:**
- See [MANUAL.md](MANUAL.md) for complete command reference
- Run `volume help` for complete usage information
- See [Features wiki](https://github.com/hastinbe/i3-volume/wiki/Features) for detailed documentation

## Exit Codes

`i3-volume` uses standard exit codes for script integration:

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `EX_OK` | Success - command executed successfully |
| 33 | `EX_URGENT` | Urgent - volume exceeds maximum limit (MAX_VOL) |
| 64 | `EX_USAGE` | Usage error - invalid command, option, or argument |
| 69 | `EX_UNAVAILABLE` | Unavailable - required tool or feature not available |

**Example usage in scripts:**

```bash
#!/bin/bash
if ! volume up 5; then
    case $? in
        64) echo "Usage error - check command syntax" ;;
        69) echo "Tool unavailable - check dependencies" ;;
        33) echo "Volume limit exceeded" ;;
    esac
fi
```

Use `volume --exit-code` to view detailed exit code information.

## Practical Examples

### Keyboard Shortcuts (i3wm/sxhkd)

```bash
# In ~/.config/i3/config
bindsym XF86AudioRaiseVolume exec --no-startup-id volume up
bindsym XF86AudioLowerVolume exec --no-startup-id volume down
bindsym XF86AudioMute exec --no-startup-id volume mute
bindsym XF86AudioMicMute exec --no-startup-id volume mic mute

# With notifications
bindsym XF86AudioRaiseVolume exec --no-startup-id volume -n up
bindsym XF86AudioLowerVolume exec --no-startup-id volume -n down

# In ~/.config/sxhkd/sxhkdrc (sxhkd doesn't use --no-startup-id)
XF86AudioRaiseVolume
    volume up
XF86AudioLowerVolume
    volume down
XF86AudioMute
    volume mute
XF86AudioMicMute
    volume mic mute
```

### Scripts with Exit Codes

```bash
#!/bin/bash
# Safe volume increase with error handling
if volume up 5; then
    echo "Volume increased successfully"
else
    case $? in
        33) notify-send "Volume limit reached" ;;
        64) notify-send "Invalid command" ;;
        69) notify-send "Audio system unavailable" ;;
    esac
fi
```

### Combining Options

```bash
# Fade with notifications
volume -n -f 1000 up 10

# Multiple sinks with fade
volume -a -f 500 set 50

# Custom notification method with fade
volume -n -N dunst -f 1000 mute

# Test commands without executing (dry-run mode)
volume -d up 10          # See what would happen without changing volume
volume --dry-run set 50   # Test setting volume to 50%
volume -d switch          # See which sink would be switched to

# Logging and debugging
volume --log up 5         # Log operations to syslog
volume --log /tmp/volume.log up 5  # Log to custom file
volume --log --debug up 5 # Enable debug mode with verbose logging
```

## Interoperability

`i3-volume` works with many other programs:

| Program | Note |
| ---------- | ----- |
| **[i3blocks]** | See our [example blocklet](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks). Mouse wheel events are automatically handled - scrolling on the volume block adjusts volume without additional configuration. |
| **[i3status-rust]** | See our [example custom block](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3status-rust) |
| **[xob]** | Requires extra steps for notifications. [Guide](https://github.com/hastinbe/i3-volume/wiki/Usage-with-xob) |
| **[XOSD]** | Notifications require the `-N xosd` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-XOSD) |
| **[herbe]** | Notifications require the `-N herbe` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-herbe) |
| **[volnoti]** | Notifications require the `-N volnoti` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-volnoti) |
| **[KOSD]** | Notifications require the `-N kosd` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-kosd) |
| **[sxhkd]** | For keybindings with or without [i3wm], often used with [bspwm]. [Example](https://github.com/hastinbe/i3-volume/wiki/Keybindings#sxkhd) |

## Help

Having a problem? Try reading our [common issues](https://github.com/hastinbe/i3-volume/wiki/Common-Issues) or open an [issue](https://github.com/hastinbe/i3-volume/issues/new).

## License

`i3-volume` is released under [GNU General Public License v2][license]

Copyright (C) 1989, 1991 Free Software Foundation, Inc.

[bspwm]: https://github.com/baskerville/bspwm
[build]: https://github.com/hastinbe/i3-volume/actions/workflows/shellcheck.yml/badge.svg
[dunst]: https://dunst-project.org
[herbe]: https://github.com/dudik/herbe
[KDE]: https://kde.org
[KOSD]: https://store.kde.org/p/1127472/show/page/5
[i3blocks]: https://github.com/vivien/i3blocks
[i3status]: https://github.com/i3/i3status
[i3status-rust]: https://github.com/greshake/i3status-rust
[i3wm]: https://i3wm.org
[libnotify]: https://developer.gnome.org/libnotify
[license]: https://www.gnu.org/licenses/gpl-2.0.en.html
[license-badge]: https://img.shields.io/badge/License-GPL%20v2-blue.svg
[logo]: assets/logo.svg
[notify-osd]: https://launchpad.net/notify-osd
[polybar]: https://github.com/polybar/polybar
[pulseaudio-utils]: https://www.freedesktop.org/wiki/Software/PulseAudio/
[sxhkd]: https://github.com/baskerville/sxhkd
[volnoti]: https://github.com/davidbrazdil/volnoti
[wiki]: https://github.com/hastinbe/i3-volume/wiki
[xob]: https://github.com/florentc/xob
[XOSD]: https://sourceforge.net/projects/libxosd/
