# i3-volume

Volume control with on-screen display notifications. Works with any window manager, such as [i3wm], [bspwm], and [KDE], as a standalone script, or with statusbars such as [polybar], [i3blocks], [i3status], and more.

[![License: GPL v2][license-badge]][license] ![build][build]

## Installation

Read the [installation instructions](https://github.com/hastinbe/i3-volume/wiki/Installation) to get started. For a specific usage:

- [i3wm](https://github.com/hastinbe/i3-volume/wiki/Installation#i3wm)
- [polybar](https://github.com/hastinbe/i3-volume/wiki/Installation#polybar)
- [i3blocks](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks)

### Usage

Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change. When notifications are enabled a popup will display the volume level.

#### On-Screen Notifications

| [notify-osd] | [dunst] | [xob] |
| ------------ | ------- | ----- |
| ![notify-osd notifications](https://github.com/hastinbe/i3-volume/wiki/images/notify-osd.png) | ![dunst notifications](https://github.com/hastinbe/i3-volume/wiki/images/dunst.png) | ![xob notifications](https://github.com/hastinbe/i3-volume/wiki/images/xob.png) |

| [XOSD] | [herbe] | [volnoti] |
| ------ | ------- | --------- |
| ![xosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/xosd.png) | ![herbe notifications](https://github.com/hastinbe/i3-volume/wiki/images/herbe.png) | ![volnoti notifications](https://github.com/hastinbe/i3-volume/wiki/images/volnoti.png)

| [KOSD] |
| ------ |
| ![kosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/kosd.png) |

Read about [notifications](https://github.com/hastinbe/i3-volume/wiki/Notifications) for more information.

### Standalone

`i3-volume` does not require any particular desktop environment and can be used as a standalone script.

#### Command-line options
```
Usage: ./volume [<options>] <command> [<args>]
Control volume and related notifications.

Commands:
  up [value]                  increase volume (uses default step if value omitted)
  down [value]                decrease volume (uses default step if value omitted)
  set <value>                 set volume
  wheel <delta>               mouse wheel volume control (accumulates small changes)
                              examples:
                                  wheel 2.0   - scroll up (positive delta)
                                  wheel -2.0 - scroll down (negative delta)
                              note: accumulates changes until reaching DEFAULT_STEP threshold
  mute                        toggle mute
  fade <from> <to> [duration_ms] fade volume smoothly
                              examples:
                                  fade 0 100        - fade from 0% to 100% (500ms)
                                  fade 0 100 2000  - fade from 0% to 100% over 2 seconds
  mic <cmd> [value]           control microphone
                              commands:
                                  up <value>    - increase microphone volume
                                  down <value>  - decrease microphone volume
                                  set <value>   - set microphone volume
                                  mute          - toggle microphone mute
  listen [options] [output_format] monitor volume changes
                              options:
                                  -a, --all          - monitor all sinks
                                  -I, --input        - monitor input sources
                                  --watch            - show real-time updates in terminal
                                  --volume-only      - only show volume change events
                                  --mute-only        - only show mute change events
                              examples:
                                  listen                    - monitor default sink
                                  listen -a                 - monitor all sinks
                                  listen -I                 - monitor all input sources
                                  listen --watch            - show terminal output
                                  listen -a --watch         - monitor all sinks with terminal output
                                  listen --volume-only      - only volume changes
                                  listen i3blocks           - output in i3blocks format
  list <type>                 list sinks, sources, or ports
                              types:
                                  sinks   - list all audio output sinks
                                  sources - list all audio input sources
                                  ports   - list ports for current sink (BETA: shows availability status)
  switch [sink]               switch to next sink or specified sink
  next                        switch to next sink
  prev                        switch to previous sink
  port <cmd> [port]           control audio ports (BETA/EXPERIMENTAL)
                              commands:
                                  list        - list available ports with availability status
                                  set <port>  - set active port
                              note: Port features are experimental and may not work on all devices
  profile <cmd> [name]       manage volume profiles
                              commands:
                                  save <name>   - save current settings as profile
                                  load <name>   - load a saved profile
                                  list          - list all saved profiles
                                  delete <name> - delete a profile
                              quick access:
                                  profile <name> - load profile (shortcut for load)
  boost <amount> [timeout]   temporarily boost volume
                              examples:
                                  boost 20        - boost by 20% for 30s (default)
                                  boost 20 60    - boost by 20% for 60s
                                  boost off      - cancel active boost
  sync                        sync volume across all active sinks
  balance [value]             control stereo balance (left/right)
                              examples:
                                  balance          - show current balance
                                  balance 0        - center balance
                                  balance -10      - shift 10% left
                                  balance +10      - shift 10% right
                                  balance -100     - full left
                                  balance 100      - full right
                              note: Balance range is -100 (left) to +100 (right), 0 is centered
                              Balance preference is stored per sink
  app <cmd> [args]            control per-application volume
                              commands:
                                  list                    - list all applications with audio streams
                                  <name> up [value]       - increase application volume
                                  <name> down [value]     - decrease application volume
                                  <name> set <value>      - set application volume
                                  <name> mute             - toggle application mute
                              examples:
                                  app list                - show all active applications
                                  app firefox up 5        - increase Firefox volume by 5%
                                  app mpv mute            - mute/unmute mpv
  output <format>             display volume in a custom format
                              special formats:
                                  json                        - JSON output with all volume information
                              format placeholders:
                                  %v = volume
                                  %s = sink name
                                  %p = volume progress bar
                                  %i = volume icon/emoji
                                  %P = active port description (BETA: includes availability status when available)
                                  %m = microphone volume
                                  %a = active application name
                                  %b = balance (L=left, R=right, C=center)
                                  %c = color codes (ANSI terminal colors)
                                  %n = node display name/alias
                                  %d = node id

                              conditional formatting:
                                  %v{>50:high:low}  - if volume > 50, show "high", else "low"
                                  %v{<30:quiet:normal} - if volume < 30, show "quiet", else "normal"
                                  %m{>80:loud:normal} - conditional on microphone volume
                                  %b{!=0:unbalanced:centered} - conditional on balance

                                  examples:
                                      output json              - JSON format for programmatic use
                                      "Volume is %v" = Volume is 50%
                                      "%i %v %p \n"  = 奔 50% ██████████
                                      "%c%v${COLOR_RESET}" = colored volume (if terminal supports)
                                      "%v{>50:high:low}" = "high" if volume > 50%, else "low"
  outputs                     show supported output formats
  notifications               list notification methods
  help                        show help

Options:
  -n                          enable notifications
  -q, --no-notify             disable notifications (quiet mode)
  -C                          play event sounds using libcanberra
  -P                          play sound for volume changes
  -j <muted,high,low,medium>  custom volume emojis
  -s <sink>                   specify sink (default: @DEFAULT_AUDIO_SINK@)
  -I <source>                 specify input source (default: @DEFAULT_AUDIO_SOURCE@)
  -a                          operate on all sinks (for up/down/set/mute)
  -t <process_name>           status bar process name (requires -u)
  -A <node.nick:alias>        alias a node nick (e.g., -A "ALC287 Analog:Speakers")
  -u <signal>                 signal to update status bar (requires -t)
  -D <value>                  set default step size (default: 5)
  -f <duration_ms>            fade duration in milliseconds (for set/up/down/mute)
  -x <value>                  set maximum volume
  -v                          verbose mode (detailed error information)
  --exit-code                 show detailed exit code information
  -h                          show help

Notification Options:
  -N <method>                 notification method (default: libnotify)
  -p                          enable progress bar in notifications
  -L <placement>              progress bar placement (default: summary; requires -p)
                              placements:
                                  body
                                  summary
  -e <ms>                     notification expiration time
  -l                          use full-color icons
  -S <suffix>                 add suffix to symbolic icon names
  -y                          use dunstify (default: notify-send)

Notification Features:
  - Notifications show sink name when multiple sinks are available
  - Port information is displayed in notifications when available (BETA/EXPERIMENTAL)
  - Port change detection shows when active port changes (BETA/EXPERIMENTAL)
  - Auto-suggestions for newly available ports (BETA/EXPERIMENTAL)
  - Sink and port changes trigger enhanced notifications with context
  - Set NOTIFICATION_GROUP=true in config to group volume change notifications (dunst only)
  - Plugin system for custom notification methods (see Custom Notification Plugins below)

Custom Plugins:
  i3-volume supports a generalized plugin system for extending functionality. Currently supported
  plugin types are notifications and output formats, with the infrastructure designed to easily
  support additional plugin types in the future.

  Plugin Directory Structure:
    ~/.config/i3-volume/plugins/notify/   - Notification plugins
    ~/.config/i3-volume/plugins/output/   - Output format plugins

  Notification Plugins:
    Create executable scripts in plugins/notify/
    Each plugin must define: notify_volume_<plugin-name>()
    Parameters: $1=volume, $2=icon, $3=summary, $4=body
    Usage: volume -N <plugin-name> up 5
    Example: examples/plugin.example

  Output Format Plugins:
    Create executable scripts in plugins/output/
    Each plugin must define: output_volume_<plugin-name>()
    Parameters: None (query volume state internally)
    Usage: volume output <plugin-name>
    Example: examples/plugin.output.example

  Use 'volume notifications' to list notification methods (including plugins).
  Use 'volume outputs' to list output formats (including plugins).

Environment Variables:
  XOSD_PATH                   path to osd_cat
  HERBE_PATH                  path to herbe
  VOLNOTI_PATH                path to volnoti-show
  CANBERRA_PATH               path to canberra-gtk-play
  NOTIFY_PATH                 path to command that sends notifications
  NO_NOTIFY_COLOR             flag to disable colors in notifications
  USE_NOTIFY_SEND_PY          flag to use notify-send.py instead of notify-send
  NOTIFICATION_GROUP          set to "true" to group volume change notifications (dunst only)
```

### Exit Codes

`i3-volume` uses standard exit codes to indicate the result of command execution. This is particularly useful for scripts that need to handle errors properly.

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `EX_OK` | Success - command executed successfully |
| 33 | `EX_URGENT` | Urgent - volume exceeds maximum limit (MAX_VOL) |
| 64 | `EX_USAGE` | Usage error - invalid command, option, or argument |
| 69 | `EX_UNAVAILABLE` | Unavailable - required tool or feature not available |

To view detailed information about exit codes, use the `--exit-code` option:

```bash
volume --exit-code
```

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

### Configuration

`i3-volume` also looks for a configuration file located at either `~/.config/i3-volume/config`, or `$XDG_CONFIG_HOME/i3-volume/config`. You can use this file to set any variables that are not set in the command line. For example, if you want to always display notifications using `dunst`. You can add the following to your config file:

```
NOTIFICATION_METHOD="dunst"
DISPLAY_NOTIFICATIONS=true
```

Or if using `i3blocks` as your statusline and `dunst` for notifications, aliasing the `analog-output-speaker` port to `Speaker` and using fullcolor icons:

```
STATUSLINE="i3blocks"
SIGNAL="SIGRTMIN+10"
NOTIFICATION_METHOD="dunst"
USE_DUNSTIFY=true
DISPLAY_NOTIFICATIONS=true
USE_FULLCOLOR_ICONS=true
PORT_ALIASES[analog-output-speaker]=Speaker
```

Now every invocation of the script will use these settings, unless overridden by command line options. For example, to set a default step size:

```
DEFAULT_STEP=10
```

This allows you to use `volume up` or `volume down` without specifying a step size each time. You can also use the `-D` option to set and save the default step size:

```bash
volume -D 10 up
```

This will save `DEFAULT_STEP=10` to your config file automatically, making it persistent for future invocations. To find more variables, check the [source code](https://github.com/hastinbe/i3-volume/blob/master/volume) of the `parse_opts` and `main` functions.

### Per-Sink Configuration

You can configure different settings for different audio devices (sinks). This is useful when you have multiple audio devices with different characteristics, such as headphones vs speakers.

Per-sink settings can be keyed by sink ID, name, or nick. Use `volume list sinks` to see available sink identifiers. Per-sink settings take precedence over global settings and are automatically applied when you switch sinks.

**Example configuration:**

```bash
# Global defaults
DEFAULT_STEP=5
MAX_VOL=100
DISPLAY_NOTIFICATIONS=true

# Per-sink overrides
# Headphones can go louder without distortion
SINK_MAX_VOL[USB Audio]=150
SINK_MAX_VOL[headphones]=120

# Smaller steps for headphones (more sensitive)
SINK_DEFAULT_STEP[USB Audio]=2
SINK_DEFAULT_STEP[headphones]=3

# Speakers should be limited to prevent damage
SINK_MAX_VOL[alsa_output.pci-0000_00_1f.3.analog-stereo]=100
SINK_MAX_VOL[Speakers]=100

# Larger steps for speakers (less sensitive)
SINK_DEFAULT_STEP[alsa_output.pci-0000_00_1f.3.analog-stereo]=10
SINK_DEFAULT_STEP[Speakers]=10

# Disable notifications for headphones (you can hear the volume change)
SINK_DISPLAY_NOTIFICATIONS[USB Audio]=false
SINK_DISPLAY_NOTIFICATIONS[headphones]=false

# Enable notifications for speakers (visual feedback helpful)
SINK_DISPLAY_NOTIFICATIONS[alsa_output.pci-0000_00_1f.3.analog-stereo]=true
SINK_DISPLAY_NOTIFICATIONS[Speakers]=true
```

**Supported per-sink settings:**
- `SINK_MAX_VOL[sink_identifier]` - Maximum volume limit for a specific sink
- `SINK_DEFAULT_STEP[sink_identifier]` - Default step size for volume changes
- `SINK_DISPLAY_NOTIFICATIONS[sink_identifier]` - Enable/disable notifications per sink
- `SINK_BALANCE[sink_identifier]` - Balance setting for a specific sink (-100 to +100)

See `examples/config.per-sink` for a complete example configuration file.

### Port Information Features (BETA/EXPERIMENTAL)

**⚠️ Note:** Port information features are currently in beta/experimental status. They may not work on all audio devices and may have limited functionality depending on your hardware and PipeWire configuration.

The port information system provides enhanced visibility into audio port status and management:

- **Port Listing**: Use `volume port list` to see all available ports for the current sink with availability status (plugged/unplugged)
- **Port Switching**: Use `volume port set <port_id>` to switch between available ports
- **Port Detection**: Enhanced port detection with multiple fallback methods for better compatibility
- **Availability Status**: Ports are marked with their availability status:
  - `[plugged]` - Port is available and ready to use
  - `[unplugged]` - Port is not currently available
  - `[unknown]` - Availability status cannot be determined
- **Port Change Notifications**: Notifications automatically show when the active port changes
- **Auto-Suggestions**: When a new port becomes available, you'll receive a notification suggesting to switch to it
- **%P Placeholder**: The `%P` placeholder in output formats includes port description and availability status when available

**Limitations:**
- Not all audio devices support port switching
- Port availability detection may vary by device
- Some devices may not expose port information through PipeWire
- Features are actively being improved and may change in future versions

If your device doesn't show ports, this is normal - not all audio hardware supports port switching or exposes port information.

## Migrating

### Version 2.x to 3.x

Version 3 introduces commands which makes it incompatible with previous versions. Your command-line usage and/or configured hotkeys need to be updated to reflect this.

| Change | v2 | v3 |
| ------ | -- | -- |
| `-d` is now the `down` command | `volume -d 5` | `volume down 5` |
| `-i` is now the `up` command | `volume -i 5` | `volume up 5` |
| `-m` is now the `mute` command | `volume -m` | `volume mute` |
| `-o` is now the `output` command | `volume -o i3blocks` | `volume output i3blocks` |
| `-v` is now the `set` command | `volume -v 5` | `volume set 5` |
| `-L` is now the `listen` command | `volume -L` | `volume listen` |
| `-M` is now the `-m` option | `volume -M Master` | `volume -m Master` |

## Interoperability

`i3-volume` is capable of working with many other programs. The following lists a few with examples:

| Program | Note |
| ---------- | ----- |
| **[i3blocks]** | See our [example blocklet](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks) |
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
