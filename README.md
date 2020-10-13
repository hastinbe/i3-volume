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

| [xosd] | [herbe] |
| ------ | ------- |
| ![xosd notifications](https://github.com/hastinbe/i3-volume/wiki/images/xosd.png) | ![herbe notifications](https://github.com/hastinbe/i3-volume/wiki/images/herbe.png) |

Read about [notifications](https://github.com/hastinbe/i3-volume/wiki/Notifications) for more information.

### Standalone

`i3-volume` does not require any particular desktop environment and can be used as a standalone script.

#### Command-line options
```
Usage: volume [options]
Control volume and related notifications.

Options:
  -a                                    use alsa-utils instead of pulseaudio-utils for volume control
  -c <card>                             card number to control (amixer only)
  -d <amount>                           decrease volume
  -e <expires>                          expiration time of notifications, in milliseconds
  -i <amount>                           increase volume
  -l                                    use fullcolor instead of symbolic icons
  -m                                    toggle mute
  -M <mixer>                            specify mixer (ex: Headphone), default Master
  -n                                    show notifications
  -N <libnotify|herbe|xosd>             notification method (default: libnotify)
  -o <generic|i3blocks|xob|"format">    output the volume according to the provided output format:
                                            generic  = output the volume
                                            i3blocks = output the volume for i3blocks
                                            xob      = output the volume for xob
                                            "format" = output using a format string. substitutions:
                                                        %v = current volume
  -p                                    show text volume progress bar
  -s <sink_name>                        symbolic name of sink (pulseaudio only)
  -S <suffix>                           add a suffix to symbolic icon names
  -t <process_name>                     name of status line process. must be used with -u
  -u <signal>                           update status line using signal. must be used with -t
  -v <value>                            set volume
  -x <value>                            set maximum volume
  -X <value>                            set maximum amplification (if the device supports it. default: 2)
  -y                                    use dunstify instead of notify-send
  -h                                    display this help and exit
  ```

## Interoperability

`i3-volume` is capable of working with many other programs. The following lists a few with examples:

| Program | Note |
| ---------- | ----- |
| **[i3blocks]** | See our [example blocklet](https://github.com/hastinbe/i3-volume/wiki/Usage-with-i3blocks) |
| **[xob]** | Requires extra steps for notifications. [Guide](https://github.com/hastinbe/i3-volume/wiki/Usage-with-xob) |
| **[xosd]** | Notifications require the `-N xosd` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-XOSD)
| **[herbe]** | Notifications require the `-N herbe` option. [Example](https://github.com/hastinbe/i3-volume/wiki/Usage-with-herbe)
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
[wiki]: https://github.com/hastinbe/i3-volume/wiki
[xob]: https://github.com/florentc/xob
[xosd]: https://sourceforge.net/projects/libxosd/
