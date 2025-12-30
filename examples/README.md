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

### Plugin Examples

- **plugin.example** - Template for creating custom notification plugins
- **plugin.output.example** - Template for creating custom output format plugins

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

## Custom Plugins

i3-volume supports plugins for extending functionality. Currently supported plugin types are notifications and output formats.

### Notification Plugins

Create custom notification methods by creating plugin scripts:

1. Create the plugin directory (if it doesn't exist):
   ```bash
   mkdir -p ~/.config/i3-volume/plugins/notify
   ```

2. Copy the example plugin:
   ```bash
   cp examples/plugin.example ~/.config/i3-volume/plugins/notify/myplugin
   chmod +x ~/.config/i3-volume/plugins/notify/myplugin
   ```

3. Edit the plugin to implement your custom notification method

4. Use it with the `-N` option:
   ```bash
   volume -N myplugin up 5
   ```

5. List all available notification methods (including plugins):
   ```bash
   volume notifications
   ```

### Output Format Plugins

Create custom output formats by creating plugin scripts:

1. Create the plugin directory (if it doesn't exist):
   ```bash
   mkdir -p ~/.config/i3-volume/plugins/output
   ```

2. Copy the example plugin:
   ```bash
   cp examples/plugin.output.example ~/.config/i3-volume/plugins/output/myformat
   chmod +x ~/.config/i3-volume/plugins/output/myformat
   ```

3. Edit the plugin to implement your custom output format

4. Use it with the `output` command:
   ```bash
   volume output myformat
   ```

5. List all available output formats (including plugins):
   ```bash
   volume outputs
   ```

### Plugin Directory Structure

Plugins are organized by type in subdirectories:
- `~/.config/i3-volume/plugins/notify/` - Notification plugins
- `~/.config/i3-volume/plugins/output/` - Output format plugins

See the main README for more details on the plugin system.

## Getting Help

- View all configurable variables: `volume config docs`
- Show current configuration: `volume config`
- Validate config syntax: `volume config validate`

