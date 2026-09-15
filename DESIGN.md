---
name: SnapBrief landing
description: One product mock in the app's charcoal skin, placed on three page grounds (light canon, charcoal continuity, ultramarine changelog)
colors:
  # Shared: the app's own material, identical in every variant (site/spec/product-mock.md, all three :root blocks)
  mock-shell: "#171A20"
  mock-card: "#242A33"
  mock-hover: "#303845"
  mock-border: "#39424E"
  mock-border-strong: "#46515F"
  mock-pill: "#2B3440"
  mock-overlay-blue: "#2F8CFF"
  mock-focus: "#7AB8FF"
  mock-text: "#EEF2F8"
  mock-text-secondary: "#BFC8D6"
  mock-icon: "#9AA7B8"
  mock-danger: "#FF9B95"
  mock-backdrop: "rgba(10,13,18,.55)"
  # Variant A: light canon (site/src/light.html)
  light-ground: "#FFFFFF"
  light-ground-alt: "#F5F6F8"
  light-ink: "#172033"
  light-muted: "#5E687A"
  light-line: "#DDE2EA"
  light-line-soft: "#E7EAF0"
  light-accent: "#315CF5"
  light-accent-deep: "#1E3FCB"
  light-accent-soft: "#E9EDFE"
  # Variant B: charcoal continuity (site/src/dark.html); panels, cards, borders and text reuse the mock-* tokens
  dark-ground: "#0B0E13"
  dark-accent-fill: "#1E6FE0"
  dark-accent-fill-hover: "#1A5FC9"
  # Variant C: ultramarine changelog (site/src/editorial.html)
  editorial-ultramarine: "#2038E6"
  editorial-ultramarine-hover: "#1A2FC4"
  editorial-ink: "#0B0F1A"
  editorial-paper: "#F2F3F5"
  editorial-rule: "#C9CDD6"
  editorial-ink-secondary: "#3D4A8A"
  editorial-on-blue-secondary: "rgba(255,255,255,.82)"
  editorial-badge-fill: "#1B5FD1"
typography:
  display-light:
    fontFamily: "Wix Madefor Display, Segoe UI, system-ui, sans-serif"
    fontSize: "clamp(30px, 8.6vw, 64px)"
    fontWeight: 700
    lineHeight: 1.06
    letterSpacing: "-0.025em"
  headline-light:
    fontFamily: "Wix Madefor Display, Segoe UI, system-ui, sans-serif"
    fontSize: "clamp(30px, 3.4vw, 46px)"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.025em"
  title-light:
    fontFamily: "Wix Madefor Display, Segoe UI, system-ui, sans-serif"
    fontSize: "16.5px"
    fontWeight: 700
    lineHeight: 1.1
  body-light:
    fontFamily: "Golos Text, Segoe UI, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.55
  display-dark:
    fontFamily: "Geologica, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(44px, 6vw, 72px)"
    fontWeight: 600
    lineHeight: 1.06
    letterSpacing: "-0.025em"
  headline-dark:
    fontFamily: "Geologica, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(30px, 3.4vw, 46px)"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.025em"
  title-dark:
    fontFamily: "Geologica, system-ui, -apple-system, sans-serif"
    fontSize: "19px"
    fontWeight: 600
    lineHeight: 1.1
  body-dark:
    fontFamily: "Onest, system-ui, -apple-system, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.55
  display-editorial:
    fontFamily: "Unbounded, system-ui, sans-serif"
    fontSize: "clamp(2.5rem, 4.6vw, 4.5rem)"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  headline-editorial:
    fontFamily: "Unbounded, system-ui, sans-serif"
    fontSize: "clamp(1.875rem, 3.4vw, 2.875rem)"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title-editorial:
    fontFamily: "Unbounded, system-ui, sans-serif"
    fontSize: "1.3rem"
    fontWeight: 600
    lineHeight: 1.1
  body-editorial:
    fontFamily: "Literata, Iowan Old Style, Georgia, serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.6
  label-mono:
    fontFamily: "JetBrains Mono, Cascadia Code, ui-monospace, monospace"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.7
