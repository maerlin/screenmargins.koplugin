# Screen Margins Plugin

A KOReader plugin to configure screen margins for devices where part of the screen is physically covered by a bezel (e.g., the bottom edge sits behind a plastic frame).

## Features

- Configure margins per edge: top, bottom, left, right
- Live **preview** — a black frame overlay shows exactly where margins will be cut before you commit
- Settings persist across restarts
- Malformed saved settings are validated and reset instead of crashing KOReader
- Touch input coordinates are adjusted with a single mutable hook, avoiding duplicate translations
- Rotation-aware: margin settings survive orientation changes without being invalidated

## Installation

1. **Download the plugin**:
   - Download the `screenmargins.koplugin` directory (or zip archive if available)

2. **Extract to KOReader plugins directory**:

   The location depends on your device:

   - **Kindle/Kobo/Android**: `/koreader/plugins/`
   - **Linux**: `~/.config/koreader/plugins/`
   - **Windows**: `%APPDATA%/koreader/plugins/`
   - **macOS**: `~/Library/Application Support/koreader/plugins/`

   The plugin must be placed as `plugins/screenmargins.koplugin/` containing all plugin files.

3. **Restart KOReader** to load the plugin.

4. **Verify installation**: open the KOReader menu — you should see **Screen margins** listed.

## Usage

1. Go to **Menu → Screen margins → Configure margins**
2. Tap the edge you want to adjust (**Top**, **Bottom**, **Left**, or **Right**)
3. Use the spinner to set the number of pixels to trim from that edge, then tap **Set**
4. Repeat for any other edges
5. Tap **Preview** to see a black frame overlay showing exactly where the margins will fall — tap **Apply** to save, or **Cancel** to go back and adjust
6. Tap **Apply** directly (without previewing) to save and be prompted to restart

Changes take effect after restarting KOReader.

### Example

If your device has 12 pixels hidden behind the bottom bezel:

- Open **Configure margins**
- Tap **Bottom**, set the value to `12`, tap **Set**
- Tap **Preview** to confirm the margin looks right
- Tap **Apply** and restart KOReader

## Menu items

| Item | Description |
|---|---|
| **Configure margins** | Open the margin editor (Top / Bottom / Left / Right) |
| **Reset to full screen** | Clear all margins and restore the full screen viewport |
| **Show current settings** | Display current screen size, viewport coordinates, and margin values |

## How It Works

- The physical screen size is stored once in `G_reader_settings` as `screenmargins_original_size` and used as the reference for all margin calculations
- Margin values are converted to a viewport rectangle (`x`, `y`, `w`, `h`) stored as `screenmargins_viewport` (legacy `screen_original_size` / `screen_viewport` values are migrated automatically)
- On first install, any KOReader/device viewport already in effect is kept as a baseline so merely enabling the plugin does not alter the display
- On startup, the plugin applies the saved viewport via `Screen:setViewport()` and uses one mutable touch translation hook to keep input coordinates aligned without piling up duplicate hooks
- The preview overlay draws black bars directly onto the framebuffer at the margin positions without modifying the viewport, so no restart is needed to dismiss it

## Troubleshooting

- **Plugin not appearing**: ensure the directory is named exactly `screenmargins.koplugin` and both `main.lua` and `_meta.lua` are present
- **Margins not applying**: check KOReader's crash.log for errors; try **Reset to full screen** and reconfigure
- **Changed devices**: if the screen size is different, the stored `screenmargins_original_size` will be automatically updated on first load
- **Debug logs**: search for `ScreenMargins` in KOReader's log output (enable debug logging if needed)

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
