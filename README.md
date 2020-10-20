# i3-volume

Volume control with notifications, and a volume statusline indicator. Written for use with [i3wm], but works with any window manager or as a standalone script.

[![License: GPL v2][license-badge]][license]

## Installation

Read our [installation instructions](https://github.com/hastinbe/i3-volume/wiki/Installation) for general usage with [i3wm].

### Usage

Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change. When notifications are enabled a popup will display the volume level.


#### On-Screen Notifications

| [notify-osd] | [dunst] | [xob] |
| ------------ | ------- | ----- |
| ![notify-osd notifications](https://github.com/hastinbe/i3-volume/wiki/images/notify-osd.png) | ![dunst notifications](https://github.com/hastinbe/i3-volume/wiki/images/dunst.png) | ![xob notifications](https://github.com/hastinbe/i3-volume/wiki/images/xob.png) |

| [xosd] | [herbe] | [volnoti] |
| ------ | ------- | --------- |
| ![xosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/xosd.png) | ![herbe notifications](https://github.com/hastinbe/i3-volume/wiki/images/herbe.png) | ![volnoti notifications](https://github.com/hastinbe/i3-volume/wiki/images/volnoti.png)

Read about [notifications](https://github.com/hastinbe/i3-volume/wiki/Notifications) for more information.

### Standalone

`i3-volume` does not require any particular desktop environment and can be used as a standalone script.

#### Command-line options
```
Usage: ./volume [<options>] <command> [<args>]
Control volume and related notifications.

Commands:
  up <value>            increase volume
  down <value>          decrease volume
  set <value>           set volume
  mute                  toggle mute
  listen                listen for changes to a PulseAudio sink
  output <format>       output volume in a supported format
                        custom format substitutions:
                            %v = volume
                            example: "My current volume is %v"
  outputs               show available output formats
  notifications         show available notification methods
  help                  display help

Options:
  -a                    use amixer
  -n                    enable notifications
  -t <process_name>     process name of status bar (requires -u)
  -u <signal>           signal to update status bar (requires -t)
  -x <value>            maximum volume
  -X <value>            maximum amplification; if supported (default: 2)
  -h                    display help

amixer Options:
  -c <card>             card number to control
  -m <mixer>            set mixer (default: Master)

PulseAudio Options:
  -s <sink>             symbolic name of sink

Notification Options:
  -N <method>           notification method (default: libnotify)
  -p                    enable progress bar
  -e <expires>          expiration time of notifications in ms
  -l                    use fullcolor instead of symbolic icons
  -S <suffix>           append suffix to symbolic icon names
  -y                    use dunstify (default: notify-send)
```

#### Listen mode (PulseAudio only)

Listen mode (`-L`) causes `i3-volume` to listen for changes on your PulseAudio sink. When configured, these events will update your status bar and dispatch on-screen display notifications to reflect the change.

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
| `-M` is now the `-m` option | `volume -M Master` | `volume -m Master` |

## Interoperability

`i3-volume` is capable of working with many other programs. The following lists a few with examples:

| Program | Note |
| ---------- | ----- |
| **[i3blocks]** | See our [example blocklet](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks) |
| **[xob]** | Requires extra steps for notifications. [Guide](https://github.com/hastinbe/i3-volume/wiki/Usage-with-xob) |
| **[xosd]** | Notifications require the `-N xosd` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-XOSD)
| **[herbe]** | Notifications require the `-N herbe` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-herbe)
| **[volnoti]** | Notifications require the `-N volnoti` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-volnoti)
| **[sxhkd]** | For keybindings with or without [i3wm], often used with [bspwm]. [Example](https://github.com/hastinbe/i3-volume/wiki/Keybindings#sxkhd)

## Help

Having a problem? Try reading our [common issues](https://github.com/hastinbe/i3-volume/wiki/Common-Issues) or open an [issue](https://github.com/hastinbe/i3-volume/issues/new).

## License
`i3-volume` is released under [GNU General Public License v2][license]

Copyright (C) 1989, 1991 Free Software Foundation, Inc.

[alsa-utils]: https://alsa.opensrc.org/Alsa-utils
[bspwm]: https://github.com/baskerville/bspwm
[dunst]: https://dunst-project.org
[herbe]: https://github.com/dudik/herbe
[i3blocks]: https://github.com/vivien/i3blocks
[i3status]: https://github.com/i3/i3status
[i3wm]: https://i3wm.org
[libnotify]: https://developer.gnome.org/libnotify
[license]: https://www.gnu.org/licenses/gpl-2.0.en.html
[license-badge]: https://img.shields.io/badge/License-GPL%20v2-blue.svg
[logo]: assets/logo.svg
[notify-osd]: https://launchpad.net/notify-osd
[pulseaudio-utils]: https://www.freedesktop.org/wiki/Software/PulseAudio/
[sxhkd]: https://github.com/baskerville/sxhkd
[volnoti]: https://github.com/davidbrazdil/volnoti
[wiki]: https://github.com/hastinbe/i3-volume/wiki
[xob]: https://github.com/florentc/xob
[xosd]: https://sourceforge.net/projects/libxosd/
