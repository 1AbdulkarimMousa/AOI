# Design System

## Theme

Warm, paper-like light surfaces for daytime research operations, with a complete dark theme for lower-light work. The interface uses restrained color: orange for primary action, teal for verified progress, blue for information, rose for risk, gold for rewards, and purple for secondary analytical series.

## Color

Source tokens live in `src/css/aoi.css`. Use tinted warm neutrals rather than pure black or white. Semantic colors must pair text or symbols with color so state remains legible without color perception.

## Typography

Geist Sans with Noto Sans SC and system fallbacks. Use compact product hierarchy, tabular alignment for metrics, and 65 to 75 character line lengths for prose.

## Components

Use the existing button, panel, status badge, form control, table row, drawer, notice, progress, and navigation vocabulary. Every interactive control needs visible hover, focus, disabled, loading, and error states. Avoid nested decorative cards and modal-first workflows.

## Layout

The persistent sidebar and top bar frame a responsive content area. Collection forms use a stable left workflow rail and one focused form surface. Analysis uses layer tabs, a horizontally scrollable comparison table, review rows, and a separate decision area. Mobile layouts collapse navigation and stack form actions without shrinking tap targets.

## Motion

Use 150 to 250 millisecond state transitions only. Respect `prefers-reduced-motion`; do not animate layout properties or orchestrate page-load sequences.
