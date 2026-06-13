# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-13

### Added
- Initial release of the Screen Margins KOReader plugin.
- Per-edge screen margin configuration: top, bottom, left, and right.
- Live black-frame preview before applying margin changes.
- Persistent viewport settings across KOReader restarts.
- Touch coordinate adjustment for offset viewports.
- Rotation-aware viewport reapplication.

### Changed
- Store plugin settings under namespaced `screenmargins_*` keys.
- Automatically migrate legacy `screen_original_size` and `screen_viewport` settings.
- Preserve any built-in KOReader/device viewport as a baseline on first install.

### Fixed
- Validate and clamp saved settings to avoid crashes from malformed configuration.
- Avoid duplicate touch translations by using a single mutable touch hook.
- Restore pending margin edits when cancelling or dismissing the configuration dialog.
- Prevent preview dialogs from being dismissed in a way that could leave the overlay stuck.

### Security
- Hardened loading of persisted settings by rejecting invalid, negative, non-numeric, or out-of-bounds viewport values.
