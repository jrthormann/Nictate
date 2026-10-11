<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.png">
  <img src="docs/images/hero-light.png" alt="Nictate. Copy the text you can see. The app frames four lines of a note; the menu offers the color and the link it found, and a notification says Text copied.">
</picture>

<p align="center">
  <a href="https://github.com/jrthormann/Nictate/actions/workflows/ci.yml"><img src="https://github.com/jrthormann/Nictate/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="https://github.com/jrthormann/Nictate/releases"><img src="https://img.shields.io/github/v/release/jrthormann/Nictate?include_prereleases&label=release" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/jrthormann/Nictate" alt="MIT license"></a>
</p>

<p align="center">
  An independent, open-source macOS utility built to make text on your screen usable.
  <br>
  <a href="https://github.com/jrthormann/Nictate/releases">Download&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#build-from-source">Build it yourself&nbsp;&rsaquo;</a>
  <br><br>
  Made in the Dominican Republic <img src="docs/images/flag-do.svg" width="16" height="16" alt="" align="absmiddle">, powered by Coke Zero and pizza.
  <br><br>
  English&nbsp;·&nbsp;<a href="docs/i18n/README.es.md">Español</a>
</p>

<br>

## Select. Copy. Move on.

Some text on your screen just won't let you copy it. Nictate grabs it for you.

Press <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> and drag over whatever has words on it: a web page, a
photo of a whiteboard, a paused video, a slide someone is sharing. The text lands on your clipboard in a fraction
of a second.

It all happens on your Mac, using Apple's Vision framework, in any language Vision reads. Nothing gets uploaded.
Your other problems are still yours, sorry.

<br>

## Pixel by pixel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/bento-dark.png">
  <img src="docs/images/bento-light.png" alt="Select. It's copied. Pixel by pixel. Colors, links, codes. Never leaves your Mac.">
</picture>

<br>
<br>

Selections snap to whole screen pixels, so every edge sits exactly where you put it. The arrow keys move the
corner one pixel at a time, and Shift plus an arrow moves it ten. It works the same way as the system screenshot
tool, so it'll feel familiar.

<br>

## It knows what it's reading.

Nictate can tell code, tables, lists and plain prose apart, and it keeps each one the way it was written. Code
keeps its line breaks and indentation. Tables paste with tabs between the cells, so they drop straight into a
spreadsheet. Only ordinary prose gets joined into paragraphs, which means a list never turns into a sentence.

Colors, links, emails and phone numbers from your last capture are one click away in the menu. QR codes and
barcodes copy their contents. A link inside one gets copied, or opens only after you confirm the address, whichever
you prefer.

<br>

## Shortcuts

| Shortcut | What it does |
|:--|:--|
| <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Select an area and copy its text. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd> | Cycle through your recent captures. |
| Arrow keys, or <kbd>⇧</kbd> with an arrow | Move the selection corner one pixel, or ten. |
| <kbd>Return</kbd> | Start a corner from the keyboard, then press it again to copy. |
| <kbd>Esc</kbd> | Cancel the selection. |

You can change any shortcut in Settings. Every shortcut needs <kbd>⌘</kbd> or <kbd>⌃</kbd>, so ordinary typing never
fires a capture by accident. The shortcut for codes alone is optional.

<br>

## Private by design.

No account and no analytics. If you turn on Save Captures, the 15 most recent captures are kept in a plain file on
your Mac. Nictate doesn't encrypt that file, so turn saving off or clear the file whenever you like.

Nictate makes no network requests of its own, except Check for Updates, and only when you ask it to. A link you
choose to open goes to your browser, which connects the way it normally would. To report a security problem, see [SECURITY.md](SECURITY.md).

<br>

## Tech specs

| | |
|:--|:--|
| **Compatibility** | Built for macOS. Minimum deployment target: macOS 14 Sonoma, on Apple silicon and Intel. Tested by the maintainer on macOS 27. |
| **Size** | About 4 MB |
| **Languages** | English and Spanish. Text is recognized in every language Vision supports. |
| **Built with** | Swift, AppKit, SwiftUI, Vision and ScreenCaptureKit |
| **Network access** | Only Check for Updates, and only when you ask. Links open in your browser only when you choose. |
| **Price** | Free |
| **License** | MIT |