rounded:
  light-sm: "8px"
  light-md: "10px"
  light-lg: "12px"
  dark-sm: "12px"
  dark-lg: "16px"
  editorial-sm: "2px"
  editorial-md: "3px"
  editorial-lg: "4px"
  mock-annotation: "4px"
  mock-chip: "10px"
  mock-toolbar: "12px"
  mock-stack: "16px"
  pill: "999px"
spacing:
  gutter-mobile: "16px"
  gutter-tablet: "24px"
  gutter: "32px"
  section-head-gap: "44px"
  grid-gap-tight: "24px"
  grid-gap: "32px"
  grid-gap-wide: "56px"
  section: "clamp(64px, 8vw, 112px)"
  nav-height: "64px"
  container: "1200px"
  container-editorial: "1320px"
components:
  button-primary-light:
    backgroundColor: "{colors.light-accent}"
    textColor: "#FFFFFF"
    typography: "{typography.body-light}"
    rounded: "{rounded.light-md}"
    padding: "14px 24px"
  button-primary-light-hover:
    backgroundColor: "{colors.light-accent-deep}"
  button-secondary-light:
    backgroundColor: "transparent"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.light-md}"
    padding: "14px 24px"
  button-primary-dark:
    backgroundColor: "{colors.dark-accent-fill}"
    textColor: "#FFFFFF"
    typography: "{typography.body-dark}"
    rounded: "{rounded.dark-sm}"
    padding: "0 24px"
    height: "48px"
  button-primary-dark-hover:
    backgroundColor: "{colors.dark-accent-fill-hover}"
  button-secondary-dark:
    backgroundColor: "transparent"
    textColor: "{colors.mock-text}"
    rounded: "{rounded.dark-sm}"
    padding: "0 24px"
    height: "48px"
  button-white-editorial:
    backgroundColor: "#FFFFFF"
    textColor: "{colors.editorial-ink}"
    typography: "{typography.body-editorial}"
    rounded: "{rounded.editorial-lg}"
    padding: ".85em 1.5em"
  button-ultramarine-editorial:
    backgroundColor: "{colors.editorial-ultramarine}"
    textColor: "#FFFFFF"
    rounded: "{rounded.editorial-lg}"
    padding: ".85em 1.5em"
  button-ultramarine-editorial-hover:
    backgroundColor: "{colors.editorial-ultramarine-hover}"
  chip-works-with-light:
    backgroundColor: "{colors.light-ground}"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.pill}"
    padding: "8px 16px"
  chip-works-with-dark:
    backgroundColor: "{colors.mock-shell}"
    textColor: "{colors.mock-text}"
    rounded: "{rounded.pill}"
    padding: "9px 16px"
  chip-works-with-editorial:
    backgroundColor: "transparent"
    textColor: "{colors.editorial-ink}"
    rounded: "{rounded.editorial-lg}"
    padding: ".55em 1.2em"
  card-light:
    backgroundColor: "{colors.light-ground}"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.light-lg}"
    padding: "26px"
  card-dark:
    backgroundColor: "{colors.mock-shell}"
    textColor: "{colors.mock-text}"
    rounded: "{rounded.dark-lg}"
    padding: "28px"
  card-editorial:
    backgroundColor: "transparent"
    textColor: "{colors.editorial-ink}"
    rounded: "{rounded.editorial-lg}"
    padding: "1.75rem"
  kbd:
    backgroundColor: "{colors.mock-pill}"
    textColor: "{colors.mock-text}"
    typography: "{typography.label-mono}"
    rounded: "6px"
    padding: "3px 7px"
  mock-note-chip:
    backgroundColor: "rgba(23,26,32,.95)"
    textColor: "{colors.mock-text}"
    rounded: "{rounded.mock-chip}"
    padding: "8px 10px"
  mock-annotation-badge:
    backgroundColor: "{colors.mock-overlay-blue}"
    textColor: "#FFFFFF"
    rounded: "50%"
    size: "20px"
  mock-stack-shell:
    backgroundColor: "rgba(23,26,32,.95)"
    textColor: "{colors.mock-text}"
    rounded: "{rounded.mock-stack}"
    padding: "10px"
