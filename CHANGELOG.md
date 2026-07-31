# Changelog

## [1.1.0] - 2026-07-27

### Added
- **Code label**: an optional caption above the barcode/QR panel, so it is clear whether the code is a race bib, an insurance number or a link to an online health profile. The alternate code field already accepted URLs, and this makes that usable in practice, and the field description now mentions it (all 20 languages).
- Fallback panels now explain themselves. When a value cannot be drawn as a barcode the app says why ("too long for bars, use QR", or "code too long for QR") instead of silently showing plain text, which read as a broken app.

### Fixed
- **Data entered but not shown**: filling in only medications, height/weight or the alternate code left the app on the "no ICE data configured" screen and the data was never displayed.
- **Organ donor status was always English** ("Yes"/"No") on every watch, even though translations existed in all 20 languages.
- **Code 39 geometry**: the wide/narrow bar ratio could render inconsistently, breaking the ratio a scanner decodes on. Code 39 now also refuses to draw bars too thin to be scanned, showing the readable value instead of a barcode that only looks real.
- **Rendering cost**: the barcode was fully redrawn on every frame even while scrolled far off screen (up to ~1100 draw calls per frame for a large QR).
- A failed render could retry itself in an unbounded loop, pinning the CPU and leaving the widget stuck.
- Long unbroken words (medication or allergen names) were clipped at the screen edge instead of wrapping.
- The glance loaded the entire data model, including three 512-character fields, to display only a blood type.
- Impossible dates such as `1990-02-31` were accepted.
- The barcode value in the fallback panel could overflow its panel; it now scales to fit.

## [1.0.0] - 2026-07-26: First public release

**SafeRunner ICE Wallet** by SkapaCraft: emergency medical information (ICE) stored directly on your Garmin watch.

### Features
- ICE info screen: blood type, name, age/date of birth, height/weight, national ID, emergency contacts (name + relationship + phone), medications, allergies, medical conditions, organ donor status
- Scannable barcode (QR or Code 39) generated from your National ID or a custom alternate code, with automatic backlight while visible
- The alternate code accepts anything you want encoded, such as an insurance number, a race bib, or a link to an online health profile (e.g. MedicAlert), with an optional caption shown above the code so it is clear what it refers to
- Fully scrollable single-screen layout, high-contrast display for fast reading in an emergency
- 20 languages, auto-selected from the watch's system language: EN, IT, DE, FR, ES, PT, NL, PL, SV, NO, DA, FI, RU, JA, KO, ZH-S, ZH-T, TR, CS, HU
- All fields optional and configured via Garmin Connect Mobile: nothing is required to install and use the app
- 100% offline: no network requests, no data collection, no analytics: see [README](README.md#privacy) for details

### Compatibility
- QR code: renders reliably on all supported devices: **recommended format**
- Code 39 barcode: needs a lot of horizontal space, so it only renders when the bars come out wide enough to actually be scanned. With a long value (e.g. a 16-character Codice Fiscale) that is not achievable on most watch screens, and the app shows the value as large readable text instead of an unscannable barcode. Shorter values on larger displays do render as bars.
