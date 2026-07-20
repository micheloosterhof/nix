# ABOUTME: Apple Virtualization.framework guest ("container machine"): a headless
# ABOUTME: virtio NixOS VM. GUI is forced off; this is a command-line-only target.
#
# UNVALIDATED: authored without a boot test. It evaluates cleanly, but the exact
# Virtualization.framework guest requirements (EFI vs direct kernel boot, the
# virtio module set) have not been confirmed on real hardware. Treat the virtio
# list and console settings as a first cut to verify on first boot.
{ ... }:
{
  flake.modules.nixos.apple-vm =
    { lib, ... }:
    {
      # This is a terminal-only platform: no Xorg/Wayland regardless of profile.
      my.gui.enable = lib.mkForce false;

      # aarch64 guests trip nixpkgs' platform-support assertions for some packages
      # that nonetheless build and run fine, matching the other aarch64 VMs.
      nixpkgs.config.allowUnsupportedSystem = true;

      # Apple's VM exposes the console as a virtio console (hvc0); put the kernel
      # log and a login getty there. (The virtio initrd modules live in the
      # host's hardware file.)
      boot.kernelParams = [ "console=hvc0" ];
    };
}