---

# Design System: SnapBrief landing

## Overview

**Creative North Star: "The Product Is the Only Dark Object"**

Three landings share one skeleton (nav, hero with live DOM mock, "pastes into" row, flagship Ctrl+V block, three steps, six features with mini-demos, agent output panel, before/after, Windows 11 block, one-card pricing, FAQ, final CTA, footer) and one product: the SnapBrief overlay, drawn in HTML/CSS in the app's exact charcoal skin (`mock-*` tokens). Each variant changes the ground the product sits on and the type that speaks around it; none of them changes the product. In the light canon (A) and the ultramarine changelog (C) the charcoal reads as a placed object, so every appearance of charcoal on the page is an appearance of the app. In the dark variant (B) the page is made of the same material as the app, so page panels and mock panels are the same tokens and the mock sits on the ground without a frame of its own.

Density is measured and calm: one accent per variant, 1px lines, 16px body at 1.55 to 1.6 leading, headings tightened to -0.02/-0.025em, section padding on a single clamp. Feature proofs are mini product demos, never icon tiles. Demo content is real-looking application text on the page's language; keys, file names, step numbers, counters and prompt text are set in JetBrains Mono because they are product output. Motion is one grammar everywhere: expo-out easing, 150ms hovers, 180ms fold into the stack, reveal-on-scroll as an enhancement over content that is visible by default.

Confirmed rejections carried by the build: no cream or warm paper ground (C's ground is cool `editorial-paper`), no neon glow on black (B's one radial is a 16% blue spotlight behind the mock), no bento of tiles, no testimonials or ratings, no raster screenshots of the product, no emoji or icon-font glyphs.

**Key Characteristics:**
- One shared product mock palette; three page palettes that never bleed into it
- Two blues in every variant: the page accent (per variant) and the overlay blue inside the product (`mock-overlay-blue`)
- Depth by 1px border first; soft ambient shadow only in A and B, none in C
- Mono for product output only; display faces never appear inside the mock
- Radii shrink as the ground gets more editorial: 8–12 (A), 12–16 (B), 2–4 (C); the mock keeps its own 4/10/12/16 regardless

## Colors

Two layers: a fixed charcoal product palette shared by all three files, and a per-variant page palette with exactly one accent.

