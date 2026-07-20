# ABOUTME: Drop inbound traffic from bogon (unallocated/reserved) source
# ABOUTME: networks, using team-cymru's fullbogons lists refreshed every 4h.
#
# Ported from a Debian bogons-update setup, done natively in nftables: a named
# interval set per family, dropped early by a dedicated input chain, and
# refreshed by a systemd timer via an atomic `nft -f` transaction — so a failed
# download leaves the working set in place (never breaks the firewall).
{ ... }:
{
  flake.modules.nixos.bogons =
    { pkgs, ... }:
    {
      networking.nftables.enable = true;

      networking.nftables.tables.bogons = {
        family = "inet";
        content = ''
          set bogons4 {
            type ipv4_addr
            flags interval
            auto-merge
          }
          set bogons6 {
            type ipv6_addr
            flags interval
            auto-merge
          }

          # Runs before the main firewall (priority filter - 10). policy accept,
          # so only bogon sources are dropped; everything else falls through.
          chain input {
            type filter hook input priority filter - 10; policy accept;
            ip saddr @bogons4 drop
            ip6 saddr @bogons6 drop
          }
        '';
      };

      systemd.services.bogons-update = {
        description = "Refresh team-cymru bogon nftables sets";
        after = [
          "network-online.target"
          "nftables.service"
        ];
        wants = [ "network-online.target" ];
        path = with pkgs; [
          nftables
          curl
          gnugrep
          coreutils
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail

          update() {
            name="$1"; url="$2"
            tmp="$(mktemp)"
            # Keep the existing set if the download fails — never break the firewall.
            if ! curl -sSf --max-time 120 -o "$tmp" "$url"; then
              echo "bogons: download failed for $name, keeping existing set" >&2
              rm -f "$tmp"
              return 0
            fi
            elems="$(grep -E '^[0-9a-fA-F:.]+/[0-9]+' "$tmp" | paste -sd, -)"
            nftfile="$(mktemp)"
            {
              echo "flush set inet bogons $name"
              if [ -n "$elems" ]; then
                echo "add element inet bogons $name { $elems }"
              fi
            } > "$nftfile"
            # One atomic transaction: if it can't apply, the old set stays.
            nft -f "$nftfile"
            rm -f "$tmp" "$nftfile"
          }

          update bogons4 https://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt
          update bogons6 https://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt
        '';
      };

      systemd.timers.bogons-update = {
        description = "Periodic bogon set refresh";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "4h"; # matches the 14400s staletime
          Persistent = true;
        };
      };
    };
}
