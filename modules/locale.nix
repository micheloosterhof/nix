# ABOUTME: en_US.UTF-8 locale, built with only that locale, on every Linux
# ABOUTME: target: VMs, servers and the container image.
{ ... }:
let
  shared = {
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
    # en_US alone means 12-hour AM/PM timestamps; C.UTF-8 (always built into
    # glibc) switches date/time rendering to 24-hour without another locale.
    i18n.extraLocaleSettings.LC_TIME = "C.UTF-8";
  };
in
{
  flake.modules.nixos.vm = shared;
  flake.modules.nixos.server = shared;
  flake.modules.nixos.container = shared;
}
