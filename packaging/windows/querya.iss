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
