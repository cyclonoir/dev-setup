# Managed by dev-setup (steps/55-shell.sh), which rewrites this file on every run.
# Your own settings go in ~/.config/fish/config.fish, which fish loads after this file.

# The desktop session gets ~/.local/bin from ~/.profile, but fish as a login shell (SSH, a console)
# never reads that file.
fish_add_path --global --path ~/.local/bin

# mise puts its tools on PATH: with its prompt hook in interactive shells, and with shims in scripts
# and `fish -c`, as mise's docs recommend.
if status is-interactive
    @MISE@ activate fish | source
    starship init fish | source
else
    @MISE@ activate fish --shims | source
end
