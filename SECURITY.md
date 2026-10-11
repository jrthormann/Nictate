# Security policy

Nictate reads the text on your screen, so it handles what you capture with care. Captured text stays on your Mac,
the app asks only for the access it needs, and the one network request it makes is the update check you start.

## Reporting a vulnerability

Please report a security problem privately, not in a public issue or pull request.

[Report a vulnerability](https://github.com/jrthormann/Nictate/security/advisories/new)

The link opens GitHub's private advisory form. You can also choose **Report a vulnerability** on the
[Security tab](https://github.com/jrthormann/Nictate/security) of this repository.

Include as much of the following as you can:

- What the problem is, and what it could let someone do.
- Steps to reproduce it. Use sample text rather than private captures.
- The Nictate version, shown in About Nictate, and your macOS version.
- Anything you tried, and what happened.

I review reports as time allows. Please keep the details private until a fix is released or the report has been
reviewed.

## Supported versions

Security fixes go into the latest release. Earlier versions, including 1.0.0-beta.1, do not get separate fixes, so
install the latest release.

## How Nictate handles your data

- **Recognition runs on your Mac.** Nictate reads text and barcodes with Apple's Vision framework. Screen captures are
  kept in memory and are not written to disk.
- **History is a plain file on your Mac.** With Save Captures on, the 15 most recent captures are kept in
  `history.json`, in the app's sandbox container. Nictate does not encrypt that file.
- **Deletion is your choice.** Turning off Save Captures asks whether to delete the saved captures. Clear History
  deletes them, Clear on Quit deletes them when Nictate quits, and Reset Nictate deletes them only if you tick its box.
  Discarding an unreadable history file asks for confirmation first.
- **The clipboard is read only as needed.** Nictate confirms each copy by reading back only the text it wrote. In
  Append mode it reads the current clipboard text to add the new capture to it. It does not read text that another app
  has marked as concealed or transient. The text already on the clipboard is not saved to history; only the new capture is. With "Hide from clipboard
  managers" on, Nictate marks its copies as transient, which the clipboard managers that follow that convention skip.
- **Permissions are macOS's.** Captures need Screen Recording permission, which macOS asks you to grant. Nictate does not
  use Accessibility access. It asks for notification permission once, when it first shows a notification.
- **Network use is limited.** Check for Updates is the only network request Nictate makes, and it runs only when you
  click it. It sends one request to GitHub's public releases API, with no cookies. A link opens in your browser only
  when you choose it.
- **Earlier encrypted history.** Earlier versions kept history in an encrypted file, with its key in your Keychain. You
  can import that file once, after you confirm. Nictate reads the old key only for that import. Normal use does not
  read the Keychain.
- Nictate runs in the App Sandbox with the hardened runtime.

## How Nictate is distributed

- **Signed, not notarized.** Each release is signed with a local certificate. That lets macOS confirm the app hasn't
  changed since it was built. The signature is not an Apple Developer ID signature, and Apple has not notarized the app,
  so macOS asks you to approve it on first launch. [docs/INSTALL.md](docs/INSTALL.md) explains the steps.
- **Download only from the Releases page.** Each release lists the SHA-256 checksum of its disk image. Comparing it with
  your download is optional.
- **Open source doesn't make a download safe on its own.** The source is public, so anyone can read it. The checksum
  only confirms that your file is the one that was published.

No software is free of vulnerabilities. Reports help find the ones that matter.

## Principles

- Keep captured text on your Mac.
- Ask for the least access macOS allows, and explain what it is for.
- Make deleting data something you choose, and ask first wherever data would be lost.
- Keep network use to the update check you start.
- Fix reported problems in the latest release.

## Scope

Nictate runs on your Mac and has no server of its own. Reports about the update check, the history file, the clipboard,
screen capture, and the permissions it asks for are all in scope.
