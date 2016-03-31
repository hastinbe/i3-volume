i3-volume
=========
[![License](http://img.shields.io/:license-GPLv2-blue.svg)][license]

Volume control and volume notifications for [i3wm](http://i3wm.org)

## Installation

#### Requirements
* [i3wm](http://i3wm.org) - A better tiling and dynamic window manager
* [notify-osd](https://launchpad.net/notify-osd) - Canonical's on-screen-display notification agent
* [pulseaudio](http://pulseaudio.org) - Sound system for POSIX OSes. Typically provided by your OS distribution 

#### Conflicts
dunst will not work with i3-volume's notifications. If you wish to use notifications you must use notify-osd.

`Note:` The Ubuntu repository provided by sur5r for the stable i3 package will install dunst. The dunst daemon cannot be running for notifications to go to notify-osd! `killall -9 dunst` or remove dunst with `sudo apt-get remove dunst`

#### Guide
Clone this repository: `git clone https://github.com/hastinbe/i3-volume.git ~/i3-volume`

Edit the following example and append it to your ~/.config/i3/config:

```
## Volume control

# Path to volume control, without trailing slash
set $volumepath ~/i3-volume

# Command for the status line (used with -t, must also use -u)
#   ie: i3blocks, i3status
set $statuscmd i3status

# Signal used to update the status line (used with -u, must also use -t)
#   i3blocks uses SIGRTMIN+10 by default
#   i3status uses SIGUSR1 by default
set $statussig SIGUSR1

# Amount to increase/decrease volume as a percentage (used with -i, -d)
set $volumestep 5

# Symbolic name for sink (numeric index not supported) (used with -s $sinkname)
#   Recommended: comment out this setting and omit the -s option to use default sink
#   List sink names: pacmd list-sinks | awk -F "[<>]" '/^\s+name: <.*>/{print $2}' 
#set $sinkname alsa_output.pci-0000_00_1b.0.analog-stereo 

bindsym XF86AudioRaiseVolume exec $volumepath/volume -i $volumestep -n -t $statuscmd -u $statussig
bindsym XF86AudioLowerVolume exec $volumepath/volume -d $volumestep -n -t $statuscmd -u $statussig
bindsym XF86AudioMute exec $volumepath/volume -m -n -t $statuscmd -u $statussig
```
Reload i3 configuration by pressing `mod+Shift+r`

## Usage
Use your keyboard volume keys to increase, decrease, or mute your volume. If you have a volume indicator in your status line it will be updated to reflect the volume change (requires -t $statuscmd and -u $statussig to be set). When notifications are enabled (-n flag) a popup will display the volume level.

![Volume Notifications](https://github.com/hastinbe/i3-volume/blob/master/volume-notifications.png)

## License

i3-volume is released under [GNU General Public License v2][license]

Copyright (C) 1989, 1991 Free Software Foundation, Inc.

[license]: http://www.gnu.org/licenses/gpl-2.0.en.html

