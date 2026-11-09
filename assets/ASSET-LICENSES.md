# Asset license report

This file lists every theming asset bundled with macOS-Lite and its license.
It is regenerated at release time with `find assets -type f -exec sha256sum {} +`.

## Fonts

| File | Source | License |
|------|--------|---------|
| fonts/Inter-*.ttf | https://github.com/rsms/inter | SIL Open Font License 1.1 |
| fonts/JetBrainsMono-*.ttf | https://github.com/JetBrains/JetBrainsMono | SIL Open Font License 1.1 |

## Icons

| File | Source | License |
|------|--------|---------|
| icons/papirus-* | https://github.com/PapirusDevelopmentTeam/papirus-icon-theme | CC0 / CC-BY-3.0 (mixed per-file) |
| icons/mlite-* | macOS-Lite project (original) | MIT |

## Wallpapers

| File | Source | License |
|------|--------|---------|
| wallpapers/* | macOS-Lite project (original) | CC0 1.0 |

## Explicitly NOT included (Apple IP)

- Apple SF Pro / San Francisco font
- Apple emoji and icon artwork
- macOS wallpapers
- The "" Apple logo

## Verification

```bash
find assets -type f -exec sha256sum {} + | sort > assets/ASSET-SHA256.txt
```
