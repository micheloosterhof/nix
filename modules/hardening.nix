# ABOUTME: Kernel security hardening for the VM guests (sysctls, boot params, a
# ABOUTME: module blacklist). Adapted from bivsk/nix-iv, which credits NotAShelf/nyx.
#
# Contributes to the vm and server aggregates, so it lands on fusion/utm/apple-vm
# and helium/nitrogen but not on darwin. The upstream's module.sig_enforce /
# lockdown=confidentiality / lsm= / rootflags settings are deliberately omitted —
# see the notes below.
{ ... }:
let
  hardening =
    { config, lib, ... }:
    {
      boot.kernel.sysctl = {
        # The Magic SysRq key lets a console user run low-level kernel commands;
        # we don't need it and it's a security concern.
        "kernel.sysrq" = 0;

        # Hide kernel pointers even from processes with CAP_SYSLOG.
        "kernel.kptr_restrict" = 2;

        # eBPF hardening that keeps the JIT (so tailscale/docker/tor stay fast,
        # unlike disabling it): block the unprivileged bpf() syscall entirely —
        # everything we run uses BPF as root — and constant-blind JITed programs
        # against spray attacks.
        "kernel.unprivileged_bpf_disabled" = true;
        "net.core.bpf_jit_harden" = 2;

        # Disable ftrace debugging.
        "kernel.ftrace_enabled" = false;

        # Keep kernel memory addresses out of dmesg.
        "kernel.dmesg_restrict" = 1;

        # Prevent unintended fifo / regular-file writes in world-writable dirs.
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;

        # Disable SUID binary core dumps.
        "fs.suid_dumpable" = 0;

        # Disallow perf profiling without CAP_SYS_ADMIN.
        "kernel.perf_event_paranoid" = 3;

        # Network hardening. Ignore ICMP redirects (MITM route injection) and
        # don't send them (we're not a router); log packets with impossible
        # source addresses. Reverse-path filtering is deliberately left to the
        # firewall's checkReversePath — a strict kernel rp_filter here would
        # break tailscale/wireguard on asymmetric paths.
        "net.ipv4.conf.all.accept_redirects" = false;
        "net.ipv4.conf.default.accept_redirects" = false;
        "net.ipv6.conf.all.accept_redirects" = false;
        "net.ipv6.conf.default.accept_redirects" = false;
        "net.ipv4.conf.all.send_redirects" = false;
        "net.ipv4.conf.default.send_redirects" = false;
        "net.ipv4.conf.all.log_martians" = true;
        "net.ipv4.conf.default.log_martians" = true;
      };

      boot.kernelParams = [
        # Make stack-based attacks on the kernel harder.
        "randomize_kstack_offset=on"

        # Break really old binaries rather than keep the legacy vsyscall table.
        "vsyscall=none"

        # Reduce a heap attack's exposure to a single cache; don't merge slabs.
        "slab_nomerge"

        # Buddy-allocator free poisoning.
        "page_poison=1"

        # Shuffle the free lists — less predictable page allocation.
        "page_alloc.shuffle=1"

        # Keep SysRq disabled (matches the sysctl above).
        "sysrq_always_enabled=0"

        # Don't let the kernel blank the framebuffer out from under plymouth.
        "fbcon=nodefer"

        # Deliberately NOT taken from the upstream list, because they break a
        # stock NixOS VM:
        #   module.sig_enforce=1 / lockdown=confidentiality
        #     — both require signed kernel modules; NixOS doesn't sign them, so
        #       virtio/vmwgfx/uinput/overlay would fail to load. Needs a
        #       module-signing setup before it can be enabled.
        #   lsm=landlock,lockdown,yama,integrity,apparmor,bpf,tomoyo,selinux
        #     — forces LSMs with no matching NixOS policy; left to NixOS defaults.
        #   rootflags=noatime
        #     — redundant; set it per-filesystem if wanted.
      ];

      # sshd is key-only already (vm.nix); also forbid keyboard-interactive auth
      # and restrict login to the one real user.
      services.openssh.settings = {
        KbdInteractiveAuthentication = false;
        AllowUsers = [ "mich" ];
      };

      # Only wheel-group users may sudo, even if a sudoers entry says otherwise.
      security.sudo.execWheelOnly = true;

      # Don't let the boot menu edit the kernel command line — that's a path to a
      # root shell from console access. Selecting boot entries (incl. the sway
      # specialisation) still works.
      boot.loader.systemd-boot.editor = lib.mkIf config.boot.loader.systemd-boot.enable false;

      # Unload attack surface we never use on these VMs.
      boot.blacklistedKernelModules = [
        # Obscure network protocols.
        "af_802154" # IEEE 802.15.4
        "appletalk" # Appletalk
        "atm" # ATM
        "ax25" # Amateur X.25
        "can" # Controller Area Network
        "dccp" # Datagram Congestion Control Protocol
        "decnet" # DECnet
        "econet" # Econet
        "ipx" # Internetwork Packet Exchange
        "n-hdlc" # High-level Data Link Control
        "netrom" # NetRom
        "p8022" # IEEE 802.3
        "p8023" # Novell raw IEEE 802.3
        "psnap" # Subnetwork Access Protocol
        "rds" # Reliable Datagram Sockets
        "rose" # ROSE
        "sctp" # Stream Control Transmission Protocol
        "tipc" # Transparent Inter-Process Communication
        "x25" # X.25

        # Rare or insufficiently audited filesystems. overlay (docker) and the
        # fuse-based vmhgfs (/host) are intentionally NOT here.
        "adfs"
        "affs"
        "befs"
        "bfs"
        "cifs"
        "cramfs"
        "efs"
        "erofs"
        "exofs"
        "f2fs"
        "freevxfs"
        "gfs2"
        "hfs"
        "hfsplus"
        "hpfs"
        "jffs2"
        "jfs"
        "ksmbd"
        "minix"
        "nfs"
        "nfsv3"
        "nfsv4"
        "nilfs2"
        "omfs"
        "qnx4"
        "qnx6"
        "squashfs" # NOTE: also blocks mounting AppImages (they're squashfs).
        "sysv"
        "udf"
        "vivid" # Virtual Video Test Driver

        # Block DMA-attack transports (absent in these VMs anyway).
        "firewire-core"
        "thunderbolt"
      ];
    };
in
{
  flake.modules.nixos.vm = hardening;
  flake.modules.nixos.server = hardening;
}