### Primary
- **Overlay Blue** (`mock-overlay-blue`, #2F8CFF): the app's annotation blue. 2px annotation frames, active tool state, mini-demo frames, the "+ Capture" button inside the stack, the 20px numbered badge in the light mock. On the page it is the product's colour, not the page's.
- **Light Accent** (`light-accent`, #315CF5): variant A only. Filled primary button, checkmarks and step numbers, hover borders, selection, focus ring, the "after" column stroke. Hover deepens to `light-accent-deep`; `light-accent-soft` is the one tinted fill (pricing tag, "after" column).
- **Charcoal Fill Blue** (`dark-accent-fill`, #1E6FE0): variant B's filled primary button and every filled badge; hover `dark-accent-fill-hover`. In B, `mock-overlay-blue` stays a stroke, icon and active-tool colour; white text never sits on it at page scale.
- **Ultramarine** (`editorial-ultramarine`, #2038E6): variant C. Owns whole fields (hero, pricing, final CTA) with an SVG fractal-noise grain at 30% alpha, plus step numbers, entry numbers, the FAQ plus, the "after" column stroke, focus ring and scrollbar. Filled badges inside C's captures use `editorial-badge-fill` (#1B5FD1) for white numerals.

### Neutral (shared product material)
- **Charcoal Shell** (`mock-shell`, #171A20): toolbar, note chips, stack shell and composer at 95–97% alpha; B's page panels; A's agent output panel; C's entry demos. The one dark surface the system allows outside variant B.
- **Charcoal Card** (`mock-card`, #242A33) and **Hover** (`mock-hover`, #303845): thumbnails, attachment chips, mock inputs.
- **Charcoal Borders** (`mock-border` #39424E, `mock-border-strong` #46515F): every 1px line on charcoal. A one-step sibling #3A424E appears in A and C's source as a second border variable; treat it as `mock-border`.
- **Pill** (`mock-pill`, #2B3440): counters and `kbd` keys.
- **Shell Text** (`mock-text` #EEF2F8, `mock-text-secondary` #BFC8D6, `mock-icon` #9AA7B8): text and icons on charcoal in all three variants and page text in B.
- **Focus** (`mock-focus`, #7AB8FF): Restore link, caret in B, hover ring in the stack.
- **Danger** (`mock-danger`, #FF9B95): the "session lost" toast border and the "before" column icons in B.
- **Backdrop** (`mock-backdrop`, rgba(10,13,18,.55)): the frozen-desktop dim; B's hero mock uses a .6 spotlight cut-out of the same hue.

### Neutral (per-variant page grounds)
- **A:** `light-ground` #FFFFFF with `light-ground-alt` #F5F6F8 for the works row and footer; `light-ink` #172033 text, `light-muted` #5E687A secondary, `light-line` #DDE2EA borders, `light-line-soft` #E7EAF0 row dividers.
- **B:** `dark-ground` #0B0E13 page; panels, cards, borders and text are the `mock-*` tokens.
- **C:** `editorial-paper` #F2F3F5 body ground, `editorial-ink` #0B0F1A, `editorial-ink-secondary` #3D4A8A (secondary text tinted from the ultramarine), `editorial-rule` #C9CDD6 hairlines; on ultramarine, white and `editorial-on-blue-secondary` (rgba 255 .82) with hairlines at rgba(255,255,255,.16–.28).

### Named Rules
**The Charcoal Is Product Rule.** In A and C, `mock-shell` appears only where the app appears: hero mock, agent output panel, feature and step mini-demos. Marketing containers (pricing, compare, FAQ, footer) stay on the page ground. In B the page is the material, so the rule inverts: page panels and mock panels share tokens and the mock has no frame of its own.

**The Two-Blue Rule.** Every variant carries its page accent and the product's `mock-overlay-blue`. Annotation frames, badges, active tools and the stack button are always overlay blue; page buttons, checkmarks and focus rings are always the page accent. They are never swapped and never both used on one element.

**The Fill Deepens Rule.** White text on a filled blue uses the deeper step: `light-accent` (A), `dark-accent-fill` (B), `editorial-ultramarine` or `editorial-badge-fill` (C). `mock-overlay-blue` is a stroke and state colour at page scale; the only white-on-#2F8CFF is the app's own 20px badge and stack button inside the mock.

## Typography

**Display Font:** A: Wix Madefor Display 700 · B: Geologica 600 · C: Unbounded 500–700, lowercase (fallbacks system-ui, sans-serif)
**Body Font:** A: Golos Text 400–700 · B: Onest 400–600 · C: Literata 400–500 (Georgia, serif)
**Label/Mono Font:** JetBrains Mono 400–600 in all variants

**Character:** Each variant pairs a geometric display with a quiet body; the mono is the constant and it belongs to the product (keys, file names, prompt text, counters, step numbers). C is the only variant that lowercases headings and the only one with a serif body; A and B keep sentence case.

### Hierarchy
- **Display** (A 700 / B 600 / C 600, `display-*`, line-height 1.05–1.06): hero H1 only. A left-aligned in a 5/12 column at clamp(30–64px); B centered at clamp(44–72px), max 20ch; C lowercase at clamp(40–72px), max 12ch, white on ultramarine.
- **Headline** (`headline-*`, clamp(30px, 3.4vw, 46px), line-height 1.1): section H2, max 640px or 56ch, 16px below to the lede. Flagship and final CTA use smaller clamps (26–38px / 28–44px) at max 16–20ch.
- **Title** (`title-*`, 16.5–22px): feature and step H3 in the display face; C's entry titles at 1.3rem lowercase.
- **Body** (`body-*`, 16px / 1.55–1.6): paragraphs. Section ledes 17px; hero sub 18–19px (C clamp 17–20px); card copy 14–14.5px (C .9375rem). Max measures 44–60ch for ledes, 48–52ch for feature copy, 64–66ch for FAQ answers.
- **Label** (`label-mono`, 13px mono, weight 500–600, tabular numerals): step numbers, file rows, lang toggle, prompt panel. Nav links 14.5–15px body; footer column heads 13px semibold in the body face; small meta 12.5–13px muted.

### Named Rules
**The Mono Means Product Rule.** JetBrains Mono is used only for what the product emits or reads: keys (`kbd`), file names, the generated prompt, counters, step and entry numbers, graticule labels. Never headings, never running copy.

**The One Display Face Rule.** Each variant has one display face used for H1, H2, H3, brand wordmark and the price figure, and nothing else. Inside the mock, text is the body face (A/B) or mono (C) at 10–13px; the display face never enters the product.

## Layout

Container 1200px with 32px gutters (24px ≤1024/768, 16–18px ≤480) in A and B; C widens to 1320px with `clamp(20px, 4vw, 48px)` gutters and draws its container edges as 1px hairlines plus a 12-column graticule at 50% behind every section. Sticky 64px nav in every variant (backdrop blur 10–14px, 72–86% ground). Sections breathe on one clamp, `clamp(64px, 8vw, 112px)` block padding; section heads sit 44px above their content and cap at 640px / 56ch.

Hero grammar differs per variant and is the main layout distinction: A is 5/12 copy + 7/12 mock, 56px gap, stacking at 900px; B is centered copy with a full-width 1040px mock below on a radial spotlight; C is a 6/6 split at 92vh on the ultramarine field, mock captures fanned on a tick-marked graticule, stacking at 1024px. Feature proofs: A a 3-column grid with two spanning cards; B a sticky mock (top 100px, 440px tall) beside six 56vh feature rows that recolour as they activate, collapsing to per-row minis below 900px; C numbered `01`–`06` rows on a 60px / 1fr / 320px grid ruled by hairlines. Grid gaps step 24 / 32 / 48–56 / 64–72px. Breakpoints observed: 1280, 1024, 960/900/860, 768, 640/600, 480, 390.

The mock scales rather than reflows: it is drawn at 720px (A) or 1040px (B) and scaled via a CSS variable; below 600px the edge stack and composer inside it are hidden.

## Elevation & Depth

A hybrid that leans on borders. Every surface in every variant carries a 1px border first; shadows are ambient and secondary. Variant A adds three soft offset shadows tinted with its ink; variant B has one shadow used for panels, mock and pricing; variant C has none, depth comes from hairlines, the grain on ultramarine, and translucent white fills (rgba 255 .06–.07 with .24–.28 borders) on the blue fields. Inside the mock, floating panels are the charcoal at 95% alpha with `mock-border`, plus the variant's medium shadow in A and B.

### Shadow Vocabulary
- **Light small** (`box-shadow: 0 1px 2px rgba(23,32,51,.08)`): A's primary button, works chips, toasts.
- **Light medium** (`box-shadow: 0 8px 24px rgba(23,32,51,.10)`): A's cards, pricing, agent output panel, mock toolbar and stack.
- **Light large** (`box-shadow: 0 24px 48px rgba(23,32,51,.18)`): A's hero mock frame only.
- **Charcoal** (`box-shadow: 0 5px 24px rgba(0,0,0,.42)`): B's panels, mock, pricing card, floating chips; also the app's own stack shadow.
- **Spotlight** (`radial-gradient(ellipse 60% 100% at 50% 0%, rgba(47,140,255,.16), transparent 70%)`): B's hero only, behind the mock.

### Named Rules
**The Border First Rule.** A surface is defined by its 1px border; a shadow may be added but never replaces the border. C proves the rule with zero shadows.

**The Grain Belongs to Ultramarine Rule.** Noise texture appears only on `editorial-ultramarine` fields, as an inline SVG feTurbulence tile at 30% alpha; the paper ground and charcoal are smooth.

## Shapes

Three radius scales sharing one mock. A is softly rounded (8 / 10 / 12px; pills 999px; mock frame 20px). B is rounder (12 / 16px; small inputs 9px; pill 99px). C is near-square (2 / 3 / 4px) with hairline rules and 1px container edges, and its only rounded objects are the placed product pieces (capture cards 10px, stack 14px, composer 16px). The product keeps its own geometry in all three: annotation frames 4px, 2px stroke; badges circular 15–22px; note chips 9–10px; toolbar 12px; stack shell 14–16px; thumbnails 6–10px. Icons are inline SVG at 14–20px, stroke 1.5–1.75, round caps. FAQ toggles are a plus rotating 45° to a cross.

## Components

### Buttons
- **Shape:** A `light-md` (10px); B `dark-sm` (12px), fixed 48px height; C `editorial-lg` (4px). All inline-flex, 8px gap, 15px semibold (C 500 in Literata), 150ms transitions on background/border/colour only.
- **Primary:** A `light-accent` fill, white, 14px 24px, small shadow; hover `light-accent-deep`, active translateY(1px). B `dark-accent-fill`, white, 0 24px; hover `dark-accent-fill-hover`, active opacity .85. C on ultramarine: white fill with `editorial-ink` text, hover opacity .86; on paper: `editorial-ultramarine` fill, hover `editorial-ultramarine-hover`, active #16269E.
- **Secondary:** A transparent with `light-line` border, hover border and text turn `light-accent`. B transparent with `mock-border-strong` border, hover fills `mock-shell`. C outlined white at .55 alpha on blue, hover white border and .08 white fill.
- **Nav variant:** primary shrinks to 38px / 10px 18px / 13.5–14px; text collapses to a short label or icon-only ≤480px.
- **Focus:** 2px outline in the page accent (B uses `mock-focus`), 3px offset; on ultramarine the outline is white.

### Chips
- **Works-with chips:** A white pill, `light-line` border, 13.5px 500, small shadow. B `mock-shell` pill, `mock-border`, 14px. C `editorial-rule` border, 4px radius, .9375rem, no fill.
- **Tags:** pricing tag as a pill in `light-accent-soft`/`light-accent-deep` (A) or `mock-pill` with `mock-border` (B); C uses a 3px mono outlined tag at .6875rem on the blue field.
- **`kbd`:** mono 11px on `mock-pill`, `mock-border-strong` 1px, 6px radius, 3px 7px; identical treatment across variants because it is product material.

### Cards / Containers
- **Corner Style:** A 12px, B 16px, C 4px (mock objects keep their own).
- **Background:** A white or `light-ground-alt`; B `mock-shell`; C transparent on paper, rgba(255,255,255,.06) on ultramarine.
- **Shadow Strategy:** A medium, B charcoal, C none (see Elevation).
- **Border:** always 1px: `light-line`, `mock-border` / `mock-border-strong` for emphasis, `editorial-rule` or white .28.
- **Internal Padding:** 26–28px (compare), 36–40px (pricing), 20–24px (agent output panel), C `clamp(2rem, 4vw, 3rem)` for the plan card.
- **Emphasis:** the "after" compare column takes the accent as border (A also tints with `light-accent-soft`; B swaps to `mock-border-strong`).

### Navigation
- Sticky 64px bar, translucent ground with 10–14px backdrop blur, 1px bottom line. Brand: 26–28px inline SVG mark + wordmark in the display face at 17px (C lowercase). Links 14.5–15px in secondary text, hover to primary text (C underlines in ultramarine). Right cluster: mono lang toggle (13px, bordered, 8–9px radius, hover accent) and the nav primary. Links hide at 768 (A), 860 (B), 600 (C); the download label shortens ≤480–600px.

### FAQ Accordion
- Native `details`/`summary`; 1px row dividers; summary 16–17px semibold (C in the display face, lowercase) with a plus that rotates 45° when open; answer at 14.5–15px secondary text, max 64–66ch; height animates via `grid-template-rows` 0fr→1fr in 220ms down / 180ms up.

### Product Mock (signature component)
The one component shared by all three pages, drawn in HTML/CSS from the app's own tokens; never a raster. Frozen desktop (real-looking app window with text in the page language) under `mock-backdrop`; the selection stays bright; a floating toolbar (charcoal .95, `mock-border`, 12px radius, 24–26px tool buttons, active tool `mock-overlay-blue` on A / `mock-pill` with blue icon on B); 2px `mock-overlay-blue` annotation frames at 4px radius with a circular numbered badge at the top-left corner and a charcoal note chip (10px radius, `mock-border-strong`, 11–11.5px text, close cross) beside each; an edge stack (charcoal .95, 16px radius, "SnapBrief" title, `mock-pill` mono counter, `mock-card` thumbnails with lettered badges, `mock-overlay-blue` "+ Capture" button); and a composer panel (charcoal .97, 14px radius) receiving attachment chips and the mono prompt text. Animation is the same nine-second scene in all variants (backdrop 240ms → selection 420ms expo → toolbar 200ms → frame + badge + typed note → fold to stack 180ms → paste). Content is visible by default; `prefers-reduced-motion` shows the final frame.

## Do's and Don'ts

### Do:
- **Do** keep the product mock in the `mock-*` palette regardless of page variant; the app's skin is the constant the three pages agree on.
- **Do** define every surface with a 1px border before considering a shadow (The Border First Rule).
- **Do** set keys, file names, counters, step numbers and generated prompt text in JetBrains Mono at 11–13.5px with tabular numerals.
- **Do** use one section padding clamp, `clamp(64px, 8vw, 112px)`, and one hover duration, 150ms, on background, border, colour or opacity only.
- **Do** ship feature proofs as mini product demos in charcoal with real-looking text; the demo is the icon.
- **Do** make animation an enhancement: final state visible in CSS, JS rewinds into the loop, `prefers-reduced-motion` freezes the final frame.
- **Do** put white text on the deeper blue step (`light-accent`, `dark-accent-fill`, `editorial-ultramarine`, `editorial-badge-fill`), never on `mock-overlay-blue` at page scale.

### Don't:
- **Don't** introduce cream, beige or warm paper; C's paper is cool `editorial-paper` and A's alt ground is cool `light-ground-alt`.
- **Don't** add kicker or eyebrow labels above headings; every section in every variant opens directly with its H2.
- **Don't** use icon-tile feature grids, bento layouts, emoji, or icon fonts; icons are inline SVG at stroke 1.5–1.75.
- **Don't** add glow, 3D tilt or transform-heavy hovers; the only radial is B's 16% hero spotlight and the only hover transform is a 1px press on A's buttons.
- **Don't** let the display face enter the mock or the mono face enter headings and body copy.
- **Don't** place charcoal marketing containers on the A or C page grounds; charcoal outside variant B means "this is the product".
- **Don't** invent testimonials, ratings, logos of other brands or metrics; proof is the exact generated prompt and the before/after list.
