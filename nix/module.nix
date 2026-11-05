# `programs.gridcraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME defaults for the whole system. NixOS cannot write per-user files, so it never
# writes `settings`.
#
# The overlay is `settings.override.json` beside `prefs.json` (`apps/gridcraft/src/main.rs`),
# merged over the saved preferences at start-up. GridCraft never writes it, so the declarative
# values survive a normal save. `ui.json` (window and docking state) is deliberately not frozen.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  gridcraftPackage ? pkgs.gridcraft,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.gridcraft;

  jsonFormat = pkgs.formats.json { };

  # The same list as `packaging/linux/ai.storyteller.gridcraft.desktop` (`MimeType=`).
  mimeTypes = [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.ms-excel.sheet.macroEnabled.12"
    "application/vnd.ms-excel.sheet.binary.macroEnabled.12"
    "application/vnd.oasis.opendocument.spreadsheet"
    "text/csv"
    "text/tab-separated-values"
  ];

  desktopFile = "ai.storyteller.gridcraft.desktop";

  # The per-user settings directory: `$XDG_CONFIG_HOME/gridcraft` on Linux.
  settingsDir = "${config.xdg.configHome}/gridcraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.gridcraft = {
    enable = mkEnableOption "GridCraft";

    package = mkOption {
      type = types.package;
      default = gridcraftPackage;
      defaultText = lib.literalMD "the `gridcraft` package of this flake";
      description = "The GridCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open the workbook, spreadsheet and tabular formats GridCraft handles with it by default
        (the MIME types of `packaging/linux/ai.storyteller.gridcraft.desktop`).
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `settings.override.json`; NixOS ignores them, because it cannot write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE`. Inert until theming support
        lands.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "gridcraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
