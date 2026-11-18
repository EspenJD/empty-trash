# Changelog

## 0.1.0 - 2026-11-18

First release.

- Lists the trash with sizes, item counts and the five biggest items of each folder.
- Empties only after `y` at a terminal. Without a terminal it only lists. No `--yes` option.
- macOS: `~/.Trash`, the iCloud Drive trash and the trash of each mounted disk.
- Linux: the FreeDesktop.org home trash and the trash of each mounted filesystem.
- Other machines through SSH, from the command line or from a hosts file. Nothing to install there.
- `--sudo` for root's trash and for items that only root can delete.
