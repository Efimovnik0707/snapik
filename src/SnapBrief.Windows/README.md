# SnapBrief.Windows

Windows-only transport adapters for a prepared immutable export. The application layer maps `PreparedExport` to:

```csharp
new PreparedPastePackage(
    prepared.Manifest.ExportId,
    prepared.GetImagePathsInOrder(),
    prepared.Manifest.PromptText);
```

`PasteCoordinator` supports one composite `CF_HDROP` + Unicode text clipboard object and a staged image/text sequence. Staged PNGs expose the registered `PNG` bytes plus standard `CF_DIB` and auto-convertible `CF_BITMAP` representations. Every retry checks the Windows clipboard sequence immediately before WPF/OLE writes and stops when another application has already changed it. WPF opens the clipboard internally, so this is a best-effort race guard rather than a native atomic compare-and-swap; the coordinator also checks the resulting sequence after each write. `SetDataObject(copy:true)` flushes persistent data before success. If SnapBrief becomes owner but that flush is temporarily blocked, the service detects its own `DataObject` and retries only `Clipboard.Flush`, while its dedicated STA dispatcher remains able to service OLE messages. The coordinator captures the foreground top-level window and focused child control and rechecks both around each shortcut. When Windows does not expose a focused child handle, this guard falls back to top-level window identity.

The persistence and ownership behavior follows Microsoft's [`Clipboard.SetDataObject`](https://learn.microsoft.com/dotnet/api/system.windows.clipboard.setdataobject?view=windowsdesktop-10.0) and [`Clipboard.Flush`](https://learn.microsoft.com/dotnet/api/system.windows.clipboard.flush?view=windowsdesktop-10.0) contracts. Image formats follow the Win32 [standard and synthesized clipboard formats](https://learn.microsoft.com/windows/win32/dataxchg/clipboard-formats). Tests query the WPF `DataObject` through COM `IDataObject` directly to verify raw PNG and DIB `HGLOBAL` bytes without publishing anything to the system clipboard.

Built-in profiles are deliberately `Unverified`. `UnobservableAcceptanceObserver` waits only for a calibrated delay and returns `NotObservable`; its successful completion produces `CompletedUnverified`, never `CompletedVerified`. A later UI Automation observer may return `Accepted` only when it observes the relevant attachment or text state. Safe resume is offered only for a contiguous prefix of observed image acceptances. After any unobservable step the user must inspect the draft before retrying.

No profile may contain Enter. `WindowsInputInjector` rejects Enter again at the native boundary. Before injecting, it waits up to 750 ms for Ctrl, Shift, Alt, Windows, and the gesture key to be physically released, so the global trigger cannot leak modifiers into the target shortcut. It never synthesizes key-up for a key the user is holding. `SendInput` can fail across Windows integrity levels and does not itself prove that the target accepted content.

The installed-machine process inventory on 2026-09-08 showed the Codex desktop package using process name `ChatGPT`, Claude desktop and CLI using `claude`, Codex CLI using `codex`, and no active `WindowsTerminal` process. Profiles are selectable and immutable; the settings UI may create a user-specific `TargetProfile` for another terminal host and gestures. A selected profile identifies the intended host, but a shared host process cannot prove which CLI is running in its current terminal tab.

Automated tests use fakes and never open the live clipboard, inspect UI, or inject input. Real compatibility remains unverified until the manual P1 matrix is completed in throwaway drafts for each exact app/version.
