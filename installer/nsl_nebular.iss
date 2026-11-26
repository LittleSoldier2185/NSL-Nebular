; NSL Nebular — สคริปต์ตัวติดตั้ง Inno Setup (https://jrsoftware.org/isinfo.php)
; สร้างด้วย tool\build_installer.ps1 (ส่ง /DAppVersion=x.y.z มาให้) หรือเปิดไฟล์นี้ใน Inno Setup Compiler แล้วกด Compile
; ติดตั้งแบบผู้ใช้คนเดียว (ไม่ต้องใช้สิทธิ์ผู้ดูแล) ลงใน %LOCALAPPDATA%\Programs\NSL Nebular

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

#define AppName "NSL Nebular"
#define AppExe "nsl_nebular.exe"
#define ProgId "NSLNebular.Project"

[Setup]
; GUID ตายตัวของแอปนี้ — อย่าเปลี่ยน ไม่เช่นนั้นการอัปเกรดจะติดตั้งซ้อนกับรุ่นเดิม
AppId={{6E1B7C2A-4D5F-4B8E-9A31-5C0D7F2E8A14}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=NSL
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename=NSL-Nebular-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "thai"; MessagesFile: "compiler:Languages\Thai.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "assoc_nsln"; Description: "ผูกไฟล์ .nsln กับ NSL Nebular (ดับเบิลคลิกเพื่อเปิด) / Associate .nsln files with NSL Nebular"; GroupDescription: "{cm:AssocFileExtension,{#AppName},.nsln}"
Name: "assoc_erd"; Description: "ผูกไฟล์ .erd รุ่นเก่า / Associate legacy .erd files"; GroupDescription: "{cm:AssocFileExtension,{#AppName},.erd}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; VC++ runtime แบบ app-local (build_installer.ps1 ก๊อป 64 บิตจาก System32 ไว้ที่ build\vcrt) ให้เปิดได้บนเครื่องที่ไม่เคยลง Visual C++ Redistributable
Source: "..\build\vcrt\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\vcrt\msvcp140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\vcrt\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\vcrt\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
; ไอคอนไฟล์โปรเจกต์ (.nsln) — ใช้เป็น DefaultIcon ของสกุลไฟล์
Source: "..\windows\runner\resources\nsln_file_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; ลงทะเบียนเฉพาะผู้ใช้ (HKA = HKCU เมื่อติดตั้งแบบผู้ใช้เดียว) ; uninsdeletekey ลบคีย์ของเราออกตอนถอนการติดตั้ง
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "NSL Nebular Project"; Flags: uninsdeletekey; Tasks: assoc_nsln assoc_erd
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: "{app}\nsln_file_icon.ico"; Tasks: assoc_nsln assoc_erd
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc_nsln assoc_erd
Root: HKA; Subkey: "Software\Classes\.nsln"; ValueType: string; ValueData: "{#ProgId}"; Flags: uninsdeletevalue; Tasks: assoc_nsln
Root: HKA; Subkey: "Software\Classes\.erd"; ValueType: string; ValueData: "{#ProgId}"; Flags: uninsdeletevalue; Tasks: assoc_erd

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
