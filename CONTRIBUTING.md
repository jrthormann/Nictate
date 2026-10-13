# Contributing to Nictate

Thanks for trying Nictate. It is a small utility, and we want to keep it that way. Clear reports and small, focused changes help most.

## Report a bug

Open an issue with the [bug report form](https://github.com/jrthormann/Nictate/issues/new/choose). Include:

- Your macOS version and Mac model.
- The steps that caused the problem, and what you expected.
- What happened instead, and a screenshot if it helps.

Please don't paste captured text you want to keep private. A short description is enough.

## Propose a change

For a new feature or a larger change, open an issue first and describe the problem it solves. Small fixes, documentation and translations can go straight to a pull request.

[docs/PRODUCT.md](docs/PRODUCT.md) says what Nictate is for and what it already does. A proposal that fits its principles and needs is easier to decide on.

## Build from source

You need macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode is not required.

```sh
git clone https://github.com/jrthormann/Nictate.git
cd Nictate
make build        # builds build/Nictate.app
make install      # builds, copies to Applications and opens it
make test-app     # builds build/NictateTest.app, a QA app with its own data
```

## Run the tests

```sh
make check        # unit tests, UI tests, string and source checks
```

`make ui-test` needs a window server, so it runs on a Mac you are logged into, not over SSH.

## Submit a pull request

1. Create a branch from `main`.
2. Make one focused change, and run `make check`. It must pass.
3. Open a pull request and fill in the template: what changed, how you tested it, and what you saw if the change affects the interface.

Keep changes small enough to review in one sitting. Tell us when something is untested.

## Manual checks

Focus and the desktop cannot be tested headlessly, so `make check` does not cover them. Before a release, check these
on a Mac. Use the QA build (`make test-app`), so your own captures and history are not touched.

1. **Copy from the panel:** open a history entry with Return. The app you were in should be frontmost, and ⌘V should paste there.
2. **Capture:** press the capture shortcut in another app, drag over some text, and ⌘V in that app. The text should paste.
3. **Escape:** open the panel and press Escape. The app you came from should be frontmost.
4. **Settings:** open Settings from the panel. Its window should stay in front, also after you press the capture shortcut there and copy some text.
5. **Switch away:** start a capture, switch to another app before it finishes, and check that focus is not taken back.
6. **Unreadable history:** put junk in `history.json` in the QA build's history folder while Save Captures is off. The History row should still appear, with Discard Unreadable History.
7. **Nothing found, then retry:** press the capture shortcut in another app and select an empty area. "No text found" should show, and that app should be frontmost again. Press the shortcut again at once and copy some text: ⌘V should paste in that app. Then press Esc once before dragging and once during a drag: each time that app should be frontmost, and ⌘V should paste what it pasted before.
8. **Link question:** set QR & Barcode Results to Ask Before Opening, and capture a QR code that holds a web link. The question should keep focus while it is open. Cancel or Esc should bring back the app you came from. Open should leave the browser in front.

## Translations

Interface strings are in `Sources/Nictate/Resources/<language>.lproj/Localizable.strings`. Every key must exist in every language. `make strings` checks that.

## Security and conduct

Report a security problem privately, through the [Security tab](https://github.com/jrthormann/Nictate/security), as
described in [SECURITY.md](SECURITY.md). Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Latest release

The current public test release is listed at [Releases](https://github.com/jrthormann/Nictate/releases). Test it, and tell us what you find.
