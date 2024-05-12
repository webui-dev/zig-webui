{
  description = "For lua environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls-overlay.url = "github:zigtools/zls";
  };

  outputs = { self, nixpkgs, ... }@ inputs:
    let
      systems = [
        # "aarch64-linux"
        # "i686-linux"
        # "aarch64-darwin"
        # "x86_64-darwin"
        "x86_64-linux"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # This is for using nix direnv and flake develop environment
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              inputs.zig-overlay.overlays.default
              (final: prev: {
                zlspkgs = inputs.zls-overlay.packages.${system}.default;
              })
            ];
          };
        in
        {
          default =
            pkgs.mkShell {
              packages = with pkgs; [
                zigpkgs.default
                zls
                nodePackages.live-server
              ];
            };

          nightly =
            pkgs.mkShell {
              packages = with pkgs;[
                zigpkgs.master
                zlspkgs
                nodePackages.live-server
              ];
            };
        });
    };
}
