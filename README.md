# dotfiles

Personal dotfiles, organized so that every `*.symlink` file is linked into
`$HOME` as `.<name>` (e.g. `zsh/zshrc.symlink` → `~/.zshrc`).

## Install

```sh
git clone <this-repo> ~/dotfiles
~/dotfiles/install/bootstrap.sh
```

`bootstrap.sh`:

1. ensures `curl` is available using the OS's package manager
   (`apt`/`dnf`/`pacman`/`zypper`, `brew`, or `winget`/`choco`/`scoop`; each
   application installer pulls its own dependencies the same way);
2. installs applications via `install/installer.sh` (see below);
3. creates `git/gitconfig.symlink` from the example, prompting for your
   name/email and picking the right credential helper for the OS;
4. links every `*.symlink` into `$HOME` (app configs are linked by their own
   `install.sh`);
5. adds `~/.local/bin` to zsh's `PATH` and, on Windows, to the current user's
   persistent `PATH` (restart Git Bash to pick up the Windows change);
6. creates `~/.zshrc.local` from `zsh/zshrc.local.example` if missing;
7. installs the pre-commit secret-scan hook (`core.hooksPath=.githooks`).

## Applications

Each application lives in its own directory with an `install.sh`.
`install/installer.sh` runs them all (zsh first, then the rest in sorted order,
each in its own process). If an installer fails, it continues with the remaining
installers and exits with a failure status after the run. `bootstrap.sh` catches
that result, completes its remaining setup steps, then exits with a failure
status instead of reporting that setup completed successfully.

| Directory     | Installs                                                                                          |
| ------------- | ------------------------------------------------------------------------------------------------- |
| `zsh/`        | zsh shell                                                                                         |
| `oh-my-zsh/`  | [Oh My Zsh](https://ohmyz.sh)                                                                     |
| `nvm/`        | nvm (Linux/macOS) / nvm-windows                                                                   |
| `micro/`      | [micro](https://micro-editor.github.io) editor                                                    |
| `opencode/`   | [opencode](https://opencode.ai) + global config                                                   |
| `uv/`         | [uv](https://docs.astral.sh/uv/)                                                                  |
| `go/`         | [Go](https://go.dev) toolchain                                                                    |
| `python/`     | Python 3.14 via uv, set as default                                                                |
| `godot/`      | [Godot](https://godotengine.org) game engine                                                      |
| `docker/`     | [Docker Engine](https://docs.docker.com/engine/) (Linux only)                                     |
| `kubernetes/` | `kubectl` + [kind](https://kind.sigs.k8s.io) local clusters (requires Docker, Podman, or nerdctl) |

## Layout

```
.githooks/  pre-commit secret scan (core.hooksPath)
install/    bootstrap.sh, installer.sh, lib.sh
backup/     backup.sh, restore.sh, manifest
git/        gitconfig + global gitignore
zsh/        install.sh + zshrc + zshrc.local.example
oh-my-zsh/  install.sh
nvm/        install.sh
micro/      install.sh + bindings.json
opencode/   install.sh + opencode.jsonc
uv/         install.sh
go/         install.sh
python/     install.sh (uses uv)
godot/      install.sh
docker/     install.sh (Linux only; skipped on macOS and Windows)
kubernetes/ install.sh (kubectl + kind; uses an existing container runtime)
```

## Backup & restore

`backup/manifest` maps each managed config file to its live path and marks
whether it is snapshotted back into the repo.

```sh
~/dotfiles/backup/restore.sh   # repo -> machine (symlinks; backs up conflicts)
~/dotfiles/backup/backup.sh    # machine -> repo (snapshots non-symlinked files)
```

`restore.sh` reuses the same symlink mechanism as the installers. `backup.sh`
skips files already symlinked into the repo, since editing the live file
already edits the repo. Paths are resolved per OS (`$XDG_CONFIG_HOME`, or
`%APPDATA%` on Windows). To manage a new file, append a tab-separated row to
`backup/manifest`.

> Review `git diff` after a backup: configs may contain secrets.

## Machine-specific configuration

These files are **not tracked** by git:

- `git/gitconfig.symlink` — generated from `git/gitconfig.symlink.example`
- `zsh/zshrc.local` — copied from `zsh/zshrc.local.example`

Put host-specific exports (Go, gcloud, turso, minikube, uv, opencode, ...)
in `~/.zshrc.local`; keep `zsh/zshrc.symlink` portable.

## Platform support

Linux is the primary target. macOS and Windows (Git Bash) are supported on a
best-effort basis; symlink creation falls back to copying if the OS does not
allow symlinks.
