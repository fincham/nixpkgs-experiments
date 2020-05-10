{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.powerdns;
  configDir = pkgs.writeTextDir "pdns.conf" "${cfg.extraConfig}";
in {
  disabledModules = [ "services/networking/powerdns.nix" ];

  options = {
    services.powerdns = {
      enable = mkEnableOption "PowerDNS Authoritative Server";

      extraConfig = mkOption {
        type = types.lines;
        default = "launch=bind";
        description = ''
          Extra lines to be added verbatim to pdns.conf.
        '';
      };
    };
  };

  config = mkIf config.services.powerdns.enable {
    systemd.services.pdns = {
      unitConfig.Documentation = "man:pdns_server(1) man:pdns_control(1) man:pdnsutil(1)";
      description = "PowerDNS Authoritative Server";
      wantedBy = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "mysqld.service" "postgresql.service" "slapd.service" "mariadb.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.powerdns}/bin/pdns_server --guardian=no --daemon=no --disable-syslog --log-timestamp=no --socket-dir=/run --write-pid=no --config-dir=${configDir}";
        Type = "notify";
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
  };
}
