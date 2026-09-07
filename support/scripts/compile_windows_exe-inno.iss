; Aika — Windows installer (Inno Setup)
;
; Packages the release output of `flutter build windows --release` into a
; single unsigned Aika-vX.Y.Z-windows-x64-setup.exe installer.
;
; Compiled by .github/workflows/release.yml on every `vX.Y.Z` tag push,
; from the repo root, as:
;   ISCC.exe support\scripts\compile_windows_exe-inno.iss
; (relative paths below assume that working directory).
;
; No code-signing certificate is used yet — Windows SmartScreen will warn on
; first run until Aika has one (same blocker as the MSIX packaging tracked in
; windows/aika.exe.manifest, left in place for later).
;
; IMPORTANT: MyAppVersion below is overwritten at release-build time by the
; "Set Inno Setup version to match this release" step in release.yml, so it
; always matches the tag being released. It still must be bumped by hand in
; this file on regular (non-tag) commits: .github/workflows/ci.yml's
; "packaging" job fails CI on every push/PR if this value drifts from
; app/pubspec.yaml's version.

#define MyAppName "Aika"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "Bachir Abdoul Kader"
#define MyAppURL "https://naniger.com"
#define MyAppExeName "aika.exe"

[Setup]
; Unique to Aika — do not reuse LocalSend's original AppId, so an Aika
; install is never confused with (or blocked by) a LocalSend install.
AppId={{DE7A4427-79EC-4915-8DB0-1E3469580178}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=Aika-v{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\app\assets\packaging\logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The entire flutter build windows --release output (aika.exe, flutter_windows.dll,
; the bundled VC++ runtime DLLs, data\, etc.) — release.yml stages it all under
; app\build\windows\x64\runner\Release before this script runs.
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
