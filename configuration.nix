{ config, lib, pkgs, ... }:

{
    imports =
        [
        ./hardware-configuration.nix
        ];

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Enable Intel RAPL so /sys/class/powercap/intel-rapl/ is exposed,
    # which Scaphandre reads to report electrical power consumption.
    boot.kernelModules = [ "intel_rapl_common" "intel_rapl_msr" ];

    # Memory / swap tuning. The node only has ~7.5 GiB of RAM for the
    # full K3s + ArgoCD + monitoring + media + auth stack, so it sits
    # near saturation. With the kernel default vm.swappiness=60 the VM
    # spent ~36% of its time stalled on swap I/O (PSI io.full), which in
    # turn made kubelet miss heartbeats and the CNPG operator lose its
    # leader-election lease (5 s API timeout), causing thousands of
    # spurious restarts across the cluster.
    #
    # vm.swappiness=10 follows the Kubernetes community recommendation
    # for nodes that still keep swap as a safety net: prefer dropping
    # file-cache before touching anonymous pages. The cache-pressure
    # and dirty knobs are tightened too so writeback never accumulates
    # enough dirty pages to stall the whole VM at once.
    boot.kernel.sysctl = {
        "vm.swappiness" = 10;
        "vm.vfs_cache_pressure" = 50;
        "vm.dirty_ratio" = 10;
        "vm.dirty_background_ratio" = 5;
    };

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
                UseDns = false;
                X11Forwarding = false;
                PermitRootLogin = "prohibit-password";
            };
        };
    };

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "24.11"; # Nixos version when this system was installed
}

