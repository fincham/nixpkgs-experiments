{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.powerdns;

  socketDir = "/run";
  configDir = pkgs.writeTextDir "pdns.conf" (generators.toKeyValue { } cfg.config + optionalString (cfg.extraConfig != null) cfg.extraConfig);
  
  powerdns-cli-wrappers = pkgs.stdenv.mkDerivation { 
    name = "powerdns-cli-wrappers"; 
    buildInputs = [ pkgs.makeWrapper ]; 
    buildCommand = '' 
      mkdir -p $out/bin 
      makeWrapper ${cfg.package}/bin/pdnsutil "$out/bin/pdnsutil" --add-flags "--config-dir=${configDir}"
      makeWrapper ${cfg.package}/bin/pdns_control "$out/bin/pdns_control" --add-flags "--config-dir=${configDir} --socket-dir=${socketDir}" 
    ''; 
  };

in {
  disabledModules = [ "services/networking/powerdns.nix" ];

  options = {
    services.powerdns = {
      enable = mkEnableOption "PowerDNS Authoritative Server";

      package = mkOption {
        type = types.package;
        default = pkgs.powerdns;
        defaultText = "pkgs.powerdns";
        description = "Which PowerDNS package to use";
      };


      user = mkOption {
        default = "pdns";
        description = "UID which pdns_server will switch to after starting";
      };

      group = mkOption {
        default = "pdns";
        description = "GID which pdns_server will switch to after starting";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of additional command line paramters for pdns_server";
      };

      extraConfig = mkOption {
        type = with types; nullOr lines;
        default = null;
        description = "Extra lines to be added verbatim to pdns.conf";
      };
      
      config = mkOption {
        type = with types; attrsOf (oneOf [ bool int str ]);
        # to allow pre-"config" installations to still function, if extraConfig is set
        # then specify no default config here
        default = if cfg.extraConfig != null then {} else {
          launch = "bind";
        };
        example = {
          launch = "gsqlite3";
          gsqlite3-database = "/srv/dns/powerdns.sqlite3";
          gsqlite3-dnssec = true;
        };
        description = "Configuration for pdns_server";
      };
    };
  };

  config = mkIf config.services.powerdns.enable {
    warnings = optional (cfg.extraConfig != null) "services.powerdns.`extraConfig` is deprecated, please use services.powerdns.`config`.";

    users.users.pdns = {
      isSystemUser = true;
      group = "pdns";
      description = "PowerDNS daemon user";
    };

    users.groups.pdns.gid = null;

    # preferably this should be "type=notify" to better match upstream, but this is not currently reliable on NixOS
    systemd.services.pdns = {
      unitConfig.Documentation = "man:pdns_server(1) man:pdns_control(1) man:pdnsutil(1)";
      description = "PowerDNS Authoritative Server";
      wantedBy = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "mysqld.service" "postgresql.service" "slapd.service" "mariadb.service" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/pdns_server --setuid=${cfg.user} --setgid=${cfg.group} --guardian=no --daemon=no --disable-syslog --log-timestamp=no --write-pid=no --socket-dir=${socketDir} --config-dir=${configDir} ${concatStringsSep " " cfg.extraArgs}";
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "1";
        StartLimitInterval = "0";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE CAP_SETGID CAP_SETUID CAP_CHOWN CAP_SYS_CHROOT";
        LockPersonality = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "full";
        RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "~ @clock @debug @module @mount @raw-io @reboot @swap @cpu-emulation @obsolete";
        PrivateDevices = true;
        NoNewPrivileges = true; 
      };
    };
    
    environment.systemPackages = [ powerdns-cli-wrappers ];
  };

}