<br>

## Status

Nictate 1.0.0-beta.2 is an experimental public beta. It works, and I've tested it on macOS 27. I haven't tried it on
macOS 14, 15 or 26 yet, and VoiceOver support hasn't been audited. Reports are welcome. The
[CHANGELOG](CHANGELOG.md) lists what's tested and what isn't. Nictate started as a side project, and this beta shows whether it is useful to other people.

This beta isn't notarized by Apple, so macOS asks you to approve it on first launch. See [Install](#install).

If you have 1.0.0-beta.1, download beta.2 from the [Releases page](https://github.com/jrthormann/Nictate/releases) and replace the app in Applications. Beta.1 reports itself as version 1.0.0, so its Check for Updates can't find beta.2.

## Install

Download the disk image only from the [releases page](https://github.com/jrthormann/Nictate/releases). Open it, and drag Nictate into Applications.

**Nictate isn't notarized by Apple.** It is signed with a local certificate, so macOS asks you to approve it once, before its first launch. This is a known limit of this beta. You don't need to change any security setting to open Nictate.

1. Open **Applications** and double-click **Nictate**.
2. macOS shows a message that Apple couldn't verify Nictate. Dismiss it with **Done** (on macOS 27 that is the button's name), and don't choose **Move to Trash**. The exact wording depends on your macOS version.
3. Open **System Settings**, go to **Privacy & Security**, and scroll to **Security**. Click **Open Anyway** next to the message about Nictate, then enter your password or use Touch ID.
4. Open Nictate again. If macOS asks you to confirm, click **Open**.
5. The welcome window asks you to **Allow screen recording**. Click **Open System Settings**, turn on Nictate in the **Screen & System Audio Recording** list (older versions of macOS may call it Screen Recording), then click **Restart Nictate** in the welcome window.
6. Select text with <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd>, and it lands on your clipboard.

**On macOS 14 Sonoma,** use this instead of steps 2 to 4: Control-click Nictate in Applications, choose **Open**, then click **Open** again. Then continue with step 5.

**About the signature.** A valid code signature lets macOS confirm that the app is the same one that was built, and that it was signed with Nictate's local certificate. It isn't an Apple Developer ID signature, and Apple hasn't notarized or verified Nictate. That is why macOS asks you to approve it.

**Permissions.** Nictate needs Screen Recording to read the text on your screen. It doesn't use Accessibility access. The first time Nictate has something to tell you, macOS may ask whether to allow notifications. That's optional, and Nictate works without them.

**Checksum (optional).** Each release lists the SHA-256 checksum of its disk image. You can compare it with your download to confirm the file matches the published one. This needs Terminal, so it isn't part of the normal install.

<br>

## Build from source

You need macOS 14 or later and the Command Line Tools (`xcode-select --install`). You don't need Xcode.

```sh
git clone https://github.com/jrthormann/Nictate.git
cd Nictate
make install
```

`make install` builds the app, copies it to Applications and opens it. `make check` runs the tests.

<br>

## Support the Project

If Nictate saves you some time, you can chip in through Buy Me a Coffee or PayPal. It's entirely optional, and it
goes toward maintenance, fixes and whatever comes next.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-jrthormann-FFDD00?logo=buymeacoffee&logoColor=000000)](https://www.buymeacoffee.com/jrthormann)
[![PayPal](https://img.shields.io/badge/PayPal-jrthormann-00457C?logo=paypal&logoColor=FFFFFF)](https://paypal.me/jrthormann)

<br>

## Contributing

Bug reports, ideas and pull requests are all welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers how to report a bug,
propose a change, build, run the tests and send a pull request. Translations live in `Sources/Nictate/Resources/`,
one `.lproj` folder per language, and `make strings` makes sure none is missing. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
walks through each file. The test releases are on the [Releases page](https://github.com/jrthormann/Nictate/releases). Security problems are reported privately, as [SECURITY.md](SECURITY.md) explains.

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
