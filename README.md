# i3-volume

Volume control with notifications, and a volume statusline indicator. Written for use with [i3wm], but works with any window manager or as a standalone script.

[![License: GPL v2][license-badge]][license]

## Installation

### Requirements
* awk (POSIX compatible)
* [pulseaudio-utils] - if using PulseAudio
* [alsa-utils] - if using amixer

### Optional / Recommended
* [notify-osd] - Canonical's on-screen-display notification agent
* [dunst] - a lightweight replacement for the notification daemons provided by most desktop environments
* [i3wm] - a tiling window manager designed for X11
* [i3blocks] - a feed generator for text based status bars

### Arch Linux
Arch Linux users may find PKGBUILD in [aur].

### Guide
Clone this repository:
``` bash
git clone https://github.com/hastinbe/i3-volume.git ~/i3-volume
```

#### i3wm

Volume control can be done through either [alsa-utils], [pulseaudio-utils], or both. Use one of the example configuration files below:

##### PulseAudio

``` bash
cat i3volume-pulseaudio.conf >> ~/.config/i3/config
```

##### Alsamixer

``` bash
cat i3volume-alsa.conf >> ~/.config/i3/config
```

Reload [i3wm] by pressing `mod+Shift+r` and use the volume keys on your keyboard.

#### Other window managers

If you get `i3-volume` to work on another window manager beside [i3wm], we welcome you to contribute your experience to help others.

#### Standalone

See [usage](#usage).

## Usage
Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change. When notifications are enabled a popup will display the volume level.

### Command-line options
```
Usage: volume [options]
Control volume and related notifications.

Options:
  -a                use alsa-utils instead of pulseaudio-utils for volume control
  -c <card>         card number to control (amixer only)
  -d <amount>       decrease volume
  -e <expires>      expiration time of notifications, in milliseconds
  -i <amount>       increase volume
  -l                use fullcolor instead of symbolic icons
  -m                toggle mute
  -M <mixer>        specify mixer (amixer only, default: Master)
  -n                show notifications
  -o <generic|i3blocks|"format">
                    output the volume according to the provided output format:
                        generic  = output the volume
                        i3blocks = output the volume for i3blocks
                        "format" = output using a format string. substitutions:
                                     %v = current volume
  -p                show text volume progress bar
  -s <sink_name>    symbolic name of sink (pulseaudio only)
  -S <suffix>       add a suffix to symbolic icon names
  -t <process_name> name of status line process. must be used with -u
  -u <signal>       update status line using signal. must be used with -t
  -v <value>        set volume
  -x <value>        set maximum volume
  -X <value>        set maximum amplification (if the device supports it. default: 2)
  -y                use dunstify instead of notify-send
  -h                display this help and exit
  ```

### Notifications

Notifications are provided by [libnotify]. Any [libnotify] compatible notification daemon can be used for notifications. The most common are [notify-osd] and [dunst].

![Volume Notifications](assets/notifications.png)

If you are using [dunst], you may optionally choose to use `dunstify` instead of `notify-send` by adding the `-y` option.

Expiration time of notifications can be changed using the `-e <time_in_milliseconds>` option. Default is 1500 ms. (Ubuntu's Notify OSD and GNOME Shell both ignore the expiration parameter.)

## Common Issues
* [alsa-utils] won't unmute if `pulseaudio` is running. You must disable pulseaudio's auto-respawn and terminate the `pulseaudio` process. Or use [pulseaudio-utils] for unmuting.
* [dunst] isn't displaying icons in notifications. `icon_position` needs to be set to either `left` or `right` (default is `off`) in your `~/.config/dunst/dunstrc`.
* [dunst] icons are too small. Change `icon_path` in your `~/.config/dunst/dunstrc` to a path containing larger icons, such as `/usr/share/icons/gnome/32x32/status/:/usr/share/icons/gnome/32x32/devices/`. Alternatively try increasing `max_icon_size`

**Note** only one notification daemon can be running at the same time. [dunst] can't be running for notifications to go through [notify-osd] and vice-versa.

## License
`i3-volume` is released under [GNU General Public License v2][license]

Copyright (C) 1989, 1991 Free Software Foundation, Inc.

[alsa-utils]: https://alsa.opensrc.org/Alsa-utils
[aur]: https://aur.archlinux.org/packages/i3-volume/
[dunst]: https://dunst-project.org
[i3blocks]: https://github.com/vivien/i3blocks
[i3wm]: https://i3wm.org
[libnotify]: https://developer.gnome.org/libnotify
[license]: https://www.gnu.org/licenses/gpl-2.0.en.html
[license-badge]: https://img.shields.io/badge/License-GPL%20v2-blue.svg
[logo]: assets/logo.svg
[notify-osd]: https://launchpad.net/notify-osd
[pulseaudio-utils]: https://www.freedesktop.org/wiki/Software/PulseAudio/
