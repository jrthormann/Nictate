<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.png">
  <img src="docs/images/hero-light.png" alt="Nictate. Copy the text you can see. The app frames four lines of a note; the menu offers the color and the link it found, and a notification says Text copied.">
</picture>

<p align="center">
  Free and open source. For macOS 14 and later.
  <br>
  <a href="../../releases/latest">Download&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#build-from-source">Build from source&nbsp;&rsaquo;</a>
  <br><br>
  Made in the Dominican Republic <img src="docs/images/flag-do.svg" width="16" height="16" alt="" align="absmiddle">, fueled by Coke Zero and pizza.
  <br><br>
  English&nbsp;·&nbsp;<a href="docs/i18n/README.es.md">Español</a>
</p>

<br>

## Select. Copy. Carry on.

Your screen is full of text you can't copy. Nictate fixes that.

Press <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> and drag over any text on your screen: a web page,
a photo of a whiteboard, a paused video, a slide someone is sharing. For a region, recognition takes a fraction
of a second, and the text lands on your clipboard.

Recognition runs on your Mac with Apple's Vision framework, in every language Vision supports. Nothing is uploaded.
Your other problems are unfortunately outside the scope of this project.

<br>

## Pixel by pixel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/bento-dark.png">
  <img src="docs/images/bento-light.png" alt="Select. It's copied. Pixel by pixel. Colors, links, codes. Never leaves your Mac.">
</picture>

<br>
<br>

Selections snap to whole screen pixels, so each edge lands on a pixel boundary. Arrow keys move the corner one
pixel at a time, and Shift with an arrow moves it ten. The behavior matches the system screenshot tool.

<br>

## It knows what it is reading.

Nictate tells code, tables, lists and prose apart, and keeps each one the way it was written. Code keeps every
line break and its indentation. Tables come out with tabs between the cells, ready for a spreadsheet. Only
ordinary prose is joined into paragraphs, so a list never turns into a sentence.

Colors, links, emails and phone numbers in the last capture are one click away in the menu. QR codes and
barcodes copy their content. A link inside one is copied, or opened only after you confirm its address, as you choose.

<br>

## Keys

| Keys | What it does |
|:--|:--|
| <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Select an area and copy its text. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Cycle through recent captures. |
| Arrow keys, <kbd>⇧</kbd> with an arrow | Move the selection corner one pixel, or ten. |
| <kbd>Return</kbd> | Start a corner from the keyboard; press it again to copy. |
| <kbd>Esc</kbd> | Cancel the selection. |

Every shortcut can be changed in Settings, and a shortcut only works with <kbd>⌘</kbd> or <kbd>⌃</kbd>, so
ordinary typing is never captured by mistake. A shortcut for codes alone is optional.

<br>

## Private by design.

No account. No analytics. Your captures are stored encrypted on your Mac, with the key in your login Keychain.
The only network request Nictate ever makes is Check for Updates, and only when you ask it to.

<br>

## Tech specs

| | |
|:--|:--|
| **Compatibility** | macOS 14 Sonoma or later, on Apple silicon and Intel. Designed for macOS 27. |
| **Size** | About 4 MB |
| **Languages** | English and Spanish. Text is recognized in every language Vision supports. |
| **Built with** | Swift, AppKit, SwiftUI, Vision and ScreenCaptureKit |
| **Network access** | Only Check for Updates, when you ask for it |
| **Price** | Free |
| **License** | MIT |

<br>

## Install

Download the disk image from the [latest release](../../releases/latest), open it, and drag Nictate to
Applications. Nictate is signed with a local certificate and is not notarized, so macOS asks you once to confirm
that you want to open it:

- **macOS 15 and later:** open System Settings, go to **Privacy & Security**, and click **Open Anyway** next to the message about Nictate.
- **macOS 14:** Control-click Nictate, choose **Open**, then **Open** again.

On first launch, a welcome window asks for the **Screen Recording** permission. Grant it, then restart Nictate
from that window, because macOS applies the permission only to a freshly launched app.

<br>

## Build from source

You need macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode is not required.

```sh
git clone https://github.com/jrthormann/Nictate.git
cd Nictate
make install
```

`make install` builds the app, copies it to Applications and opens it. Run the checks with `make check`.

<br>

## Contributing

Issues and pull requests are welcome. Translations live in `Sources/Nictate/Resources/`, one `.lproj` folder per language.
`make strings` checks that none is missing. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes each file.

<br>

---

<sub>
Nictate is licensed under the MIT License; see <a href="LICENSE">LICENSE</a>. It uses only Apple system frameworks,
and GitHub's public release list for Check for Updates. Release notes are in <a href="CHANGELOG.md">CHANGELOG.md</a>.
</sub>

<br>
<br>

<p align="center">
  <img src="docs/images/icon.png" width="64" height="64" alt="">
  <br>
  <sub>Copy the text you can see. No cloud, no tracking, no bullshit.</sub>
  <br><br>
  <sub>🇩🇴 Built in the Dominican Republic. Runs on Coke Zero, pizza, and questionable life choices. If it works, it's a feature. If it breaks, it's open source.</sub>
</p>
