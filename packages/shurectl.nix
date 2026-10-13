# ABOUTME: shurectl, a terminal UI for Shure USB microphones (MV7, MVX2U, MV6),
# ABOUTME: in nixpkgs callPackage form so it can be bumped or upstreamed as is.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "shurectl";
  version = "2.11.0";

  src = fetchFromGitHub {
    owner = "Humblemonk";
    repo = "shurectl";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7/Mp94ruJyLw2vXXodNz6nZ94vR2X7pDnRYY2EsGfgk=";
  };

  cargoHash = "sha256-uYVlu4swSb0XSsxfWYMUVUjMozgOGBdt1Ft2dm4X+IA=";

  # hidapi talks to IOKit and cpal to CoreAudio, both part of the stdenv
  # SDK; a Linux build would add pkg-config, alsa-lib and udev.
  meta = {
    description = "Terminal UI configurator for Shure USB audio interfaces and microphones";
    homepage = "https://github.com/Humblemonk/shurectl";
    license = lib.licenses.gpl3Only;
    mainProgram = "shurectl";
    platforms = lib.platforms.darwin;
  };
})
