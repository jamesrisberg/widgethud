# widgetHUD's MacHUD contract

widgetHUD implements the MacHUD contract through HUDKit. MacHUD reads
`widgetHUD.app/Contents/Resources/machud.json` without launching the app and talks to the running
app over a Unix socket. The shared parts (socket framing, the required verbs' requests, replies
and errors, `subscribe`, the settings schema format, the `widget` verb and its events, what
MacHUD sends and expects) are specified in HUDKit's
[docs/CONTRACT.md](../../hudkit/docs/CONTRACT.md) (§ Widgets for widgets); this page lists what
widgetHUD adds or does differently.

- Manifest: `Sources/widgetHUD/Resources/machud.json`: app `xyz.machud.widgethud`, socket
  `widgethud`, icon `square.grid.2x2`, three panels, all `kind: widget` and none in the dock
  (`HUDManifest.dockPanels` is empty). The app's settings schema is `settings.json`, named by
  the first panel.

  | Type | Symbol | Sizes | Default | `multiple` | `refresh` (s) | Instance schema |
  |---|---|---|---|---|---|---|
  | `clock` | `clock` | small, medium | small | yes | 1 | `clock.widget.json` |
  | `weather` | `cloud.sun` | small, medium, large | small | yes | 900 | `weather.widget.json` |
  | `calendar` | `calendar` | small, medium, large | medium | yes | 60 | `calendar.widget.json` |

- Widgets: `HUDWidgetHost` with the three types registered, set as `router.widgetHost` before
  the socket starts. Windows, levels, Spaces, locking, edit chrome and the `widget` verb are
  HUDKit's. widgetHUD keeps instances in memory only; MacHUD's `widget sync` after it connects
  restores them.
- Requires a MacHUD built on HUDKit 0.3 or later: an older one would read the widget panels as
  windowed apps.
