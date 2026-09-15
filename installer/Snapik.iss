; Snapik — Windows installer (Inno Setup 6).
; Build: scripts\build-installer.ps1 (publishes the app first, then compiles this script).
; Per-user install into %LOCALAPPDATA%\Programs\Snapik, no admin rights required.

#ifndef PublishDir
  #define PublishDir "..\artifacts\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\installer"
#endif
#define AppExe PublishDir + "\Snapik.exe"
#define ProductVersionRaw GetStringFileInfo(AppExe, "ProductVersion")
; Strip the "+<git sha>" suffix that .NET appends to the informational version.
#define AppVersion Copy(ProductVersionRaw, 1, Pos("+", ProductVersionRaw + "+") - 1)
#define AppFileVersion GetVersionNumbersString(AppExe)

[Setup]
AppId={{7D3C1E52-4C4A-4B6E-9B4B-2F0E3A7C5A11}
AppName=Snapik
AppVersion={#AppVersion}
AppVerName=Snapik {#AppVersion}
AppPublisher=Nikita Efimov
AppPublisherURL=https://getsnapik.com
AppSupportURL=https://getsnapik.com
VersionInfoVersion={#AppFileVersion}
DefaultDirName={localappdata}\Programs\Snapik
DefaultGroupName=Snapik
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=Snapik-Setup-{#AppVersion}
SetupIconFile=..\src\Snapik.App\Assets\Snapik.ico
UninstallDisplayIcon={app}\Snapik.exe
UninstallDisplayName=Snapik
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=Snapik.exe
RestartApplications=no
; The installer never asks for a language: it takes the one of the system, exactly like the
; application does. Startup is not asked for either, the wizard of the first run owns that switch.
ShowLanguageDialog=no

; English first on purpose: with the dialog off Inno picks the language whose LanguageID matches the
; UI locale and falls back to the FIRST entry when none does, so a Spanish, German or Ukrainian
; system would otherwise be given a Russian installer.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "build-info.json,*.pdb"

[Icons]
; Both shortcuts carry the identity the application names itself with at startup
; (TaskbarPinService.AppUserModelId). Without it the pinned icon and the running window are two
; different applications to the taskbar, and a shortcut started from the desktop gets a button of
; its own beside the pinned one. The shortcut in the Start menu is also what the pinning API reads
; the identity from, so it has to be there and it has to agree.
Name: "{group}\Snapik"; Filename: "{app}\Snapik.exe"; AppUserModelID: "YesWorkflow.Snapik"
Name: "{group}\{cm:UninstallProgram,Snapik}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Snapik"; Filename: "{app}\Snapik.exe"; AppUserModelID: "YesWorkflow.Snapik"; Tasks: desktopicon

[Run]
Filename: "{app}\Snapik.exe"; Description: "{cm:LaunchProgram,Snapik}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/IM Snapik.exe /F"; Flags: runhidden; RunOnceId: "KillSnapik"
; The startup entry is written by the application itself now, into this very value, so the installer
; no longer creates it and "uninsdeletevalue" no longer removes it. Uninstalling has to drop it
; unconditionally, or a user who switched startup on in the wizard keeps a Run entry pointing at an
; executable that is gone. A [Registry] line with "deletevalue" was rejected: it would also switch
; the setting off on every install over an existing one.
Filename: "reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v Snapik /f"; Flags: runhidden; RunOnceId: "DropAutostart"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
