i3-volume
=========
[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)][license]

Volume control and volume notifications for [i3wm]

## Installation

#### Requirements
* [i3wm] - A better tiling and dynamic window manager
* [alsa-utils] (if not using [pulseaudio-utils]) - Advanced Linux Sound Architecture utils
* [pulseaudio-utils] (if not using [alsa-utils]) - Sound system for POSIX OSes

#### Optional
* A [libnotify] compatible notification daemon such as [notify-osd] or [dunst]
* `notify-send` (provided by [libnotify]) or `dunstify` (provided by [dunst])

#### ALSA mixer and PulseAudio
Volume control can be done through either [alsa-utils], [pulseaudio-utils], or both. The example configuration uses [pulseaudio-utils]. If you want to use [alsa-utils] instead, comment out the `bindsyms` under [pulseaudio-utils] and uncomment the `bindsyms` under [alsa-utils].

#### Notifications
Notifications are provided by [libnotify]. Any [libnotify] compatible notification daemon can be used for notifications. The most common are [notify-osd] and [dunst]. To disable notifications remove the `-n` option from the `bindsyms` in the example configuration below.

If you are using [dunst], you may optionally choose to use `dunstify` instead of `notify-send` by adding the `-y` option to the `bindsyms` in the example configuration below.

Expiration time of notifications can be changed using the `-e <time_in_milliseconds>` option. Default is 1500 ms.

### Guide
Clone this repository: `git clone https://github.com/hastinbe/i3-volume.git ~/i3-volume`

Edit the following example and append it to your ~/.config/i3/config:

```
## Volume control

# Path to volume control, without trailing slash
set $volumepath ~/i3-volume

# Command for the status line (used with -t, requires -u)
#   ie: i3blocks, i3status
set $statuscmd i3status

# Signal used to update the status line (used with -u, requires -t)
#   i3blocks uses SIGRTMIN+10 by default
#   i3status uses SIGUSR1 by default
set $statussig SIGUSR1

# Amount to increase/decrease volume as a percentage (used with -i, -d)
set $volumestep 5

# alsa-utils settings when not using pulseaudio-utils
#
# To configure a default card, see https://www.alsa-project.org/main/index.php/Asoundrc
#
# Card number to control. (used with -a and -c)
#   If not specified, i3-volume will let `amixer` use a default.
#   List cards: aplay -l
#set $alsacard 1

# Uncomment to use alsa-utils (append "-c $alsacard" without quotes to override default card)
#bindsym XF86AudioRaiseVolume exec $volumepath/volume -anp -i $volumestep -t $statuscmd -u $statussig
#bindsym XF86AudioLowerVolume exec $volumepath/volume -anp -d $volumestep -t $statuscmd -u $statussig
#bindsym XF86AudioMute        exec $volumepath/volume -amn -t $statuscmd -u $statussig

# pulseaudio-utils settings when not using alsa-utils
#
# Symbolic name for sink (numeric index not supported) (used with -s $sinkname)
#   Recommended: comment out this setting and omit the -s option to use default sink
#   List sink names: pacmd list-sinks | awk -F "[<>]" '/^\s+name: <.*>/{print $2}'
#set $sinkname alsa_output.pci-0000_00_1b.0.analog-stereo

# Using pulseaudio-utils (append "-s $sinkname" without quotes to override default sink)
bindsym XF86AudioRaiseVolume exec $volumepath/volume -np -i $volumestep -t $statuscmd -u $statussig
bindsym XF86AudioLowerVolume exec $volumepath/volume -np -d $volumestep -t $statuscmd -u $statussig
bindsym XF86AudioMute        exec $volumepath/volume -mn -t $statuscmd -u $statussig
```
Reload i3 configuration by pressing `mod+Shift+r`

## Usage
Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change (requires `-t $statuscmd` and `-u $statussig` to be set). When notifications are enabled (`-n` flag) a popup will display the volume level.

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
[dunst]: https://dunst-project.org
[i3wm]: https://i3wm.org
[libnotify]: https://developer.gnome.org/libnotify
[license]: https://www.gnu.org/licenses/gpl-2.0.en.html
[notify-osd]: https://launchpad.net/notify-osd
[pulseaudio-utils]: https://www.freedesktop.org/wiki/Software/PulseAudio/