- Socket: `~/Library/Application Support/MacHUD/sockets/widgethud.sock` (0600).
- CLI: `widgethud <command> [key=value ...]` (in `widgetHUD.app/Contents/Helpers/widgethud`, linked
  onto PATH by `install.sh`; grammar and exit codes in HUDKit's docs/CLI.md). Shorthands:
  `refresh`, `status`, `places <place>`; `widget <sub-verb>` passes through.

## Verbs

| Command | Args | Result |
|---|---|---|
| `hello` | | `{app, name, hudkit, version, panels, verbs}`: the three widget panels with their `widget` objects; `verbs` ends with `menu`, `menu-invoke`, `widget` |
| `state` | | `{panels: []}`: no dock panels |
| `subscribe` | `events=state,widget` (optional) | `state` events on settings changes; `widget` events (below) |
| `panel ...` | | `no such panel`: widgets are placed with `widget`, never `panel` |
| `widget create\|update\|remove\|list\|sync\|edit\|reveal\|schema` | as in HUDKit's CONTRACT.md § Widgets | instance settings are checked by the type's schema |
| `settings get` | `key=` (optional) | `{settings: {temperatureUnit, timeFormat, menuBar.consumed}}` |
| `settings set` | `key=value ...` | validates every value before applying any |
| `settings schema` | | `{schema}` from `settings.json` |
| `action refresh` | | fetches every shown place's weather and reloads the calendars now. `{weather: <weather widgets tracked>, calendar: <access>}` |
| `action places` | `query=<place>` | Open-Meteo's matches: `{query, best, places: [{name, latitude, longitude, timeZone}]}`; `best` is what a weather widget with that place would show |
| `action status` | | `{instances, editing, revealed, weather: {sample, places: [{place, fetchedAt?, error?, loading}], lookups: [{text, found} or {text, state, error?, retryAt?}], instances}, calendar: {access, events, loadedAt?, sample, active, widgets}, settings}` |
| `menu` / `menu-invoke` | `id=` (and optional `title=`) for `menu-invoke` | the status menu, so MacHUD can host it |
| `quit` | | replies, then quits (the socket file is removed) |
| `help` | | lists the registered commands |

### Widget events widgetHUD sends

Besides HUDKit's edit-mode events (`frame`, `size`, `remove`, `configure`):

| `change` | When |
|---|---|
| `configure` | the weather widget's "Set a place" / "Change…" button: please show this instance's settings |
| `settings` | a weather widget looked its place up: `settings` carries the instance's settings with the coordinates added (below); MacHUD persists them |

## Widget settings

Per instance, checked by the type's schema (`widget schema type=`):

| Type | Key | Type | Default | Meaning |
|---|---|---|---|---|
| clock | `timeZone` | string | `""` | a zone id (`Europe/Oslo`), a city (`Oslo`, `new york`) or an abbreviation (`UTC`); empty follows this Mac; anything else shows "Unknown time zone" |
| clock | `label` | string | `""` | above the time; empty shows the zone's city |
| clock | `style` | enum `auto`, `analog`, `digital` | `auto` | `auto`: analog when small, digital with the date when medium |
| clock | `timeFormat` | enum `app`, `12h`, `24h` | `app` | `app` uses the app's `timeFormat` |
| clock | `seconds` | bool | `false` | |
| weather | `place` | string | `""` | free text; a region or country after a comma picks among namesakes (`Portland, Maine`) |
| weather | `units` | enum `app`, `celsius`, `fahrenheit` | `app` | |
| weather | `showHourly` | bool | `true` | the next five hours (medium, large) |
| weather | `showDaily` | bool | `true` | the next five days (large; medium when hourly is off) |
| calendar | `calendars` | string | `""` | calendar names separated by commas, any case; empty is every calendar |
| calendar | `daysAhead` | int 1-14 | `3` | how far ahead every size looks |
| calendar | `timeFormat` | enum `app`, `12h`, `24h` | `app` | |

Weather widgets also keep, in the same settings, keys the schema does not list (so MacHUD's
settings form does not show them): `latitude`, `longitude`, `resolvedPlace` (the `place` text
they were found for) and `resolvedName` (`Portland, Maine, United States`). widgetHUD writes them
with `HUDWidgetContext.updateSettings` after a lookup, which reports `change: settings`, once
per instance and place text. A place text is looked up once (case, commas and spacing aside)
however many widgets show it, and remembered in memory and in the cache file. When `place` no
longer matches `resolvedPlace`, or the coordinates are missing or invalid, the remembered place
is used, or the text is looked up if it is new; an instance whose settings come back without
the coordinates (a settings form that replaces them) keeps showing the weather and is not
written to again for the same text.

## Data

- Weather: `https://api.open-meteo.com/v1/forecast` (current, 24 hourly, 6 daily values, the
  place's time zone, Celsius) and `https://geocoding-api.open-meteo.com/v1/search` for places.
  Place names are asked for in this Mac's language. One forecast request per place every 15
  minutes while a widget shows it (instances at the same place, to two decimals of a degree,
  share it); after a failure, a retry after 2 minutes. A failed place lookup is retried after a
  minute, doubling up to 30 minutes; a name with no match, or with coordinates out of range,
  shows "No place called …". `<home>/weather-cache.json` keeps the last forecast per place and
  the places looked up; forecasts are shown at launch and offline, with their age once 45
  minutes old, and a forecast without today in it (cached on an earlier day) is shown as out of
  date instead. Forecasts and places no widget shows any more leave the cache when their last
  widget goes.
- Calendar: EventKit, full access (`NSCalendarsFullAccessUsageDescription`; the
  `com.apple.security.personal-information.calendars` entitlement for the hardened runtime).
  Access is requested when the first calendar widget appears, never at launch. While at least
  one calendar widget is shown, the next 15 days of every calendar are read on a serial
  background queue (a burst of changes loads once; only the newest load is kept) and reloaded
  on `EKEventStoreChanged`, at midnight, after wake and every 5 minutes, and the access is
  re-read every minute, so a grant made in System Settings shows within a minute. With no
  calendar widget left, all of that stops. Each instance filters by its `calendars` and
  `daysAhead`. Without access the widget says why, with a button: Allow… (the system prompt)
  before the user was asked, Open Settings… (Privacy & Security › Calendars) after a refusal.
- Clocks follow this Mac's time zone as it changes. Times use the 12- or 24-hour setting with
  the locale's AM/PM words; "today", "tomorrow", weekdays and dates are in the locale's
  language (widgetHUD's own words are English).

## Settings

| Key | Type | Default |
|---|---|---|
| `temperatureUnit` | enum `auto`, `celsius`, `fahrenheit` | `auto`: the explicit Celsius/Fahrenheit choice in System Settings, else Fahrenheit for the US measurement system |
| `timeFormat` | enum `auto`, `12h`, `24h` | `auto`: the region's hour format |
| `menuBar.consumed` | bool | `true`: hide the menu bar icon while MacHUD hosts the menu (served by HUDKit) |

Stored in `<home>/preferences.json` (`menuBar.consumed` in `<home>/menubar.json`), where home is
`~/Library/Application Support/widgetHUD` or `$WIDGETHUD_HOME`. Saved values are merged over
the defaults key by key.

## Menu bar consolidation

While MacHUD runs it shows widgetHUD's status menu inside its own (`menu`, `menu-invoke`) and the
menu bar icon hides (`HUDStatusItemPolicy`); the icon comes back when MacHUD quits or the user
turns `menuBar.consumed` off. Items: the number of widgets placed, Refresh Weather and
Calendars, Calendar Access…, Quit widgetHUD. widgetHUD has no text input, so no Edit menu.

## Environment

| Variable | Read by | Effect |
|---|---|---|
| `WIDGETHUD_HOME` | app | base directory for everything the app writes |
| `WIDGETHUD_SOCKET` | app, CLI | socket name instead of `widgethud` |
| `WIDGETHUD_NO_HOTKEYS` | | accepted; widgetHUD registers no global hotkeys |
| `WIDGETHUD_SAMPLE_DATA` | app | `1`: sample weather and events, no network and no Calendar access asked |

## Launch flags

| Flag | Effect |
|---|---|
| `--snapshot <path.png>` | renders every type at every size, and the no-place, no-access and world-clock states, with sample data to `<stem>-<name>.png`, writes a contact sheet of them to `<path.png>`, prints the paths and quits |
| `--snapshot <path.png> --type <type> [--size <size>]` | one widget to `<path.png>` (size default: the type's `defaultSize`) |
| `--editing` | with `--snapshot`: draw HUDKit's edit controls |

## Compliance

HUDKit's compliance checklist passes except its panel checks (`state` lists a panel, `panel
show/hide`, hover show/hide, `panel frame`), which assume a dock panel; widgetHUD has none and
answers `no such panel`. The widget block passes for each of `clock`, `weather` and `calendar`.
