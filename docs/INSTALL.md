# Install Nictate

English · [Español](i18n/INSTALL.es.md) · [Back to the README](../README.md)

Download the disk image only from the [Releases page](https://github.com/jrthormann/Nictate/releases). Open it, and drag Nictate into Applications. The current release is 1.0.0-beta.5, so that's the one to download.

**Nictate isn't notarized by Apple.** A beta is signed ad hoc, with no certificate, so macOS asks you to approve it before its first launch. macOS may ask again after a beta update. This is a known limit of this beta. You don't need to turn off Gatekeeper or any other system-wide security protection to open Nictate. Approving Nictate covers Nictate only.

1. Open **Applications** and double-click **Nictate**.
2. macOS shows a message that Apple couldn't verify Nictate. Dismiss it with **Done** (on macOS 27 that is the button's name), and don't choose **Move to Trash**. The exact wording depends on your macOS version.
3. Open **System Settings**, go to **Privacy & Security**, and scroll to **Security**. Click **Open Anyway** next to the message about Nictate, then enter your password or use Touch ID.
4. Open Nictate again. If macOS asks you to confirm, click **Open**.
5. The welcome window asks you to **Allow screen recording**. Click **Open System Settings**, turn on Nictate in the **Screen & System Audio Recording** list (older versions of macOS may call it Screen Recording), then click **Restart Nictate** in the welcome window.
6. Select text with <kbd>⇧</kbd>&thinsp;<kbd>⌘</kbd>&thinsp;<kbd>2</kbd>, and it lands on your clipboard.

**On macOS 14 Sonoma,** use this instead of steps 2 to 4: Control-click Nictate in Applications, choose **Open**, then click **Open** again. Then continue with step 5.

**About the signature.** A valid code signature lets macOS confirm that the app is the same one that was built. A beta is signed ad hoc, so no certificate signed it, and each beta build has a new signature. It isn't an Apple Developer ID signature, and Apple hasn't notarized or verified Nictate. That is why macOS asks you to approve it. macOS treats each beta update as a new app, so grant Screen Recording again after each update (step 5).

**Permissions.** Nictate needs Screen Recording to read the text on your screen. It doesn't use Accessibility access. The first time Nictate has something to tell you, macOS may ask whether to allow notifications. That's optional, and Nictate works without them.

**Checksum (optional).** Each release lists the SHA-256 checksum of its disk image. You can compare it with your download to confirm the file matches the published one. This needs Terminal, so it isn't part of the normal install.

## Upgrading from beta.1

Beta.1 reports itself as version 1.0.0, so its Check for Updates can't see newer releases. If you have beta.1, download the current release from the [Releases page](https://github.com/jrthormann/Nictate/releases) and replace the app in Applications.
