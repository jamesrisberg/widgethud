# widgetHUD

MacHUD's own desktop widgets: a clock and the weather, on HUD glass. macOS 14+.

## What it is

widgetHUD is a menu bar app (no Dock icon) that serves two widget types to MacHUD: **clock**
and **weather**. It has no dock panel of its own: MacHUD places the widgets on the
desktop, under your windows, raises them with its reveal (Control-Option-W), floats any of them
above windows, and lets you move, resize, configure and remove them in its edit mode. Each type
can be placed several times, each with its own settings: a row of world clocks, the weather at
home and where you are going. Calendar widgets are provided by [calHUD](../calhud).

| Widget | Small | Medium | Large |
|---|---|---|---|
| Clock | analog face (or digital) | digital time with the date (or analog) | |
| Weather | now, condition, high and low | + the next five hours | + the next five days |

Weather comes from [Open-Meteo](https://open-meteo.com) (no account or key).

## Install

Check out HUDKit (the shared kit and build scripts) next to this repo, then install:

```sh
ls ~/dev            # hudkit  widgethud
~/dev/widgethud/install.sh
```

`install.sh` builds a release, quits a running copy, installs `/Applications/widgetHUD.app`, links
the `widgethud` command onto your PATH and launches it. Widgets need a MacHUD built on HUDKit 0.3
or later (one that knows the `widget` panel kind).

## Use

Add widgets from MacHUD (its Widgets menu and edit mode); MacHUD keeps them, and gives them back
to widgetHUD whenever it starts. widgetHUD itself has no hotkeys and no window.

- **Clock**: set a time zone (a city such as `Tokyo` or `New York`, a zone such as
  `Europe/Oslo`, or `UTC`) for a world clock; empty follows this Mac. A label, 12- or 24-hour,
  seconds, and the analog or digital face are per clock.
- **Weather**: set a place. A new weather widget says "Set a place" and its Choose… button opens
  the widget's settings in MacHUD. Add a region or country after a comma to pick among
  namesakes (`Portland, Maine`). widgetHUD looks each place up once and remembers where it is;
  the forecast refreshes every 15 minutes and is kept on disk, so a widget shows the last
  forecast at launch and while offline (with its age).


The menu bar icon's menu shows how many widgets are placed and has Refresh Weather and Quit; while MacHUD runs the icon hides and MacHUD shows this
menu in its own (turn `menuBar.consumed` off to keep the icon). widgetHUD takes no drops.

## MacHUD contract

A widget-only app: panels `clock` and `weather`, all `kind: widget`; socket
`widgethud`. Verbs: the HUDKit set (`hello`, `state`, `subscribe`, `settings get|set|schema`,
`action`, `menu`, `quit`), `widget create|update|remove|list|sync|edit|reveal|schema`, and the
actions `refresh`, `places` and `status`. Full reference: [docs/CONTRACT.md](docs/CONTRACT.md).

```sh
widgethud hello
widgethud widget create instance=tokyo type=clock frame=40,40,170,170 'settings={"timeZone":"Tokyo"}'
widgethud widget create instance=home type=weather size=medium 'settings={"place":"Portland, Maine"}'
widgethud widget edit on
widgethud widget list
widgethud places Portland, Maine
widgethud status
widgethud quit
```

## Settings

App-wide (MacHUD's settings window, or `widgethud settings set key=value`):

| Key | Type | Default | |
|---|---|---|---|
| `temperatureUnit` | enum `auto`, `celsius`, `fahrenheit` | `auto` | `auto` follows this Mac's region and temperature setting |
| `timeFormat` | enum `auto`, `12h`, `24h` | `auto` | clock and forecast times |
| `menuBar.consumed` | bool | `true` | hide the menu bar icon while MacHUD hosts the menu |

Per widget (MacHUD's widget settings; an instance setting of "widgetHUD's setting" uses the
app-wide one):

| Widget | Key | Type | Default |
|---|---|---|---|
| clock | `timeZone` | string | empty (this Mac) |
| clock | `label` | string | empty (the zone's city) |
| clock | `style` | enum `auto`, `analog`, `digital` | `auto` |
| clock | `timeFormat` | enum `app`, `12h`, `24h` | `app` |
| clock | `seconds` | bool | `false` |
| weather | `place` | string | empty ("Set a place") |
| weather | `units` | enum `app`, `celsius`, `fahrenheit` | `app` |
| weather | `showHourly` | bool | `true` |
| weather | `showDaily` | bool | `true` |

App settings are stored in `~/Library/Application Support/widgetHUD/preferences.json`, the
weather cache in `weather-cache.json` beside it. Widget settings are MacHUD's.

## Build from source

Needs Swift 5.9+ and HUDKit checked out next to this repo (`../hudkit`).

```sh
swift test          # widgetHUDKitTests + widgetHUDTests
./build.sh          # build/widgetHUD.app (release; ./build.sh debug for a debug build)
./install.sh        # build, install to /Applications, link the CLI, launch
build/widgetHUD.app/Contents/MacOS/widgetHUD --snapshot /tmp/widgethud.png   # every widget, sample data
```

`--snapshot` renders every widget at every size (and the states before a widget has data) with
sample weather, to `/tmp/widgethud-<widget>-<size>.png`, plus a contact sheet at the
path given; `--type <widget> --size <size>` renders one; `--editing` draws the edit controls.

With MacHUD running, `./build.sh` announces the new bundle to it (`HUD_NO_ANNOUNCE=1` skips).
`build.sh` and `install.sh` call HUDKit's shared `scripts/hud-build.sh` and `scripts/hud-install.sh`
(set `HUDKIT_DIR` if HUDKit lives elsewhere); `widgetHUD.entitlements` contains no Calendar permission. The version comes from [VERSION](VERSION); changes are in
[CHANGELOG.md](CHANGELOG.md).

The app and menu bar icons (`AppIcon.icns`, `MenuBarIcon.png`, `MenuBarIcon@2x.png` in
`Sources/widgetHUD/Resources`) are HUDKit's placeholder. Draw the app's glyph in
`../hudkit/Icons/widgethud.svg` (see its README) and run `../hudkit/scripts/hud-icon.sh widgethud .`

## Isolation env vars for testing

| Variable | Effect |
|---|---|
| `WIDGETHUD_HOME` | base directory for everything widgetHUD writes (default `~/Library/Application Support/widgetHUD`) |
| `WIDGETHUD_SOCKET` | socket name (default `widgethud`); the CLI honours it too |
| `WIDGETHUD_NO_HOTKEYS` | accepted for the family convention; widgetHUD registers no hotkeys |
| `WIDGETHUD_SAMPLE_DATA` | sample weather without network access |

```sh
export WIDGETHUD_HOME=$(mktemp -d) WIDGETHUD_SOCKET=widgethud-test WIDGETHUD_NO_HOTKEYS=1 HUD_NO_ANNOUNCE=1 WIDGETHUD_SAMPLE_DATA=1
build/widgetHUD.app/Contents/MacOS/widgetHUD &
build/widgetHUD.app/Contents/Helpers/widgethud widget create instance=a type=weather frame=40,40,356,170
build/widgetHUD.app/Contents/Helpers/widgethud quit
```

## License

MIT, see [LICENSE](LICENSE).
