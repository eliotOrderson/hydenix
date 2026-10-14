{
  inputs,
}:

let
  system = "x86_64-linux";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  # Function to create Hyde package with specific source
  mkHyde =
    src:
    import ../../hydenix/sources/hyde.nix {
      inherit pkgs;
      inputs = inputs // {
        hyde = src;
      };
    };

  # Current pinned Hyde version
  hyde-pinned = mkHyde inputs.hyde;

  # The upstream master snapshot this comparison runs against, named by revision.
  #
  # It used to be `rev = "master"` carrying the hash of a 2025-10-29 revision. A branch name cannot
  # carry a hash: Nix resolves "master" to whatever it points at when the fetch runs, compares that
  # tree against the hash, and fails on the first difference — which is every commit upstream makes.
  # The old pairing built here only because that revision's source was already in the store, so the
  # fetch never ran; on a machine without it the package does not build at all, and the one tool
  # that previews an update is unusable exactly where it is needed.
  #
  # Refresh both together; the hash is that revision's tree and nothing else:
  #   rev=$(git ls-remote https://github.com/HyDE-Project/HyDE refs/heads/master | cut -f1)
  #   nix store prefetch-file --unpack --json \
  #     "https://github.com/HyDE-Project/HyDE/archive/$rev.tar.gz" | jq -r .hash
  hyde-master = mkHyde (
    pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "fa2fd57afc7203b1b5653d3271f3a57ea3873f97";
      sha256 = "sha256-/9oT3c60hZQtVdfbZWWUFo7GeU0pHQOWwhfsFELMoNE=";
    }
  );
in
pkgs.writeShellApplication {
  name = "hyde-update";
  runtimeInputs = with pkgs; [
    coreutils
    diffutils
  ];
  # Pass the built packages to the script
  text = ''
    export HYDE_PINNED="${hyde-pinned}"
    export HYDE_MASTER="${hyde-master}"
    ${builtins.readFile ./run.sh}
  '';
}
