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
- **Indigo Accent** (#545CFA / #7B80FF): the one accent. Primary actions, focus rings, the selection outline.
- **Success Green** (#1D7A33 / #30D158): "Copied" feedback only.
- **Warning Amber** (#B35400 / #FF9F0A): "No text found" feedback only.
- **Danger Red** (#D70015 / #FF453A): destructive actions only (Reset, Delete captures).

Rules: one accent. Feedback colours never decorate. The cyan scan beam belongs to the app icon and the
menu bar blink; it does not appear in ordinary UI.

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
- **Selection overlay:** the still is dimmed (28 % light, 45 % dark), the selection is a one-point white outline
  with no shadow, glow or corner decoration. The size label is removed; the outline is the whole UI.
- **Result pill:** system window background at 94 % opacity, one line of text, a symbol in its semantic colour.
  Fades after 1.5 s, stays while hovered, a click dismisses it.
- **Empty states:** composed, not blank. History says what to do: "Press ⇧⌘2 and drag over any text."
- **Progress:** a short pulse while recognition runs longer than 0.3 s. No circular spinner.

## 5. Layout Principles

- Settings: one column, `settingsWidth` 560 pt, scrolling inside the window past 80 % of the screen.
- History: a single list with search in the toolbar; no sidebar.
- Welcome: three numbered steps, each with one symbol and one sentence.
- Spacing comes from the tokens in `Design.Space` (4, 8, 12, 16, 20, 24, 32 pt). Do not invent values.

## 6. Motion & Interaction

- Menu bar feedback: one blink for success, two for failure. Reduce Motion replaces it with a 150 ms fade.
- Overlay: no animation when it appears; it must be on screen within one frame of the shortcut.
- Result pill: 200 ms fade out. No slide, no bounce.
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

## 8. Known gaps (to decide, not yet changed)

- The result pill's "Reading…" uses a circular spinner. Banned above; replace with a pulse dot.
- The welcome title ends in "!". Remove the exclamation mark.
- README and DMG still show the old hero art wording in places; regenerate after the copy is final.
