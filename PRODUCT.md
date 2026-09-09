# Product

<!-- impeccable:product-schema 1 -->

## Platform

Windows desktop

## Stack

Delegated: native Windows desktop application built with WPF on .NET 10. The choice follows the confirmed Windows-only first release, system integration requirements, and the implementation brief.

## Users

The first user is Nikita, who regularly gives UI feedback to coding agents while switching between Windows desktop applications and terminals. He needs to capture several visual states, point to exact elements, and explain each requested change without manually numbering screenshots and notes.

## Product Purpose

SnapBrief turns several screenshots, visual annotations, and linked notes into one reviewable package for Claude Code and Codex. Success means the user can move from a visible issue to a correctly structured draft in the agent composer with very little interruption.

## Positioning

The product keeps screenshot-level and annotation-level notes structurally linked while preparing multiple separate images and one deterministic prompt for an agent in a single workflow.

## Operating Context

SnapBrief runs locally on Windows 11 as a small edge stack rather than a conventional editor window. A typical session contains one to five captures from ordinary desktop applications. The user invokes capture with a global shortcut, selects and marks the frozen desktop in place, adds a compact note beside a marked region, then folds the result by clicking the dimmed backdrop, pressing Ctrl+C, or starting the next capture. Each fold updates the clipboard package. After SnapBrief observes the user paste its current package with Ctrl+V or Alt+V in another application, it preserves the sent files and clipboard while rotating the active stack to a new empty session.

## Capabilities and Constraints

- Capture a rectangular desktop region, import PNG/JPEG files, and import a clipboard image.
- Keep the primary capture and annotation flow in a full-screen desktop overlay; the persistent launcher is a compact edge stack.
- Keep multiple ordered captures in one recoverable session.
- Support arrows, rectangles, pen, highlight, text, true region blur, opaque concealment, and in-place crop. One undo/redo flow restores annotation geometry, notes, crop geometry, bitmap, and source path.
- Keep a separate note for the capture, notes linked to individual annotations, without a separate overall request field.
- Open an anchored comment editor automatically after a rectangle is drawn. Other annotation notes and the capture note open from compact contextual actions; closing an editor removes its note while preserving the marked region.
- Export one annotated PNG per capture plus UTF-8 Markdown and prepare a clipboard package for normal paste in the receiving application. The primary surface has no receiver picker. In Codex Desktop only, a guarded follow-up writes and pastes the matching prompt after the user's physical Ctrl+V; it never submits the request.
- When the current SnapBrief clipboard package has been pasted, replaced, or cannot be proven owned, the next capture starts a new empty session. The previous session and assets remain recoverable, and unrelated clipboard content stays intact until the new capture commits.
- The desktop shortcut starts SnapBrief when needed and reveals the already-running edge stack through single-instance activation.
- Preserve the session when capture, disk, clipboard, focus, or target delivery fails.
- Never press Enter or submit the agent request.
- Keep screenshots local. The application has no cloud service, AI rewriting, API key, or telemetry requirement.
- The strict multi-image-plus-text delivery behavior remains dependent on practical verification in each target application. Document compatibility separately; do not place compatibility prose permanently in the edge stack.
- Windows 11 x64 is the only first-release platform. Cross-platform support, video, OCR, voice transcription, history search, and scrolling capture are outside the first release.

## Brand Commitments

The working product name is SnapBrief. The interface uses a restrained macOS utility language: custom translucent charcoal surfaces, compact floating controls, soft rounded corners, clear blue focus, and short transitions without stock Windows chrome in the primary flow. The user explicitly pinned the interaction character of Casso and Lightshot: annotation directly over a frozen desktop, compact floating controls, inline notes, and completed captures folded into an edge stack. A thumbnail delete control appears on hover or keyboard focus, removes in one click, and exposes an inline Restore action. Their proprietary source and assets are not part of this project.

## Evidence on Hand

The full user transcript is stored at `tasks/user-transcript.md`; the implementation requirements and researched constraints are stored at `tasks/prd-snapbrief.md`. No approved logo, proprietary artwork, customer claims, usage metrics, or tested Casso Windows build exists. Casso's official download page showed macOS availability and Windows as coming soon on 8 September 2026.

## Product Principles

