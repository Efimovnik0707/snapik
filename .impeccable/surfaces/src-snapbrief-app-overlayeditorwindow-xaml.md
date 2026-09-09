---
version: 1
slug: "src-snapbrief-app-overlayeditorwindow-xaml"
primary_target: "src/SnapBrief.App/OverlayEditorWindow.xaml"
related_targets: ["src/SnapBrief.App/EdgeStackWindow.xaml","src/SnapBrief.App/MainWindow.xaml"]
---

# SnapBrief capture and stack

## Mode

Operate. Native Windows 11 desktop, WPF. The only shipped device class is desktop; mobile platform guidance does not apply.

## Direction contract

THESIS: Annotate the captured screen in place, then fold it into a persistent edge stack. The user's Casso reference replaces the rejected large editor.

OWN-WORLD: Modern macOS utility character on Windows: charcoal floating panels, blue region outlines, circular labels, quiet typography, restrained shadows and compact note chips. Primary controls share this custom visual language.

STORY: Capture, mark, type, fold, continue; compose a linked multi-image agent draft.

FIRST VIEWPORT: Frozen desktop dominates. Selection stays in place. Notes sit beside regions; compact tools and recipient actions float below. Done reveals a narrow right-edge thumbnail stack over the live desktop.

FORM: User-pinned Casso and Lightshot interaction, authoritative screenshot at `.impeccable/references/user-casso.png`. It overrides seed cc064e76. Signature transition: editing surface collapses to the same capture's stack thumbnail in 160–200 ms; respect disabled system animation.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Behavior and acceptance

- The stack remains visible while other applications accept normal clicks. Close fullscreen editing HWNDs instead of hiding their pixels over an input-blocking window.
- One click reopens a thumbnail with editable annotations and notes. Each capture supports removal, and ordering preserves note identity.
- Hover or keyboard focus reveals a close affordance on that thumbnail. One click removes only that capture; a compact Undo action restores its original position and notes. Removing the second capture leaves the first and stack available. Do not add a confirmation dialog.
- Drawing a region immediately focuses its inline note. Typing must preserve focus, caret and IME state; do not recreate text fields per keystroke.
- Treat capture, crop, privacy edits, annotation, note entry, fold and handoff as one workflow. Region blur and solid concealment are separate tools; crop and all visual edits support Undo/Redo in the overlay. The user must not visit the advanced window for these common actions.
- A blur is an actual pixel transformation in both preview and exported PNG. Cropping retains the uncropped image for Undo, remaps remaining annotation geometry and preserves stable note identities. Prepared exports are invalidated after these edits.
- The original pixels are saved before decoration. Export contains rendered marks and labels, without floating app controls, source files or accidental desktop overlays.
- Notes remain within the visible monitor workarea. Long notes use a bounded multiline editor; they never push primary actions off screen.
- Global capture hides all SnapBrief surfaces. The stack and paste completion must not steal foreground from the user's target composer.
- Expanded editor, import, export, global note and settings remain reachable as secondary actions. They do not replace the primary capture flow.
- The user explicitly wants a modern Apple-like utility, not a Windows-looking window. Avoid stock Windows titlebars, combobox styling and menu chrome in the primary surface. Do not show a recipient picker in the primary flow; keep keyboard navigation and visible focus.
- Verify real Windows states: new capture with several marked regions, typing an inline note, three-image collapsed stack, reopened capture, and error feedback. Compare overlay and stack screenshots to the user's reference before claiming design completion.

## Visual evidence and provenance

- User supplied Casso image: `.impeccable/references/user-casso.png`; research reference only, not bundled product artwork.
- Lightshot official capture UI: https://st.prntscr.com/2025/12/17/0541/img/media-screen-1.jpg (viewed 8 September 2026). Close-to-selection tool placement is the relevant behavior.
- Snipper Ghost Tray: https://www.snipperapp.org/ (reviewed 8 September 2026). Persistent floating captures inform edge-stack behavior; no compatibility claims inferred.
- Pinterest searches for screenshot annotation and floating toolbars yielded weakly relevant results. The provided Casso and official screenshot-tool interfaces carry the design decision.

## Primary interaction correction — 9 September

Clicking the dimmed backdrop outside the capture, toolbar, note editors and popovers commits the capture and folds it into the stack. Ctrl+C outside text entry performs the same action. Text fields retain standard text-copy behavior. The dismissal click is consumed; it must not activate an underlying application. Notes open only after an explicit request. Starting the next capture commits the current one without a separate Done click.

Folding saves the capture and prepares the full ordered stack in the clipboard. Ordinary Ctrl+V or the terminal's own image-paste key performs delivery; SnapBrief does not require a receiver picker or intercept Alt+V in its primary flow. Show clipboard errors on the recoverable stack. A copied single screenshot exposes native image plus file/text formats; multiple screenshots expose the complete file/text package. Receiving all separate images and notes remains an explicit compatibility acceptance condition, not something inferred from successful clipboard writes.

The user's additional note reference is .impeccable/references/user-casso-notes.png. A note is a compact pill anchored near its marked region, with an immediate remove-note X; do not use a persistent corner form. The reference's recipient strip is landing-page communication, explicitly excluded from this app. The edge stack contains thumbnails and actions, no permanent explanatory paragraphs or compatibility prose. Use hover tooltips, accessible control names and transient actionable errors when an operation fails.

## Уточнение комментариев после практической проверки

После первоначального захвата поле комментария не открывается автоматически. После рисования рамки-аннотации поле появляется рядом с этой рамкой автоматически и получает фокус ввода. Это последнее уточнение пользователя заменяет прежнее требование открывать все заметки только вручную. Для других отметок и комментария ко всему снимку доступна компактная контекстная кнопка рядом с геометрией; крестик удаляет только заметку. Не требовать поиска значка на общей панели.
