i3-volume
=========
[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)][license]

Volume control and volume notifications for [i3wm]

## Installation

#### Requirements
* [i3wm]
* [alsa-utils] or [pulseaudio-utils]

#### Optional
* [notify-osd], [dunst], or any [libnotify] compatible notification daemon
* `notify-send` (provided by [libnotify]) or `dunstify` (provided by [dunst])

#### Arch Linux
Arch Linux users may find PKGBUILD in [aur].

#### ALSA mixer and PulseAudio
Volume control can be done through either [alsa-utils], [pulseaudio-utils], or both. Use one of the example configuration to get started.

#### Notifications
Notifications are provided by [libnotify]. Any [libnotify] compatible notification daemon can be used for notifications. The most common are [notify-osd] and [dunst].

If you are using [dunst], you may optionally choose to use `dunstify` instead of `notify-send` by adding the `-y` option.

Expiration time of notifications can be changed using the `-e <time_in_milliseconds>` option. Default is 1500 ms. (Ubuntu's Notify OSD and GNOME Shell both ignore the expiration parameter.)

### Guide
Clone this repository: `git clone https://github.com/hastinbe/i3-volume.git ~/i3-volume`

Append the contents of the sample configuration files `i3volume-alsa.conf` or `i3volume-pulseaudio.conf` to your i3 config, such as `~/.config/i3/config`

Reload i3 configuration by pressing `mod+Shift+r`

## Usage
Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change. When notifications are enabled a popup will display the volume level.

Example of notifications using [notify-osd]:

![Volume Notifications](https://github.com/hastinbe/i3-volume/blob/master/volume-notifications.png)

## Common Issues
* [alsa-utils] won't unmute if `pulseaudio` is running. You must disable pulseaudio's auto respawn and terminate the `pulseaudio` process. Or use [pulseaudio-utils] for unmuting.
* [dunst] isn't displaying icons in notifications. `icon_position` needs to be set to either `left` or `right` (default is `off`) in your `~/.config/dunst/dunstrc`.
* [dunst] icons are too small. Change `icon_path` in your `~/.config/dunst/dunstrc` to a path containing larger icons, such as `/usr/share/icons/gnome/32x32/status/:/usr/share/icons/gnome/32x32/devices/`. Alternatively try increasing `max_icon_size`

`Note` only one notification daemon can be running at the same time. [dunst] can't be running for notifications to go through [notify-osd] and vice-versa.

## License
`i3-volume` is released under [GNU General Public License v2][license]

Copyright (C) 1989, 1991 Free Software Foundation, Inc.

[alsa-utils]: https://alsa.opensrc.org/Alsa-utils
[aur]: https://aur.archlinux.org/packages/i3-volume/
[dunst]: https://dunst-project.org
[i3wm]: https://i3wm.org
[libnotify]: https://developer.gnome.org/libnotify
[license]: https://www.gnu.org/licenses/gpl-2.0.en.html
[notify-osd]: https://launchpad.net/notify-osd
[pulseaudio-utils]: https://www.freedesktop.org/wiki/Software/PulseAudio/
