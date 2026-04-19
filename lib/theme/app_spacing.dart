/// Spacing, sizing, and radius design tokens for AI VaultIO.
///
/// Use these constants instead of raw numbers throughout the UI to keep
/// rhythm consistent and make global tweaks trivial.
abstract final class AppSpacing {
  // ── Base spacing scale ────────────────────────────────────────────
  static const double px2  = 2;
  static const double px4  = 4;
  static const double px6  = 6;
  static const double px8  = 8;
  static const double px10 = 10;
  static const double px12 = 12;
  static const double px14 = 14;
  static const double px16 = 16;
  static const double px20 = 20;
  static const double px24 = 24;
  static const double px32 = 32;
  static const double px40 = 40;
  static const double px48 = 48;

  // ── Layout dimensions ─────────────────────────────────────────────
  static const double sidebarWidth    = 220;
  static const double appBarHeight    = 52;
  static const double contentPadding  = 24;

  // ── Border radii ──────────────────────────────────────────────────
  static const double radiusSm  = 4;   // chips, badges, tooltips
  static const double radiusMd  = 6;   // buttons, inputs, nav items
  static const double radiusLg  = 8;   // cards, modals
  static const double radiusXl  = 12;  // dialogs, panels
  static const double radiusXxl = 16;  // large containers

  // ── Icon sizes ────────────────────────────────────────────────────
  static const double iconXs  = 12;
  static const double iconSm  = 14;
  static const double iconMd  = 16;
  static const double iconLg  = 20;
  static const double iconXl  = 24;

  // ── Interactive element heights ───────────────────────────────────
  static const double buttonHeightSm = 30;
  static const double buttonHeightMd = 36;
  static const double buttonHeightLg = 42;
}
