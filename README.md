# Screen Margins Plugin

A simple plugin to configure screen margins/viewport for devices where part of the screen is covered by bezels (e.g., bottom part cut off behind screen bezel).

## Features

- Configure screen viewport (x, y, width, height) through a simple UI
- Adjust margins to account for bezels that cover part of the screen
- Settings persist across restarts
- Works with all device types

## Installation

1. **Download the plugin**:
   - Download the `screenmargins.koplugin` directory (or zip archive if available)

2. **Extract to KOReader plugins directory**:

   The location depends on your device:

   - **Kindle/Kobo/Android**: Extract to `/koreader/plugins/`
   - **Linux**: Extract to `~/.config/koreader/plugins/`
   - **Windows**: Extract to `%APPDATA%/koreader/plugins/`
   - **macOS**: Extract to `~/Library/Application Support/koreader/plugins/`

   The plugin should be placed as `plugins/screenmargins.koplugin/` containing all plugin files.

3. **Restart KOReader**: Close and reopen KOReader to load the plugin

4. **Verify installation**:
   - Open KOReader's menu
   - You should see **Screen margins** in the menu

## Usage

1. Open KOReader
2. Go to **Menu** → **Screen margins** → **Configure margins**
3. Adjust the four parameters:
   - **X offset (left margin)**: Horizontal offset from left edge
   - **Y offset (top margin)**: Vertical offset from top edge  
   - **Width**: Width of usable screen area
   - **Height**: Height of usable screen area

4. The viewport is applied immediately
5. Settings are saved automatically

### Example

If your device has 10 pixels cut off at the bottom:
- Set **Height** to `screen_height - 10`
- Keep **X offset** and **Y offset** at `0`
- Set **Width** to full screen width

## How It Works

- The plugin stores viewport settings in `G_reader_settings` as `screen_viewport`
- The original screen size is stored once as `screen_original_size` to serve as a reference
- The plugin applies the viewport when it loads
- Touch input coordinates are automatically adjusted for the viewport offset
- A restart is recommended after changing margins to ensure proper initialization

## Troubleshooting

### Installation Issues
- Ensure the directory is named exactly `screenmargins.koplugin`
- Verify all `.lua` files are present in the plugin directory (`main.lua` and `_meta.lua`)
- Check that you have write permissions to the plugins directory
- If the plugin doesn't appear, check KOReader's crash.log for errors

### Usage Issues
- Check the logs for "ScreenMargins" messages (enable debug logging if needed)
- You can reset to full screen via **Menu** → **Screen margins** → **Reset to full screen**
- If margins don't seem to apply, try restarting KOReader
- The original screen size is stored on first load - if you change devices, you may need to clear the `screen_original_size` setting
