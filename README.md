# Dogear Manager — KOReader Plugin

Change the dogear (the folded-corner bookmark) in KOReader without touching a config file. Swap the image, scale it up or down, and nudge its position — all from a menu while reading.

## Requirements

- Jailbroken Amazon Kindle (tested on 10th gen)
- KOReader v2025.10+

## Installation

1. Connect your Kindle via USB.
2. Drop the `dogearmanager.koplugin` folder into your KOReader plugins directory:
   ```
   /mnt/us/koreader/plugins/dogearmanager.koplugin/
   ```
3. Restart KOReader.

That's it. The plugin shows up under **Tools → Dogear Manager**.

## Usage

Open a book, go to **Tools → Dogear Manager**. You'll see three options:

### Change Bookmark Design

Shows a scrollable list of all image files found in the custom icons folders. Tap one to switch to it immediately — no restart needed. There's also a "Reset to Default" entry at the bottom to go back to KOReader's built-in dogear.

### Adjust Bookmark Size & Margins

A dialog with:
- **Live corner preview** — a scaled-down representation of the top-right corner so you can see the result before applying.
- **Design picker** — arrow buttons to cycle through available icons.
- **Size** — scale from 0.5× to 4.0×, adjusted in 0.1 steps (or 0.5 with the double buttons).
- **Position** — top and right margin in discrete steps (0–20). Right steps are physically larger than top steps (ratio ~1.85×) to account for screen aspect ratio.

Hit **Apply** to save and update the dogear live. **Reset** clears all custom settings at once.

### Reset to Original Dogear

Clears the custom icon, scale, and margin settings in one tap. The dogear reverts to KOReader's default immediately.

## Adding Custom Designs

Place image files in either location:

**Bundled with the plugin** (applies to everyone using this plugin copy):
```
dogearmanager.koplugin/icons/
```

**User-specific** (won't be overwritten if you update the plugin):
```
/mnt/us/koreader/icons/dogears/
```

Supported formats: `.png`, `.svg`, `.bmp`, `.jpg`, `.jpeg`, `.alpha`

Files from both folders are merged into a single sorted list. If two files share the same filename, the plugin-bundled one takes precedence.

## Settings

The plugin stores its settings in KOReader's global config (`G_reader_settings`):

| Key | Description |
|---|---|
| `dogear_custom_icon` | Full path to the selected icon file |
| `dogear_custom_icon_name` | Filename of the selected icon (for display) |
| `dogear_scale_factor` | Size multiplier, default `1` |
| `dogear_margin_top` | Top margin in steps (each step ≈ `screen_min / 128` px) |
| `dogear_margin_right` | Right margin in steps (each step ≈ `1.85 × top_step` px) |

## File Structure

```
dogearmanager.koplugin/
├── _meta.lua    # Plugin name and description
├── main.lua     # All plugin logic
└── icons/       # Optional: bundle your own dogear designs here
```
