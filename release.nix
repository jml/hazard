/* Build instructions for Hydra
 *
 * Can test these out without Hydra using:
 *
 *   $ nix-build release.nix -A build
 *
 * Which will build the binary in a local 'result' directory. The binary will
 * contain executable, documentation, and libraries.
 */

{ havererSrc ? ../haverer ,
  hazardSrc ? ./. }:

let
  pkgs = import <nixpkgs> {};

  jobs = rec {

    build = { system ? builtins.currentSystem }:
      let
        pkgs = import <nixpkgs> { inherit system; };
        modifiedHaskellPackages = pkgs.haskellngPackages.override {
          overrides = self: super: {
            haverer = self.callPackage havererSrc {};
            hazard = self.callPackage hazardSrc {};
          };
        };
      in modifiedHaskellPackages.hazard;

  };

in
  jobs
