import 'package:flutter/material.dart';

/// Design token palette for AI VaultIO.
///
/// The sidebar is intentionally always dark to provide a stable visual
/// anchor regardless of the system light/dark preference.
/// The content area adapts via the Material 3 ColorScheme.
abstract final class AppColors {
  // ── Sidebar (always dark) ────────────────────────────────────────
  static const sidebarBg           = Color(0xFF0D1117); // near-black
  static const sidebarItemHover    = Color(0xFF1C2333); // subtle lift
  static const sidebarItemActive   = Color(0xFF1C2333); // same lift + accent icon
  static const sidebarBorder       = Color(0xFF21262D); // very subtle border
  static const sidebarText         = Color(0xFF8B949E); // muted label
  static const sidebarTextHover    = Color(0xFFCDD9E5); // brightens on hover
  static const sidebarTextActive   = Color(0xFFE6EDF3); // bright on select
  static const sidebarSectionLabel = Color(0xFF484F58); // section headers
  static const sidebarAccentIcon   = Color(0xFF58A6FF); // active icon color
  static const sidebarDivider      = Color(0xFF21262D);

  // ── Brand ────────────────────────────────────────────────────────
  static const brand50  = Color(0xFFEFF6FF);
  static const brand100 = Color(0xFFDBEAFE);
  static const brand200 = Color(0xFFBFDBFE);
  static const brand400 = Color(0xFF60A5FA);
  static const brand500 = Color(0xFF3B82F6);
  static const brand600 = Color(0xFF2563EB);
  static const brand700 = Color(0xFF1D4ED8);
  static const brand800 = Color(0xFF1E40AF);
  static const brand900 = Color(0xFF1E3A8A);

  // ── Neutrals (slate scale) ────────────────────────────────────────
  static const white     = Color(0xFFFFFFFF);
  static const slate50   = Color(0xFFF8FAFC);
  static const slate100  = Color(0xFFF1F5F9);
  static const slate200  = Color(0xFFE2E8F0);
  static const slate300  = Color(0xFFCBD5E1);
  static const slate400  = Color(0xFF94A3B8);
  static const slate500  = Color(0xFF64748B);
  static const slate600  = Color(0xFF475569);
  static const slate700  = Color(0xFF334155);
  static const slate800  = Color(0xFF1E293B);
  static const slate900  = Color(0xFF0F172A);
  static const slate950  = Color(0xFF020617);

  // ── Semantic ──────────────────────────────────────────────────────
  static const success        = Color(0xFF10B981);
  static const successSurface = Color(0xFFD1FAE5);
  static const warning        = Color(0xFFF59E0B);
  static const warningSurface = Color(0xFFFEF3C7);
  static const error          = Color(0xFFEF4444);
  static const errorSurface   = Color(0xFFFEE2E2);
  static const info           = Color(0xFF3B82F6);
  static const infoSurface    = Color(0xFFDBEAFE);

  // ── Light theme surfaces ─────────────────────────────────────────
  static const lightScaffold  = Color(0xFFF8FAFC); // outer page bg
  static const lightSurface   = Color(0xFFFFFFFF); // cards, app bars
  static const lightBorder    = Color(0xFFE2E8F0); // dividers, card outlines
  static const lightBorderSub = Color(0xFFF1F5F9); // subtler outlines

  // ── Dark theme surfaces ──────────────────────────────────────────
  static const darkScaffold   = Color(0xFF0D1117);
  static const darkSurface    = Color(0xFF161B22);
  static const darkBorder     = Color(0xFF21262D);
  static const darkBorderSub  = Color(0xFF30363D);
}
