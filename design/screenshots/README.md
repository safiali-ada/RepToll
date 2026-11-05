# App Store screenshots

Builds the six iPhone 6.9" App Store screenshots: a big caption at the top and the real screen inside a drawn iPhone frame, on black with a lime glow.

## Run

From the repo root:

```sh
swift design/screenshots/render.swift
```

You only need Xcode's `swift`; nothing else to install. It takes a few seconds.

Options:

- `--placeholders`: fill in any missing screen with a generated test image from `placeholders/`, so you can preview the layout before you have every capture.
- `--only 03`: render only the shots whose file name starts with `03`.
- `--config path/to/other.json`: use a different config file.

## Inputs

Put the screens in `raw/` using the names from `shots.json`:

| File | Source |
|---|---|
| `01-shield.png`, `02-camera.png` | your iPhone |
| `03-home.png` … `06-paywall.png` | Simulator (`xcrun simctl io booted screenshot design/screenshots/raw/03-home.png`) |

Any portrait iPhone capture works. Captures that aren't 1320×2868 are scaled to fill the screen, which can trim a few pixels off one edge. The Dynamic Island is drawn over the top of each screen, so captures without one look right.

If a screen is missing, that shot is skipped with a warning and the others still render.

## Captions and backgrounds

Edit `shots.json`. Each entry has:

- `file`: the input in `raw/`.
- `caption`: the headline. It goes on two balanced lines automatically. Put a `\n` in it to choose the break yourself, and it shrinks if a line is too wide.
- `highlight` (optional): text in the caption to colour lime, e.g. `"locked"`.
- `background` (optional): an image in `backgrounds/` (e.g. art made in Gemini). It replaces the default black and lime background, fills the canvas, and is darkened at the top so the caption stays readable.
- `output` (optional): output file name. By default it's the shot's position plus the input name, e.g. `03-home.png`.

## Output

`out/01-….png` to `out/06-….png`: 1320×2868, sRGB, no alpha channel, ready for App Store Connect. Check them with:

```sh
sips -g pixelWidth -g pixelHeight -g hasAlpha design/screenshots/out/*.png
```

Layout settings (caption size, device width, bezel, colours) are constants at the top of `render.swift`.
