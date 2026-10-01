# Security

Safience holds your sign-ins to the tools you work in, so a hole in it matters more than most bugs. If you find one, please tell us privately first.

## How to report

On GitHub: the repository's **Security** tab › [**Report a vulnerability**](https://github.com/taehee-pd/Safience/security/advisories/new). Only the maintainers see it. Say what you found, where in the code, and how to see it happen. A proof of concept that stays on your own device is welcome; please don't try it on other people's accounts or data.

Please don't open a public issue or pull request that describes the problem until a fixed version is out. A pull request that only fixes it, without spelling out the attack, is fine.

## What counts

Anything that lets a web page, another app or someone on the network do more than they should, for example:

- a page reaching the app's own content world or its message handler, or making the app run something;
- a script of ours running, or a call going into a page, on a hands-off host (`HandsOff.swift`);
- a cookie being read, or one space's sign-ins reaching another space;
- a picture or the history of a sign-in page written to disk;
- a download written outside its folder, or another app opened without a click.

A site that doesn't work is a bug rather than a security problem: open an [issue](https://github.com/taehee-pd/Safience/issues) for that.
