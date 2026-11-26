{
  description = "bc250: installed system + unattended USB installer";

  inputs = {
    bc250-nixos.url = "github:n3oney/bc250-nixos";
    # Same nixpkgs the board was validated against (pinned kernel, Mesa 26)
    nixpkgs.follows = "bc250-nixos/nixpkgs";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Only used as a source of individual modules (ACPI fix), not as a flake
    bc250-tess = {
      url = "github:TesseractCat/bc250-nixos";
      flake = false;
    };
    # filippor's governor, memory-profile branch, pinned to the tested commit
    csg-src = {
      url = "github:filippor/cyan-skillfish-governor/b770314301753c07957c6fc9359b3c7d54283c4d";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, bc250-nixos, disko, bc250-tess, csg-src, ... }:
    let
      system = "x86_64-linux";
    in
    {
      # The system that ends up on the NVMe
      nixosConfigurations.bc250 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          bc250-nixos.nixosModules.default
          bc250-nixos.nixosModules.gpu-vulkan
          bc250-nixos.nixosModules.arieltune-tune
          bc250-nixos.nixosModules.llama-vulkan
          ./disko.nix
          ./hardware.nix
          ./configuration.nix
          # llama.cpp + llmtune packages from the bc250-nixos flake
          {
            bc250.llamaVulkan.package = bc250-nixos.packages.${system}.llamaVulkan;
            bc250.llamaVulkan.llmtunePackage = bc250-nixos.packages.${system}.llmtune;
          }
          # From TesseractCat: ACPI fix (CPU idle + frequency scaling) and the
          # SMU GPU governor module, running filippor's memory-profile branch
          # (GPU clock + voltage AND memory/fabric clocks follow load)
          ({ pkgs, ... }: {
            imports = [
              "${bc250-tess}/bc250-acpi-fix/module.nix"
              "${bc250-tess}/cyan-skillfish-governor-smu/module.nix"
              "${bc250-tess}/bc250-core-unlock/module.nix"
            ];
            services.bc250-acpi-fix.enable = true;
            # 6c/12t -> 8c/16t; runs in the (systemd) initrd, adds one reboot per cold boot.
            # Skip once with the kernel parameter bc250.nocoreunlock
            boot.initrd.systemd.enable = true;
            #services.bc250-core-unlock.enable = true; is now a variable in private.nix
            services.cyan-skillfish-governor-smu = {
              enable = true;
            # Governor package adapted from TesseractCat/bc250-nixos
            # (cyan-skillfish-governor-smu/package.nix, MIT License, Copyright (c) 2026 TesseractCat)
              package = pkgs.rustPlatform.buildRustPackage {
                pname = "cyan-skillfish-governor-smu";
                version = "memory-profile-b770314";
                src = csg-src;
                cargoLock.lockFile = "${csg-src}/Cargo.lock";
                nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
                buildInputs = with pkgs; [ libdrm dbus ];
                doCheck = false;
                postInstall = ''
                  wrapProgram "$out/bin/cyan-skillfish-governor-smu" \
                    --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.util-linux pkgs.dbus ]}
                  install -Dm644 com.cyanskillfish.Governor.conf \
                    "$out/share/dbus-1/system.d/com.cyanskillfish.Governor.conf"
                '';
                meta.mainProgram = "cyan-skillfish-governor-smu";
              };
              # The branch's own default config (has the memory-fabric-profile
              # section); overrides go in configuration.nix (settings)
              configFile = "${csg-src}/default-config.toml";
            };
          })
        ];
      };

      # USB stick: boots, wipes the NVMe, installs the system above, powers off
      nixosConfigurations.autoinstaller = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { target = self.nixosConfigurations.bc250; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./autoinstall.nix
        ];
      };

      packages.${system} = {
        autoinstallIso = self.nixosConfigurations.autoinstaller.config.system.build.isoImage;
        default = self.packages.${system}.autoinstallIso;
      };
    };
}
