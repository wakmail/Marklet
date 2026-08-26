# Security Policy

Marklet is a Markdown editor for macOS. It edits local files, talks to a license server, and checks for updates.
Those are the places where a security problem would matter most, so please tell us about anything you find there.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.3 and later | Yes |
| Earlier than 1.3 | No, please update first |

Marklet updates itself through Sparkle, and every release is signed and notarized. If you are running an older
build, update before reporting, in case the problem is already fixed.

## Reporting a vulnerability

Please report privately rather than opening a public issue.

* Preferred: open a private report through GitHub, under Security then Report a vulnerability on this repository.
* By email: hello@getmarklet.com, with "security" in the subject.

Helpful things to include, as far as you have them:

* What version of Marklet and what version of macOS.
* What an attacker gains, and what they need first, for example a file the person opened or a network position.
* Steps to reproduce, and a sample document if one triggers it.
* Whether the finding is already public anywhere.

## What happens next

* We acknowledge a report within three days.
* We follow up with either a fix plan or an explanation of why it is not a vulnerability, normally within ten days.
* We aim to ship a fix within thirty days for anything an ordinary user can hit. Something requiring an unusual
  setup may take longer, and we will say so rather than go quiet.
* You will be credited in the release notes if you want to be, or left out if you prefer.

Please give us a reasonable chance to ship a fix before publishing details.

## Scope

In scope:

* The Marklet app: opening and saving documents, crash recovery backups, the Markdown parser and renderer, the
  scraps folder, and folder access grants in sandboxed builds.
* Update delivery: the appcast, the update signature check, and anything that could cause Marklet to install code
  it should not.
* Licensing: activation, validation, deactivation, and receipt verification, including anything that leaks another
  person's license or seat information.

Out of scope:

* Bugs with no security consequence. Please file those as ordinary issues, they are still welcome.
* Attacks that require an already compromised Mac, physical access to an unlocked Mac, or administrator rights the
  attacker should not have.
* Findings from automated scanners with no working reproduction.
* Denial of service from a deliberately enormous document, unless it corrupts data or escapes the app.

## What Marklet sends over the network

So you know what is normal and what is not:

* Update checks fetch the appcast and release archives from getmarklet.com.
* Licensing sends a hardware fingerprint and license key to the license server, and receives a signed receipt.
* Nothing else leaves your Mac. Document content is never uploaded.
