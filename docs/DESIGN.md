# Design System: Nictate

## 1. Visual Theme & Atmosphere

A quiet menu bar utility that feels like part of macOS, not a guest in it. Density is airy (4 of 10):
a single calm window, one question per screen, one accent colour. Layout is left-aligned and ordinary on
purpose: the interesting part happens on the screen the user is reading, not in Nictate's chrome. Motion is
restrained: the menu bar eyelid closes once, cleanly, and the selection appears without a bounce.

Native platform rules apply. Typography is the system font (SF Pro), colour follows the system appearance,
and every surface honours Reduce Transparency, Reduce Motion and Increase Contrast.

## 2. Colour Palette & Roles

Light and Dark values are defined in `Sources/Nictate/ColorTokens.swift`.

- **Charcoal Ink** (#0B0B12 / #F5F5F7): primary text. Off-black, never `#000000`.
- **Muted Steel** (#636366 / #98989D): secondary text, metadata, captions. Contrast checked at 4.5:1 or better.
- **Hairline** (black 12% / white 12%): structural separators only.
- **Indigo Accent** (#545CFA / #7B80FF): the one accent. Primary actions and focus rings.
- **Success Green** (#1D7A33 / #30D158): "Copied" feedback only.
- **Warning Amber** (#B35400 / #FF9F0A): capture problems only: "No text found" (question mark), and
  "Couldn't read this area" and "Couldn't copy text" (warning triangle).
- **Danger Red** (#D70015 / #FF453A): destructive actions only (Reset, Delete captures).

Rules: one accent. Feedback colours never decorate. The cyan scan beam belongs to the app icon and the
menu bar blink; it does not appear in ordinary UI. The capture scan line is white and black, never the cyan beam.

## 3. Typography Rules

- **Titles and labels:** SF Pro (system). Hierarchy through weight and size, not through colour.
- **Body and captions:** SF Pro at system sizes; captions use Muted Steel. Never below 11 pt.
- **Numbers and shortcuts:** SF Mono, so that ⇧⌘2 and counts align.
- **Banned:** Inter, serif faces in any Nictate screen, custom display faces in the app. Marketing images
  (README, DMG) may use the system font only.

## 4. Component Stylings

- **Buttons:** system button styles. One prominent action per sheet, with Return bound to the safe choice.
  Destructive buttons use the danger role and have no keyboard default.
- **Alerts:** Cancel is the default. A destructive alert never sits on Return.
- **Settings rows:** grouped `Form` sections, label on the left, control on the right. No cards.
- **Selection overlay:** the still is dimmed (28 % Light, 45 % Dark). The edge is a pair of bands on whole device
  pixels: 1 pt white at 90 % inside, 1 pt black at 35 % outside. Four corner marks, 12 pt arms (at most a third of
  the shorter side), thicken each band by 1 pt. Increase Contrast: 2 pt white at 100 %, black at 80 %. No shadow,
  glow, handles or size label. (Corner marks approved 2026-10-13; this replaces the earlier rule against corner
  decoration.)
- **Result pill:** HUD material (opaque under Reduce Transparency), 14 pt corners, one line of 13 pt medium text and
  a 15 pt semibold symbol: check for copied, question mark for nothing found, warning triangle for a read or copy
  failure. Fades in and out in 200 ms (instant under Reduce Motion), stays 1.5 s or while hovered, a click dismisses
  it. "Copied" appears only after the clipboard read-back.
- **Empty states:** composed, not blank. History says what to do: "Press ⇧⌘2 and drag over any text."
- **Progress:** past 0.3 s of recognition, the menu bar icon pulses, the Reading pill appears, and a 2 pt
  white-and-black line sweeps the selected area top to bottom. Under Reduce Motion the icon rests dimmed, the dot is
  still and the line is not shown. No circular spinner.

## 5. Layout Principles

- Settings: one column, `settingsWidth` 560 pt, scrolling inside the window past 80 % of the screen.
- History: a single list with search in the toolbar; no sidebar.
- Welcome: three numbered steps, each with one symbol and one sentence.
- Spacing comes from the tokens in `Design.Space` (4, 8, 12, 16, 20, 24, 32 pt). Do not invent values.

## 6. Motion & Interaction

- Menu bar feedback: one blink for success, two for failure. Reduce Motion replaces it with a 150 ms fade.
- Overlay: no animation when it appears; it must be on screen within one frame of the shortcut.
- Scan line: 1.2 s sweep, ease in-out, fading in and out over the first and last 15 %; removed the moment
  recognition ends.
- Result pill: 200 ms fade in and out. No slide, no bounce.
- Animate opacity and transform only.

## 7. Anti-Patterns (Banned)

- Emoji in any app screen. (The DMG and README carry the one exception: the flag, which is a brand asset.)
- Pure black, neon or outer glows, purple-to-blue gradient text.
- Circular spinners, scroll chevrons, "Scroll to explore", "Get started now!".
- Cards with decorative shadows in Settings; floating labels in forms.
- Generic placeholder names ("John", "Acme") in screenshots. Use realistic text.
- Marketing copy in the app: "Elevate", "Seamless", "Unleash". The app says what it does.
- A second accent colour, or any hue used for decoration rather than meaning.
- Custom mouse cursors. The crosshair is the system crosshair.
