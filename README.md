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
  up <value>                  increase volume
  down <value>                decrease volume
  set <value>                 set volume
  mute                        toggle mute
  listen                      listen for changes to a PulseAudio sink
  output <format>             output volume in a supported format
                              custom format substitutions:
                                  %v = volume
                                  %s = sink name (PulseAudio only)
                                  %c = card (alsamixer only)
                                  %m = mixer (alsamixer only)
                                  %p = volume progress bar
                                  %i = volume icon/emoji
                                  %P = active port description (PulseAudio only)

                                  examples:
                                      "Volume is %v" = Volume is 50%
                                      "%i %v %p \n"  = 奔 50% ██████████
  outputs                     show available output formats
  notifications               show available notification methods
  help                        display help

Options:
  -a                          use amixer
  -n                          enable notifications
  -C                          use libcanberra for playing event sounds
  -P                          play sound for volume changes
  -j <muted,high,low,medium>  specify custom volume emojis as a comma separated list
  -t <process_name>           process name of status bar (requires -u)
  -u <signal>                 signal to update status bar (requires -t)
  -x <value>                  maximum volume
  -X <value>                  maximum amplification; if supported (default: 2)
  -h                          display help

amixer Options:
  -c <card>                   card number to control
  -m <mixer>                  set mixer (default: Master)

PulseAudio Options:
  -s <sink>                   symbolic name of sink
  -A <port:alias>             specify an alias for a port name (e.g., -A "Speakers:Living Room")

Notification Options:
  -N <method>                 notification method (default: libnotify)
  -p                          enable progress bar
  -L <placement>              progress bar placement (default: summary; requires -p)
                              placements:
                                  body
                                  summary
  -e <expires>                expiration time of notifications in ms
  -l                          use fullcolor instead of symbolic icons
  -S <suffix>                 append suffix to symbolic icon names
  -y                          use dunstify (default: notify-send)

Environment Variables:
  XOSD_PATH                   path to osd_cat
  HERBE_PATH                  path to herbe
  VOLNOTI_PATH                path to volnoti-show
  CANBERRA_PATH               path to canberra-gtk-play
  NOTIFY_PATH                 path to command that sends notifications
  NO_NOTIFY_COLOR             flag to disable colors in notifications
  USE_NOTIFY_SEND_PY          flag to use notify-send.py instead of notify-send
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

Now every invocation of the script will use these settings, unless overridden by command line options. To find more variables, check the [source code](https://github.com/hastinbe/i3-volume/blob/master/volume) of the `parse_opts` and `main` functions.

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

[alsa-utils]: https://alsa.opensrc.org/Alsa-utils
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
