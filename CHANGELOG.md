# Changelog

All notable changes to widgetHUD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/); the current version is in [VERSION](VERSION).

## [Unreleased]

## [0.3.1] - 2026-10-13

### Changed
- The widgets' frosted backdrop is now the Mac's own blur of what is behind it under a light
  tint, the same as the rest of the MacHUD family.

### Fixed
- Widgets are already frosted when a desktop switch lands, instead of showing opaque for a
  moment first.
- Desktop widgets no longer go missing from a desktop. After a desktop switch, sleep and wake,
  or a display change, a widget the system dropped comes back within a second or two.
- Switching desktops or waking the Mac no longer resets every widget in the middle of the
  switch.

## [0.3.0] - 2026-10-02

### Added
- Desktop widgets for MacHUD: a clock (small analog, medium digital with the date; any time
  zone, so several make a world clock), the weather (small, medium with the next hours, large
  with the next five days) and your calendar (small with the next event, medium with the next
  three, large with an agenda). Place each as often as you like, each with its own settings.
- Weather from Open-Meteo, no account needed: type a place ("Portland, Maine"), refreshed every
  15 minutes, and the last forecast stays on screen while you are offline.
- The calendar reads your calendars after you allow it, and says what to do when it cannot.
- App-wide temperature unit and 12/24-hour defaults, following your Mac's region.
- `widgethud` CLI with `refresh`, `places`, `status` and the `widget` commands;
  `--snapshot` renders every widget with sample data; `WIDGETHUD_SAMPLE_DATA` for demos and
  tests.
- Menu bar consolidation: MacHUD hosts widgetHUD's menu.
