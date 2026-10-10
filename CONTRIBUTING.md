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

## Translations

Interface strings are in `Sources/Nictate/Resources/<language>.lproj/Localizable.strings`. Every key must exist in every language. `make strings` checks that.

## Latest release

The current public test release is listed at [Releases](https://github.com/jrthormann/Nictate/releases/latest). Test it, and tell us what you find.
