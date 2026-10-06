# cuore-pkgs

The packages Cuore builds itself: `cuore`, `cuore-settings`, `cuore-keyring`, and the
desktop's dependencies that aren't in Arch Linux's official repositories (the Limine
hooks, `xdg-terminal-exec`, the Yaru icons and the share picker), and
`yay`, which installs the chooser's AUR extras, and `ufw-docker`, which keeps Docker's
published ports behind the firewall. Three chooser extras are built here too:
Cutline (a video editor), Jotter (terminal notes) and Sprawl (a city-building
game), all MIT, from their released tags, with a small patch each
(`cuore-names.patch`) that takes another desktop's name out of their files.

`bin/build` builds them in a throwaway Arch Linux container (rootless podman), signs
each package and the repository database with Cuore's key, and writes a pacman
repository to `out/`. Nothing runs as root on the host. Before a package goes into the
repository, `bin/check-names` makes sure nothing in it names the project Cuore was
forked from (`tests/check-names-test.sh` tests it).

    bin/build --src ../cuore            # everything, from the checkout's HEAD
    bin/build --src ../cuore --ref v0.1.0 cuore cuore-settings

Until the release key exists, the key is the development key described in cuore's
DECISIONS.md (D65, D68). The repository is published as GitHub releases named
`<channel>-<arch>` only when the maintainer says so.

PKGBUILDs start from another project's definitions (see NOTICE and UPSTREAM);
`tools/rebrand --check` keeps that project's name out of them.
