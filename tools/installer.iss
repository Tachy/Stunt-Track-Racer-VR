; Installer of Stunt Track Racer VR (Inno Setup 6), built by tools/build.ps1:
;   ISCC /DAppVersion=1.2.3 /DFileVersion=1.2.3.0 /DSourceDir=<build\package> /DOutputDir=<build> installer.iss
; Per user, no admin rights: %LOCALAPPDATA%\Programs\Stunt Track Racer VR.
; A newer installer installs over an older one (same AppId); saves,
; settings and own tracks are in %APPDATA% and stay.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef FileVersion
  #define FileVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\package"
#endif
#ifndef OutputDir
  #define OutputDir "..\build"
#endif
#define AppName "Stunt Track Racer VR"
#define AppExe "StuntTrackRacerVR.exe"

[Setup]
AppId={{1823D17F-E97B-4907-9780-C20304A451FA}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Stunt Track Racer VR
AppPublisherURL=https://github.com/Tachy/Stunt-Track-Racer-VR
AppSupportURL=https://github.com/Tachy/Stunt-Track-Racer-VR/issues
AppUpdatesURL=https://github.com/Tachy/Stunt-Track-Racer-VR/releases
VersionInfoVersion={#FileVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=StuntTrackRacerVR-{#AppVersion}-setup
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
LicenseFile={#SourceDir}\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
german.DesktopMode=Desktop-Modus (ohne VR)
english.DesktopMode=desktop mode (no VR)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{#AppName} ({cm:DesktopMode})"; Filename: "{app}\{#AppExe}"; Parameters: "--xr-mode off -- --no-xr"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Parameters: "--xr-mode off -- --no-xr"; Description: "{cm:LaunchProgram,{#AppName} ({cm:DesktopMode})}"; Flags: nowait postinstall skipifsilent unchecked
