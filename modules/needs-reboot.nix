# ABOUTME: Print "reboot advised" when a switch activates a kernel, initrd,
# ABOUTME: or module set different from the one the system booted with.
{ ... }:
{
  flake.modules.nixos.base = {
    system.activationScripts.needsReboot = {
      text = ''
        if [ -e /run/booted-system ]; then
          for f in kernel initrd kernel-modules; do
            booted=$(readlink -f "/run/booted-system/$f" 2>/dev/null) || continue
            next=$(readlink -f "$systemConfig/$f" 2>/dev/null) || continue
            if [ "$booted" != "$next" ]; then
              echo "needs-reboot: $f differs from the booted system; reboot advised" >&2
              break
            fi
          done
        fi
      '';
    };
  };
}
