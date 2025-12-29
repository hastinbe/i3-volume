# i3-volume Configuration Examples

This directory contains example configuration files for common setups.

## Available Examples

### Basic Examples

- **config.minimal** - Minimal configuration with basic notifications
- **config.dunst** - Configuration optimized for Dunst notifications
- **config.i3blocks** - Configuration for i3blocks integration

### Advanced Examples

- **config.advanced** - Full-featured configuration with all options
- **config.with-includes** - Example showing how to use config file includes

### Include Files

- **notifications.dunst** - Notification settings for Dunst (can be included)
- **volume-control.conf** - Volume control settings (can be included)

## Usage

1. Choose an example that matches your setup
2. Copy it to your config location:
   ```bash
   cp examples/config.dunst ~/.config/i3-volume/config
   ```
3. Customize the settings as needed
4. Validate your config:
   ```bash
   volume config validate
   ```
5. View your current config:
   ```bash
   volume config
   ```

## Config File Location

- `~/.config/i3-volume/config`
- `$XDG_CONFIG_HOME/i3-volume/config`

## Config File Includes

You can split your configuration into multiple files using includes:

```bash
# In your main config file
source notifications.dunst
source volume-control.conf
```

Include paths can be:
- Absolute: `source /path/to/file`
- Relative to config directory: `source notifications.dunst`
- Relative to current file: `source ./notifications.dunst`

## Getting Help

- View all configurable variables: `volume config docs`
- Show current configuration: `volume config`
- Validate config syntax: `volume config validate`