1. The relation between every note and its capture or annotation is always visible.
2. The common path from capture to typing a note has no modal interruption.
3. Adding another capture preserves the current task and returns the user to the editor quickly.
4. Status copy describes what SnapBrief actually prepared or attempted; it never claims that an external agent accepted an attachment unless that was observed.
5. Failures leave the user's screenshots and notes recoverable.

## Accessibility & Inclusion

All core actions are keyboard reachable. Visible focus, readable text contrast, Windows scaling, mixed DPI monitors, Russian and English text, emoji, and long Unicode notes are part of the supported first-release experience.

## Уточнение комментариев после практической проверки

После первоначального захвата поле комментария не открывается автоматически. После рисования рамки-аннотации поле появляется рядом с этой рамкой автоматически и получает фокус ввода. Это последнее уточнение пользователя заменяет прежнее требование открывать все заметки только вручную. Для других отметок и комментария ко всему снимку доступна компактная контекстная кнопка рядом с геометрией; крестик удаляет только заметку. Не требовать поиска значка на общей панели.


При запуске SnapBrief работает в трее без открытой панели. Стопка после захвата показывается спереди без активации и без таймера исчезновения. Крестик скрывает её; успешное завершение пакета при вставке также скрывает стопку. Панель не закреплена поверх других окон. Крестик скрывает её, сохраняя снимки. Ярлык или значок в трее позволяет снова открыть стопку. Настройки клавиш доступны через трей.

Границы снимка и отметок, включая blur, изменяются за четыре угла; угол отметки можно потянуть при любом активном инструменте. Сужение снимка обрезает выходящие за границы отметки, Undo восстанавливает предыдущее состояние. Расширение использует только уже захваченные пиксели: для нового снимка доступен замороженный рабочий стол, при повторном открытии — сохранённое исходное изображение. Новое содержимое рабочего стола при расширении не захватывается. Во время изменения области blur отображается сплошная маска; эффект пересчитывается после отпускания мыши.
При рисовании новой области blur до отпускания мыши видны контур и полупрозрачная подсветка; финальное размытие применяется после завершения жеста. Настройки захвата принимают собственную клавишу или сочетание через поле записи. Старые сохранённые пресеты совместимы; сочетание проверяется при сохранении, конфликт оставляет диалог открытым. Отмена сохраняет прежнее назначение.
Полный оконный редактор исключён из приложения, включая пункт меню и путь запуска --advanced. Основные поверхности — разметка поверх экрана и стопка. Общего комментария ко всей стопке в интерфейсе и новом пакете нет; комментарии принадлежат снимкам и отметкам. Старое поле сессии сохраняется только для совместимости данных.

Горячая клавиша задаётся в одном поле: клик → нажатие клавиши или сочетания → сохранение. Отдельных кнопок PB и других специальных пресетов не требуется. Пока поле записывает ввод, Enter, Tab и Escape относятся к назначению, а не к навигации; после записи фокус переходит на сохранение. Модификаторы поддерживаются в сочетании и отдельно. Возможность глобальной регистрации проверяет Windows; отказ показывается внутри настроек, прежнее назначение сохраняется при отмене.
## Локальное сохранение и настройки захвата

В панели разметки необходима кнопка сохранения текущего снимка на компьютер и Ctrl+S. Поддерживаются PNG и JPEG с регулируемым качеством. Отмена диалога сохраняет открытый редактор и его разметку. Быстрое сохранение всего виртуального рабочего стола имеет отдельную включаемую горячую клавишу и папку; оно не добавляет изображение в текущий пакет и не заменяет буфер.

Общие параметры: уведомления о копировании и сохранении, запоминание геометрии последней области, включение курсора и язык интерфейса. Геометрия повторно используется только при совпадающей конфигурации виртуального рабочего стола. Настройки и горячие клавиши переживают перезапуск; конфликт регистрации не заменяет сохранённое рабочее сочетание. Временные ссылки, загрузка, её горячая клавиша и прокси отложены до проектирования хранения и срока доступа.

Панель инструментов размещается снаружи выделения: снизу, сверху, затем сбоку, с учётом границ монитора. Внешнее размещение имеет приоритет перед избеганием заметок. Только при отсутствии места снаружи допустимо размещение внутри выделения, например для полного экрана.
