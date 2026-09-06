; Inno Setup script for Querya Desktop (Windows installable channel).
; Compile from repo root after `flutter build windows --release`:
;   ISCC /DMyAppVersion=0.4.11 packaging\windows\querya.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Querya Desktop"
#define MyAppPublisher "QueryaHub"
#define MyAppExeName "querya_desktop.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Stable AppId — do not change across releases (controls uninstall / upgrades).
AppId={{A7C3E2F1-9B4D-4E8A-8F2C-1D5E6A7B8C9D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/QueryaHub/Querya-Desktop
DefaultDirName={autopf}\Querya Desktop
DefaultGroupName=Querya Desktop
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=..\..\dist-windows
OutputBaseFilename=Querya-Desktop-{#MyAppVersion}-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
; .sql file association and Open With
Root: HKCR; Subkey: ".sql"; ValueType: string; ValueName: ""; ValueData: "Querya.SQL"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".sql\OpenWithProgids"; ValueType: string; ValueName: "Querya.SQL"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCR; Subkey: "Querya.SQL"; ValueType: string; ValueName: ""; ValueData: "SQL Script File"; Flags: uninsdeletekey
Root: HKCR; Subkey: "Querya.SQL\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "Querya.SQL\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

; .sqlite, .sqlite3, .db, .db3 file associations and Open With
Root: HKCR; Subkey: ".sqlite"; ValueType: string; ValueName: ""; ValueData: "Querya.SQLite"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".sqlite\OpenWithProgids"; ValueType: string; ValueName: "Querya.SQLite"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".sqlite3"; ValueType: string; ValueName: ""; ValueData: "Querya.SQLite"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".sqlite3\OpenWithProgids"; ValueType: string; ValueName: "Querya.SQLite"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".db"; ValueType: string; ValueName: ""; ValueData: "Querya.SQLite"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".db\OpenWithProgids"; ValueType: string; ValueName: "Querya.SQLite"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".db3"; ValueType: string; ValueName: ""; ValueData: "Querya.SQLite"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".db3\OpenWithProgids"; ValueType: string; ValueName: "Querya.SQLite"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCR; Subkey: "Querya.SQLite"; ValueType: string; ValueName: ""; ValueData: "SQLite Database File"; Flags: uninsdeletekey
Root: HKCR; Subkey: "Querya.SQLite\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "Querya.SQLite\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

; Windows Applications registry (ensures presence in modern Open With menu)
Root: HKCR; Subkey: "Applications\{#MyAppExeName}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#MyAppName}"; Flags: uninsdeletekey
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".sql"; ValueData: ""
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".sqlite"; ValueData: ""
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".sqlite3"; ValueData: ""
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".db"; ValueData: ""
Root: HKCR; Subkey: "Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".db3"; ValueData: ""
