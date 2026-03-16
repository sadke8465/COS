# Dogear Manager — KOReader Plugin

A native, on-device interface for KOReader that lets you swap and resize your digital bookmark ("dogear") without ever needing a computer.

## Target Environment

- **Hardware**: Jailbroken Amazon Kindle 10th Generation
- **Software**: KOReader v2025.10

## Installation

1. Connect your Kindle to a computer via USB.
2. Copy the `dogearmanager.koplugin` folder into your KOReader plugins directory:
   ```
   /mnt/us/koreader/plugins/dogearmanager.koplugin/
   ```
3. (Optional) Create the custom designs folder and add your bookmark images:
   ```
   /mnt/us/koreader/icons/dogears/
   ```
   Supported formats: `.png`, `.svg`, `.bmp`, `.jpg`, `.jpeg`, `.alpha`
4. Restart KOReader.

## Usage

1. Open the top menu in KOReader.
2. Go to **Tools** → **Dogear Manager**.
3. Choose an option:
   - **Change Bookmark Design** — pick from any custom images you placed in the `icons/dogears/` folder.
   - **Adjust Bookmark Size** — enter a numeric multiplier (e.g., `2` for 2x larger, `0.5` for half size).
4. When prompted, tap **Restart** to apply changes.

## How It Works

The plugin saves two settings to KOReader's global configuration:

| Setting | Description |
|---|---|
| `dogear_custom_icon` | Full path to the selected custom dogear image |
| `dogear_scale_factor` | Numeric multiplier for the dogear size (default: 1) |

These settings are read by KOReader's `ReaderDogear` widget on startup. A KOReader restart is required after changes so the widget reinitializes with the new values.

## File Structure

```
dogearmanager.koplugin/
├── _meta.lua    # Plugin metadata (name, description)
└── main.lua     # Plugin logic (menus, scanning, settings)
```

## Adding Custom Designs

Place your custom bookmark image files in:
```
<koreader_data_dir>/icons/dogears/
```

On a Kindle, this is typically:
```
/mnt/us/koreader/icons/dogears/
```

The plugin scans this folder and displays all valid images in a selectable list.
