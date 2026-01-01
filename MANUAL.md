# i3-volume Manual

Complete command reference and documentation for `i3-volume`.

For a quick start guide, see [README.md](README.md). For detailed feature documentation, see the [wiki](https://github.com/hastinbe/i3-volume/wiki).

## Command Reference

```
Usage: ./volume [<options>] <command> [<args>]
Control volume and related notifications.

Commands:
  up [value]                  increase volume (uses default step if value omitted)
                              aliases: raise, increase
                              supports decimal values and dB: up 2.5, up 3dB
  down [value]                decrease volume (uses default step if value omitted)
                              aliases: lower, decrease
                              supports decimal values and dB: down 1.25, down 6dB
  set <value>                 set volume (supports decimal values and dB)
                              examples:
                                  set 50      - set to 50%
                                  set +10     - increase by 10% (relative)
                                  set -5      - decrease by 5% (relative)
                                  set 45.5    - set to 45.5% (may round to 46% depending on hardware)
                                  set -6dB    - set to -6dB (approximately 50% in dBFS scale)
                                  set 0dB     - set to 0dB (100%, full volume)
                              note: wpctl may round decimal values to nearest integer percentage
                              note: dB values use dBFS scale where 0dB = 100%, negative values attenuate
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
                                  fade 20.5 75.5   - fade from 20.5% to 75.5% (supports decimals)
  mic <cmd> [value]           control microphone
                              commands:
                                  up <value>    - increase microphone volume (aliases: raise, increase)
                                                    supports decimals
                                  down <value>  - decrease microphone volume (aliases: lower, decrease)
                                                    supports decimals
                                  set <value>   - set microphone volume (supports decimals)
                                                    examples: set 75, set +10, set -5
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
                              alias: previous
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
  normalize [cmd] [target]    normalize volume across sources
                              commands:
                                  suggest         - analyze and suggest adjustments (default)
                                  apply           - analyze and apply adjustments
                                  apply <target>  - normalize to specific target volume
                                  auto [interval] - auto-normalization mode (default: 5s)
                              examples:
                                  normalize                    - suggest volume adjustments
                                  normalize apply              - normalize all sources to average
                                  normalize apply 75           - normalize all sources to 75%
                                  normalize auto               - auto-normalize every 5 seconds
                                  normalize auto 10            - auto-normalize every 10 seconds
                              note: Analyzes volumes across all sinks and applications
                              Useful for consistent volume levels across different audio sources
  app <cmd> [args]            control per-application volume
                              commands:
                                  list                    - list all applications with audio streams
                                  <name> up [value]       - increase application volume (aliases: raise, increase)
                                  <name> down [value]     - decrease application volume (aliases: lower, decrease)
                                  <name> set <value>      - set application volume
                                                             examples: set 80, set +10, set -5
                                  <name> mute             - toggle application mute
                              examples:
                                  app list                - show all active applications
                                  app firefox up 5        - increase Firefox volume by 5%
                                  app mpv set +10         - increase mpv volume by 10% (relative)
                                  app vlc mute            - mute/unmute vlc
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
  config <cmd>                manage configuration
                              commands:
                                  show        - show current configuration
                                  validate    - validate config file syntax
                                  docs        - show all configurable variables
  undo                        restore previous volume level
                              examples:
                                  undo        - revert to last volume before current change
                              note: History is tracked automatically for volume changes
  history [count]             show volume change history
                              examples:
                                  history     - show last 10 volume changes
                                  history 20  - show last 20 volume changes
                              note: History persists across sessions in config directory
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
                              examples:
                                  -f 1000 up 10    - fade volume up by 10% over 1 second
                                  -f 500 set 50     - fade to 50% over 500ms
                                  -f 1000 mute      - smooth fade when muting/unmuting
  -x <value>                  set maximum volume
  -U <unit>                   display unit for volume output (percent or db)
                              examples:
                                  -U db      - display volume in dB
                                  -U percent - display volume in percentage (default)
                              note: can also be set in config file as VOLUME_DISPLAY_UNIT
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

## Quick Reference

### Most Common Commands

| Command | Description |
|---------|-------------|
| `volume up [value]` | Increase volume (default: 5%) |
| `volume down [value]` | Decrease volume (default: 5%) |
| `volume set <value>` | Set volume (supports `+10`, `-5`, `50`, `45.5`, `-6dB`) |
| `volume mute` | Toggle mute |
| `volume mic mute` | Toggle microphone mute |
| `volume list sinks` | List audio output devices |
| `volume switch` | Switch to next audio device |

### Command Aliases

- `up` = `raise` = `increase`
- `down` = `lower` = `decrease`
- `prev` = `previous`

## See Also

- [README.md](README.md) - Quick start guide
- [Features Wiki](https://github.com/hastinbe/i3-volume/wiki/Features) - Detailed feature documentation
- [Configuration Wiki](https://github.com/hastinbe/i3-volume/wiki/Configuration) - Configuration options
- Run `volume help` for complete usage information

