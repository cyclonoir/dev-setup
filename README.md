# dev-setup

Scripts that configure my Ubuntu 26.04 work laptop on top of IT's compliance baseline
(LUKS, AD join via SSSD, Intune, Sophos, FortiClient). They follow the
"My Ubuntu 26.04 Desktop & Dev Setup" guide.

They never change IT-managed components; preflight and verify only check them.

## Usage

```bash
git clone <this repo> ~/dev-setup && cd ~/dev-setup
./install.sh --dry-run         # see every command first
./install.sh                   # run all default steps
./install.sh --only greetd --switch-dm   # make Noctalia Greeter the login screen (on next reboot)
./verify.sh                    # check the result
```

Run as your own user (not root); steps call `sudo` where needed. Re-running is safe: each step
checks before acting. Changed system files are backed up as `<file>.bak-<timestamp>`.
Logs go to `~/.local/state/dev-setup/install.log`.

Options: `--only a,b`, `--skip a,b`, `--with umbriel`, `--dry-run`, `--switch-dm`.

## Steps

| Step | What it does |
| --- | --- |
| `preflight` | Ubuntu 26.04, not root, network; warns if IT baseline items are missing |
| `base` | Build tools, git, ripgrep, fd (`fd` link), tmux, btop; apt pin keeping Microsoft's .NET packages out |
| `fonts` | JetBrainsMono Nerd Font + Symbols Nerd Font (nerd-fonts releases) in `~/.local/share/fonts`; fontconfig rule making it the default monospace (foot picks it up) |
| `hyprland` | Hyprland 0.53, portal (screen sharing), polkit agent, wl-clipboard, brightnessctl, foot |
| `browsers` | Vivaldi (main) and Microsoft Edge (work: Intune/Conditional Access) from their vendors' repos |
| `noctalia` | Noctalia APT repo + `noctalia` |
| `hypr-config` | `~/.config/hypr/dev-setup.conf`: the whole keymap (ported from Omarchy, shell actions via Noctalia; SUPER+K searches it), autostart, `DOTNET_ROOT`; helper scripts in `~/.local/bin`; `hyprland.conf` created without Hyprland's default binds, plus one `source =` line; power button opens Noctalia's session menu (logind drop-in, active after reboot) |
| `mise` | mise, bash and nushell activation, `neovim node go dotnet@10`, `global.json` support |
| `podman` | Podman + podman-compose; subuid/subgid range for the AD user (not added automatically for SSSD users) |
| `virt` | QEMU/KVM, libvirt, virt-manager, OVMF, swtpm; `libvirt` + `kvm` groups via `gpasswd` |
| `greetd` | greetd + Noctalia Greeter, pre-filled user/session, keyring PAM lines, passwordless theme sync; switches from GDM only with `--switch-dm` |
| `umbriel` | Optional (`--with umbriel`): Umbriel as an extra session to trial |

Constants (username, terminal, mise tools, package lists) live at the top of `lib/common.sh`.

## Rollback: login screen

If Noctalia Greeter won't log you in: press Ctrl+Alt+F3, log in on the console, then

```bash
sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot
```

Logs: `journalctl -b -u greetd`.

## Not automated

Windows VM creation, Intune compliance, screen-sharing tests and the greeter's "Sync Now" button.
`verify.sh` lists these at the end.

## Notes

- Hyprland config uses `hyprland.conf` syntax for Ubuntu's Hyprland 0.53. Upstream moved to Lua in
  0.55; translate snippets from newer docs, and skip features newer than 0.53.
- mise-installed tools (including .NET) don't get Ubuntu's automatic security updates: run `mise upgrade`.
