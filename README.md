# dev-setup

Scripts that configure an Ubuntu 26.04 machine as my desktop and dev environment: the work laptop
or a personal machine. They follow the "My Ubuntu 26.04 Desktop & Dev Setup" guide.

They work for an AD (SSSD) account or a local one; the user is whoever runs them. On the work laptop
they sit on top of IT's compliance baseline (LUKS, AD join, Intune, Sophos, FortiClient), which
`--work` and `verify.sh --work` check but never change.

## Usage

```bash
git clone <this repo> ~/dev-setup && cd ~/dev-setup
./install.sh --dry-run         # see every command first
./install.sh                   # run all default steps (personal machine)
./install.sh --work            # work laptop: also install Edge and check IT's baseline
./install.sh --only greetd --switch-dm   # make Noctalia Greeter the login screen (on next reboot)
./verify.sh                    # check the result (add --work on the work laptop)
```

Run as your own user (not root); steps call `sudo` where needed. Re-running is safe: each step
checks before acting, so a second run changes nothing. Before a file is first changed in a run, the
original is copied to `/var/backups/dev-setup/<run>/` (system files) or
`~/.local/state/dev-setup/backups/<run>/` (your files), mirroring its path; the run ends by listing them.
Logs go to `~/.local/state/dev-setup/install.log`.

Options: `--only a,b`, `--skip a,b`, `--with fingerprint,umbriel`, `--work`, `--dry-run`, `--switch-dm`.

## Steps

| Step | What it does |
| --- | --- |
| `preflight` | Ubuntu 26.04, installs curl; with `--work`, warns about missing IT baseline items (LUKS, AD join, Sophos, FortiClient, Intune, GNOME fallback), never changing them |
| `base` | Build tools, git, ripgrep, fd (`fd` link), tmux, btop; apt pin keeping Microsoft's .NET packages out |
| `fonts` | JetBrainsMono Nerd Font + Symbols Nerd Font (nerd-fonts releases) in `~/.local/share/fonts`; fontconfig rule making it the default monospace (foot picks it up) |
| `hyprland` | Hyprland 0.53, portal (screen sharing), polkit agent, wl-clipboard, brightnessctl, foot |
| `browsers` | Vivaldi from its vendor's repo; on a work machine (`--work`) also Microsoft Edge, which Intune/Conditional Access need |
| `noctalia` | Noctalia APT repo + `noctalia` |
| `hypr-config` | `~/.config/hypr/dev-setup.conf`: the whole keymap (ported from Omarchy, shell actions via Noctalia; SUPER+K searches it), autostart, `DOTNET_ROOT`; helper scripts in `~/.local/bin`; `hyprland.conf` created without Hyprland's default binds, plus one `source =` line; power button opens Noctalia's session menu (logind drop-in, active after reboot) |
| `mise` | mise, bash activation, `neovim node go dotnet@10 gh` (GitHub CLI), Claude Code (`claude@latest`: Anthropic's release binaries; update with `mise upgrade claude`), `global.json` support |
| `podman` | Podman + podman-compose; subuid/subgid range for the user via `usermod` if missing (AD/SSSD users never get one from `useradd`; local users already have one) |
| `virt` | QEMU/KVM, libvirt, virt-manager, OVMF, swtpm; user added to `libvirt` + `kvm` |
| `greetd` | greetd + Noctalia Greeter (its package configures greetd), pre-filled user/session, keyring PAM lines, passwordless theme sync; switches from GDM only with `--switch-dm` |
| `fingerprint` | Optional (`--with fingerprint`), machines with a reader: fprintd (checked for a reader before the PAM module goes in); fingerprint for `sudo` and admin (polkit) prompts, falling back to the password after 10 s; keeps it out of the shared login stack (removing it if someone enabled it there), where it would fight Noctalia's lock screen for the sensor. The lock screen uses the reader directly; the login screen stays password-only. Enroll with `fprintd-enroll` |
| `umbriel` | Optional (`--with umbriel`): Umbriel as an extra session to trial |

Constants (terminal, mise tools, package lists) live at the top of `lib/common.sh`; to leave out a
mise tool (Claude Code, say, where policy rules it out), remove it from `MISE_TOOLS`. The username
is always the account running the scripts (AD or local); per-user changes go to that account's home.

## Rollback: login screen

If Noctalia Greeter won't log you in: press Ctrl+Alt+F3, log in on the console, then

```bash
sudo systemctl enable --force gdm && echo /usr/sbin/gdm3 | sudo tee /etc/X11/default-display-manager && sudo reboot
```

(The step's own rollback notice prints the exact unit and path that were active before the switch;
`grep NOTICE ~/.local/state/dev-setup/install.log` finds it again later.)

Logs: `journalctl -b -u greetd`.

## Not automated

Windows VM creation, screen-sharing tests, the greeter's "Sync Now" button and, on the work laptop,
Intune compliance.
`verify.sh` lists these at the end.

## Notes

- Hyprland config uses `hyprland.conf` syntax for Ubuntu's Hyprland 0.53. Upstream moved to Lua in
  0.55; translate snippets from newer docs, and skip features newer than 0.53.
- mise-installed tools (including .NET and Claude Code) don't get Ubuntu's automatic security updates: run
  `mise upgrade`, and `mise prune` to remove old versions. Re-running the scripts doesn't upgrade them; it
  only adds tools missing from your global mise config.
- Some steps edit package conffiles (`/etc/pam.d/sudo` with `--with fingerprint`, greetd's PAM file).
  If a later update of that package changes the same file, unattended-upgrades holds it back for a
  manual `apt upgrade`, which asks whether to keep your version.
