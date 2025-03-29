{
    pkgs,
    pkgsUnstable,
    ...
};

{
    home = {
        username = "armleth";
        homeDirectory = "/home/armleth";

        packages = with pkgs; [
            neofetch
            ripgrep
        ];
    };

    programs = {
        git = {
            enable = true;
            userName = "Armleth";
            userEmail = "armleth@proton.me"
        };

        bash = {
            enable = true;
            shellAliases = {
                rebuild = "sudo nixos-rebuild switch --flake ~/tmp_infra/.";
                vim = "nvim";
                gst = "git status";
            };
        };
    };

    # home.stateVersion = "24.11";
    programs.home-manager.enable = true;
}
