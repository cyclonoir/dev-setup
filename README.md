# dev-setup

Scripts that configure an Ubuntu 26.04 machine as my desktop and dev environment: the work laptop
or a personal machine. They follow the "My Ubuntu 26.04 Desktop & Dev Setup" guide.

They work for an AD (SSSD) account or a local one; the user is whoever runs them. On the work laptop
they sit on top of IT's compliance baseline (LUKS, AD join, Intune, Sophos, FortiClient), which
`--with compliance` and `verify.sh --compliance` check but never change.

## Usage

```bash
git clone <this repo> ~/dev-setup && cd ~/dev-setup
./install.sh --dry-run         # see every command first
./install.sh                   # run all default steps (personal machine)
./install.sh --with compliance # work laptop: also check IT's baseline and install Edge
./install.sh --only greetd --switch-dm   # make Noctalia Greeter the login screen (on next reboot)
./verify.sh                    # check the result (add --compliance on the work laptop)
```

Run as your own user (not root); steps call `sudo` where needed. Re-running is safe: each step
checks before acting. Changed system files are backed up as `<file>.bak-<timestamp>`.
Logs go to `~/.local/state/dev-setup/install.log`.

Options: `--only a,b`, `--skip a,b`, `--with compliance,umbriel`, `--dry-run`, `--switch-dm`.

## Steps

| Step | What it does |
| --- | --- |
| `preflight` | Ubuntu 26.04, not root, network |
| `compliance` | Optional (`--with compliance`), work machine only: warns if IT baseline items are missing (LUKS, AD join, Sophos, FortiClient, Intune, GNOME fallback); never changes them. Also marks the run as a work machine, so `browsers` adds Edge |
| `base` | Build tools, git, ripgrep, fd (`fd` link), tmux, btop; apt pin keeping Microsoft's .NET packages out |
| `fonts` | JetBrainsMono Nerd Font + Symbols Nerd Font (nerd-fonts releases) in `~/.local/share/fonts`; fontconfig rule making it the default monospace (foot picks it up) |
| `hyprland` | Hyprland 0.53, portal (screen sharing), polkit agent, wl-clipboard, brightnessctl, foot |
| `browsers` | Vivaldi from its vendor's repo; on a work machine (`--with compliance`) also Microsoft Edge, which Intune/Conditional Access need |
| `noctalia` | Noctalia APT repo + `noctalia` |
| `hypr-config` | `~/.config/hypr/dev-setup.conf`: the whole keymap (ported from Omarchy, shell actions via Noctalia; SUPER+K searches it), autostart, `DOTNET_ROOT`; helper scripts in `~/.local/bin`; `hyprland.conf` created without Hyprland's default binds, plus one `source =` line; power button opens Noctalia's session menu (logind drop-in, active after reboot) |
| `mise` | mise, bash activation, `neovim node go dotnet@10 gh` (GitHub CLI), `global.json` support |
| `claude` | Claude Code through mise (`claude@latest`: Anthropic's release binaries); update with `mise upgrade claude` |
| `podman` | Podman + podman-compose; subuid/subgid range for the user via `usermod` if missing (AD/SSSD users never get one from `useradd`; local users already have one) |
| `virt` | QEMU/KVM, libvirt, virt-manager, OVMF, swtpm; user added to `libvirt` + `kvm` |
| `greetd` | greetd + Noctalia Greeter, pre-filled user/session, keyring PAM lines, passwordless theme sync; switches from GDM only with `--switch-dm` |
| `umbriel` | Optional (`--with umbriel`): Umbriel as an extra session to trial |

Constants (terminal, mise tools, package lists) live at the top of `lib/common.sh`. The username
defaults to the account running the scripts; override with `DEV_USER=name ./install.sh`.

## Rollback: login screen

If Noctalia Greeter won't log you in: press Ctrl+Alt+F3, log in on the console, then

```bash
sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot
```

Logs: `journalctl -b -u greetd`.

## Not automated

Windows VM creation, screen-sharing tests, the greeter's "Sync Now" button and, on the work laptop,
Intune compliance.
`verify.sh` lists these at the end.

## Notes

- Hyprland config uses `hyprland.conf` syntax for Ubuntu's Hyprland 0.53. Upstream moved to Lua in
  0.55; translate snippets from newer docs, and skip features newer than 0.53.
- mise-installed tools (including .NET and Claude Code) don't get Ubuntu's automatic security updates: run
  `mise upgrade`, and `mise prune` to remove old versions.
