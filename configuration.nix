{ config, lib, pkgs, ... }:

{
    imports =
        [
        ./hardware-configuration.nix
        ];

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = "nixosVM";
    networking.networkmanager.enable = true;

    # Set your time zone.
    time.timeZone = "Europe/Paris";

    users.users.armleth = {
        isNormalUser = true;
        home = "/home/armleth";
        extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
    };

    environment.systemPackages = with pkgs; [
        neovim
        wget
        git
    ];

    networking.firewall.allowedTCPPorts = [
        6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    ];
    networking.firewall.allowedUDPPorts = [
# 8472 # k3s, flannel: required if using multi-node for inter-node networking
    ];

    services = {
        k3s = {
            enable = true;
            role = "server";
        };

        openssh = {
            enable = true;
            ports = [ 22 ];
            settings = {
                PasswordAuthentication = true;
                AllowUsers = null;
                UseDns = true;
                X11Forwarding = false;
                PermitRootLogin = "prohibit-password";
            };
        };
    };

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "24.11"; # Nixos version when this system was installed
}

