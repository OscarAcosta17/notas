; Inno Setup 6 script for NotasApp Windows Installer
#ifndef AppTag
  #define AppTag "v1.3.2"
#endif
#ifndef AppVer
  #define AppVer "1.3.2"
#endif
#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8E7D9A4C-5F2B-4B9E-A6D1-20260705C0DE}
AppName=NotasApp
AppVersion={#AppVer}
AppVerName=NotasApp {#AppTag}
AppPublisher=NotasApp
AppPublisherURL=https://github.com/OscarAcosta17/notas
AppSupportURL=https://github.com/OscarAcosta17/notas/issues
DefaultDirName={autopf}\NotasApp
DefaultGroupName=NotasApp
AllowNoIcons=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..
OutputBaseFilename=NotasApp-Setup-{#AppTag}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\notas.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
CloseApplicationsFilter=*.exe
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NotasApp"; Filename: "{app}\notas.exe"
Name: "{group}\{cm:UninstallProgram,NotasApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\NotasApp"; Filename: "{app}\notas.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\notas.exe"; Description: "{cm:LaunchProgram,NotasApp}"; Flags: nowait postinstall skipifsilent
