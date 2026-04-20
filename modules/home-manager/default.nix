{
    pkgs,
    pkgsUnstable,
    ...
}:

{
    home = {
        username = "armleth";
        homeDirectory = "/home/armleth";

        packages = with pkgs; [
            neofetch
            ripgrep
            fzf
            eza 
            dwt1-shell-color-scripts
            nixd
        ];
    };

    programs = {
        git = {
            enable = true;
            userName = "Armleth";
            userEmail = "armleth@proton.me";
        };

        bash = {
            enable = true;
            shellAliases = {
                rebuild = "sudo nixos-rebuild switch --flake ~/tmp_infra/.";
                vim = "nvim";
                gst = "git status";
                ls = "eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first";
                tree = "eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first --tree";
            };
        };
    };

    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
}
