{ config, lib, pkgs, ... }:

let
  cfg = config.services.codespaces-keepalive;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalString
    types;

  configText = ''
    name=${cfg.codespaceName}
    timezone=${cfg.timezone}
    schedule=${cfg.schedule}
    start_timeout_seconds=${toString cfg.startTimeoutSeconds}
    heartbeat_command=${cfg.heartbeatCommand}
    debug=${if cfg.debug then "true" else "false"}
    ${optionalString (cfg.logDir != null) "log_dir=${cfg.logDir}"}
  '';
in
{
  options.services.codespaces-keepalive = {
    enable = mkEnableOption "scheduled GitHub Codespaces keepalive";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "codespaces-keepalive package (wraps the script with gh on PATH).";
    };

    codespaceName = mkOption {
      type = types.str;
      example = "fuzzy-adventure-xxxxx";
      description = "Codespace name from `gh codespace list`.";
    };

    timezone = mkOption {
      type = types.str;
      default = "America/Chicago";
      description = "IANA timezone used to evaluate `schedule`.";
    };

    schedule = mkOption {
      type = types.str;
      default = "0 7-17 * * 1-5";
      description = "5-field crontab expression (minute hour dom month weekday).";
    };

    startTimeoutSeconds = mkOption {
      type = types.ints.positive;
      default = 300;
      description = "Seconds to wait after start for the codespace to become Available.";
    };

    heartbeatCommand = mkOption {
      type = types.str;
      default = "true";
      description = "Remote command run over `gh codespace ssh` to record activity.";
    };

    logDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "~/.local/state/codespaces-keepalive";
      description = "Directory for keepalive.log. Null uses the script default (XDG_STATE_HOME).";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Write schedule/gh traces to the log file.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.codespaceName != "";
          message = "services.codespaces-keepalive.codespaceName must be set (see `gh codespace list`).";
        }
      ];

      home.packages = [ cfg.package ];

      xdg.configFile."codespaces-keepalive/config".text = configText;
    }

    (mkIf pkgs.stdenv.isLinux {
      systemd.user.services.codespaces-keepalive = {
        Unit = {
          Description = "GitHub Codespaces scheduled keepalive tick";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          # Wrapped package already prefixes gh/coreutils; this covers a bare script too.
          Environment = "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gh pkgs.gnused ]}";
          ExecStart = "${lib.getExe cfg.package} tick${optionalString cfg.debug " --debug"}";
        };
      };

      systemd.user.timers.codespaces-keepalive = {
        Unit.Description = "GitHub Codespaces scheduled keepalive";
        Timer = {
          OnCalendar = "minutely";
          Persistent = true;
          AccuracySec = "1s";
          Unit = "codespaces-keepalive.service";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })

    (mkIf pkgs.stdenv.isDarwin {
      launchd.agents.codespaces-keepalive = {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe cfg.package)
            "tick"
          ] ++ lib.optionals cfg.debug [ "--debug" ];
          StartInterval = 60;
          RunAtLoad = true;
          EnvironmentVariables.PATH = lib.makeBinPath [
            pkgs.coreutils
            pkgs.gh
            pkgs.gnused
          ];
          StandardOutPath = "${config.home.homeDirectory}/.local/state/codespaces-keepalive/launchd.stdout.log";
          StandardErrorPath = "${config.home.homeDirectory}/.local/state/codespaces-keepalive/launchd.stderr.log";
        };
      };
    })
  ]);
}
