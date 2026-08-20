# codespaces_scheduled_keepalive

Wake a GitHub Codespace before work and keep it alive during configured hours.

## Install (Linux and macOS)

Needs [GitHub CLI](https://cli.github.com/) (`gh auth login`) with codespace access, and a machine that is **already on** before work. A sleeping laptop will not fire the timer.

```sh
git clone https://github.com/dgmcguire/codespaces_scheduled_keepalive.git
cd codespaces_scheduled_keepalive

mkdir -p ~/.local/bin ~/.config/codespaces-keepalive
install -m 755 bin/codespaces-keepalive ~/.local/bin/codespaces-keepalive
cp config.example ~/.config/codespaces-keepalive/config
```

Edit `~/.config/codespaces-keepalive/config`: set `name` from `gh codespace list`, plus `timezone`, `minute`, `hours`, and `weekdays`. Put `~/.local/bin` on your `PATH` if it is not already.

**Linux** (systemd user timer, catch-up after the machine was off):

```sh
codespaces-keepalive install systemd --apply
```

**macOS** (LaunchAgent, every 60s; `tick` applies the policy):

```sh
codespaces-keepalive install launchd --apply
```

**Either OS** (crontab derived from the policy):

```sh
codespaces-keepalive install cron --apply
```

`install` prints the unit or crontab by default; `--apply` writes it. Confirm with `codespaces-keepalive status`.

Run `--apply` from a login shell that can already find `gh`, `date`, and `sed`. The installer snapshots that `PATH` (existing directories only, plus `/usr/bin:/bin`) into the timer, so NixOS does not inherit a macOS Homebrew layout and vice versa. The Nix package and home-manager module wrap those tools instead of relying on the snapshot.

**Uninstall** (Linux and macOS; print-only until `--apply`):

```sh
codespaces-keepalive uninstall           # show cron, systemd, and launchd artifacts
codespaces-keepalive uninstall --apply   # stop timers and remove those files
```

That undoes `install`. It does not delete `~/.config/codespaces-keepalive/config`, the log directory, or the binary. If you installed via home-manager, set `services.codespaces-keepalive.enable = false` instead — that unit uses a different name.

## Shape

```
minute=0 hours=7-17 weekdays=1-5   # in `timezone` (0=Sun ... 6=Sat)

install cron     →  crontab fires at those times, tick --force
systemd/launchd  →  wake every minute, tick noops unless the policy matches
                     (silent skip; no GitHub calls)
```

On a match, `tick` starts a stopped codespace and SSHs a heartbeat so idle timeout resets.

Put the timer on a machine that is **already on** before work. A sleeping laptop will not fire cron/launchd.

## Config

```
mkdir -p ~/.config/codespaces-keepalive
cp config.example ~/.config/codespaces-keepalive/config
```

`KEY=value` (not sourced). `name` is the codespace from `gh codespace list`. When to run:

```
minute    0-59
hours     *  |  8  |  7-17
weekdays  *  |  4  |  1-5     0=Sun ... 6=Sat
```

No crontab syntax, lists, steps, or day names. `install cron` turns the policy into a crontab line (`0 7-17 * * 1-5`).

Example (2-hour idle policy → hourly is enough), weekdays 07:00–17:00:

```
minute=0
hours=7-17
weekdays=1-5
timezone=America/Chicago
```

`log_dir` defaults to `$XDG_STATE_HOME/codespaces-keepalive` (`~/.local/state/codespaces-keepalive`). Every run appends to `log_dir/keepalive.log`. `debug=true` (or `--debug`) adds policy miss/match and `gh` traces to that file. `--log-dir DIR` overrides the directory for one run.

Without debug, cron/systemd/launchd stay quiet on stdout (not a tty), so cron will not mail you on a successful noop. Failures still go to stderr.

Other examples:

```
hours=* weekdays=1-5     # every hour, weekdays, all day
hours=8 weekdays=1-5     # 8:00 only, weekdays
hours=8-18 weekdays=*    # 08:00-18:00 every day
```

## Usage

```sh
codespaces-keepalive status
codespaces-keepalive tick --dry-run
codespaces-keepalive tick --force    # ignore the policy
codespaces-keepalive tick --debug --log-dir /tmp/cs-keep
codespaces-keepalive uninstall
```

## What `tick` does

1. If `minute`/`hours`/`weekdays` do not match now in `timezone`, exit 0 (unless `--force`).
2. `gh codespace view -c NAME` for the configured `name`.
3. `Shutdown` → `POST /user/codespaces/{name}/start`, wait until `Available`.
4. `Available` → `gh codespace ssh -c NAME -- sh -c true` so GitHub records client activity.

The codespace image needs SSH, which GitHub's default images do.

## Nix / home-manager

The flake wraps the script with `gh` on `PATH` and exposes a home-manager module that writes `~/.config/codespaces-keepalive/config` plus a user timer (systemd on Linux, launchd on macOS).

```nix
# flake.nix
{
  inputs.codespaces-keepalive.url = "github:dgmcguire/codespaces_scheduled_keepalive";
}

# home.nix
{
  imports = [ inputs.codespaces-keepalive.homeManagerModules.default ];

  services.codespaces-keepalive = {
    enable = true;
    codespaceName = "your-codespace-name"; # gh codespace list
    timezone = "America/Chicago";
    hours = "7-17";
    weekdays = "1-5";
  };
}
```

CLI only (no timer):

```nix
home.packages = [ inputs.codespaces-keepalive.packages.${pkgs.system}.default ];
```

From this repo, or without cloning:

```sh
nix run github:dgmcguire/codespaces_scheduled_keepalive -- status
nix build github:dgmcguire/codespaces_scheduled_keepalive
nix flake check
```
