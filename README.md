# codespaces_scheduled_keepalive

Wake a GitHub Codespace before work and keep it alive on a crontab schedule.

## Install (Linux and macOS)

Needs [GitHub CLI](https://cli.github.com/) (`gh auth login`) with codespace access, and a machine that is **already on** before work. A sleeping laptop will not fire the timer.

```sh
git clone https://github.com/dgmcguire/codespaces_scheduled_keepalive.git
cd codespaces_scheduled_keepalive

mkdir -p ~/.local/bin ~/.config/codespaces-keepalive
install -m 755 bin/codespaces-keepalive ~/.local/bin/codespaces-keepalive
cp config.example ~/.config/codespaces-keepalive/config
```

Edit `~/.config/codespaces-keepalive/config`: set `name` from `gh codespace list`, plus `timezone` and `schedule`. Put `~/.local/bin` on your `PATH` if it is not already.

**Linux** (systemd user timer, catch-up after the machine was off):

```sh
codespaces-keepalive install systemd --apply
```

**macOS** (LaunchAgent, every 60s; `tick` applies `schedule`):

```sh
codespaces-keepalive install launchd --apply
```

**Either OS** (crontab = `schedule`):

```sh
codespaces-keepalive install cron --apply
```

`install` prints the unit or crontab by default; `--apply` writes it. Confirm with `codespaces-keepalive status`.

## Shape

```
schedule=0 7-17 * * 1-5     # 5-field crontab, in `timezone`

install cron     →  crontab fires at those times, tick --force
systemd/launchd  →  wake every minute, tick noops unless schedule matches
                     (silent skip; no GitHub calls)
```

On a match, `tick` starts a stopped codespace and SSHs a heartbeat so idle timeout resets.

Put the timer on a machine that is **already on** before work. A sleeping laptop will not fire cron/launchd.

## Config

```
mkdir -p ~/.config/codespaces-keepalive
cp config.example ~/.config/codespaces-keepalive/config
```

`KEY=value` (not sourced). `name` is the codespace from `gh codespace list`. `schedule` is a 5-field crontab expression:

```
minute  hour  day-of-month  month  weekday
```

All five fields must match (lists, ranges, steps, `*`, and weekday/month names). There is no Vixie "day-of-month OR weekday" quirk.

Example (2-hour idle policy → hourly is enough), weekdays 07:00–17:00:

```
schedule=0 7-17 * * 1-5
timezone=America/Chicago
```

`log_dir` defaults to `$XDG_STATE_HOME/codespaces-keepalive` (`~/.local/state/codespaces-keepalive`). Every run appends to `log_dir/keepalive.log`. `debug=true` (or `--debug`) adds schedule miss/match and `gh` traces to that file. `--log-dir DIR` overrides the directory for one run.

Without debug, cron/systemd/launchd stay quiet on stdout (not a tty), so cron will not mail you on a successful noop. Failures still go to stderr.

Other examples:

```
schedule=0 * * * 1-5          # every hour, weekdays, all day
schedule=0 7,12,17 * * 1-5    # 7am, noon, 5pm weekdays
schedule=0 8-18 * * mon-fri   # same idea with names
```

## Usage

```sh
codespaces-keepalive status
codespaces-keepalive tick --dry-run
codespaces-keepalive tick --force    # ignore schedule
codespaces-keepalive tick --debug --log-dir /tmp/cs-keep
```

## What `tick` does

1. If `schedule` does not match now in `timezone`, exit 0 (unless `--force`).
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
    schedule = "0 7-17 * * 1-5";
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
