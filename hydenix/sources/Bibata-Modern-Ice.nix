{
  lib,
  stdenv,
  pkgs,
}:

stdenv.mkDerivation {
  pname = "Bibata-Modern-Ice";
  version = "1.0.0";

  src = pkgs.fetchurl {
    url = "https://github.com/HyDE-Project/HyDE/raw/be97b8b4db232bfffc9b74fd27ba90a3457b9354/Source/arcs/Cursor_BibataIce.tar.gz";
    sha256 = "sha256-pYvIxOZ3jvcLrv4bDYPc0FPkPLydyWwltFLCZ7aILaQ=";
  };

  nativeBuildInputs = with pkgs; [
    jdupes
  ];

  installPhase = ''
    mkdir -p $out/share/icons/
    tar -xf $src -C $out/share/icons/
    jdupes --recurse $out/share/icons/
  '';

  meta = {
    description = "Bibata Modern Ice cursor theme";
    homepage = "https://github.com/HyDE-Project/HyDE";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.all;
    maintainers = [ ];
  };
}
