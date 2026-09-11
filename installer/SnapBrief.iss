; SnapBrief — Windows installer (Inno Setup 6).
; Build: scripts\build-installer.ps1 (publishes the app first, then compiles this script).
; Per-user install into %LOCALAPPDATA%\Programs\SnapBrief, no admin rights required.

#ifndef PublishDir
  #define PublishDir "..\artifacts\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\installer"
#endif
#define AppExe PublishDir + "\SnapBrief.exe"
#define ProductVersionRaw GetStringFileInfo(AppExe, "ProductVersion")
; Strip the "+<git sha>" suffix that .NET appends to the informational version.
#define AppVersion Copy(ProductVersionRaw, 1, Pos("+", ProductVersionRaw + "+") - 1)
#define AppFileVersion GetVersionNumbersString(AppExe)

[Setup]
AppId={{7D3C1E52-4C4A-4B6E-9B4B-2F0E3A7C5A11}
AppName=SnapBrief
AppVersion={#AppVersion}
AppVerName=SnapBrief {#AppVersion}
AppPublisher=Nikita Efimov
VersionInfoVersion={#AppFileVersion}
DefaultDirName={localappdata}\Programs\SnapBrief
DefaultGroupName=SnapBrief
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=SnapBrief-Setup-{#AppVersion}
SetupIconFile=..\src\SnapBrief.App\Assets\SnapBrief.ico
UninstallDisplayIcon={app}\SnapBrief.exe
UninstallDisplayName=SnapBrief
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=SnapBrief.exe
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Запускать SnapBrief при входе в Windows"; GroupDescription: "Автозапуск:"; Flags: unchecked; Languages: russian
Name: "autostart"; Description: "Start SnapBrief when you sign in to Windows"; GroupDescription: "Startup:"; Flags: unchecked; Languages: english

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "build-info.json,*.pdb"

[Icons]
Name: "{group}\SnapBrief"; Filename: "{app}\SnapBrief.exe"
Name: "{group}\{cm:UninstallProgram,SnapBrief}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\SnapBrief"; Filename: "{app}\SnapBrief.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SnapBrief"; ValueData: """{app}\SnapBrief.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\SnapBrief.exe"; Description: "{cm:LaunchProgram,SnapBrief}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/IM SnapBrief.exe /F"; Flags: runhidden; RunOnceId: "KillSnapBrief"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
