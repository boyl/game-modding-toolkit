Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:FoundWindow = [IntPtr]::Zero

function Initialize-GMTIsaacWindowAutomation {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if ('GMTIsaacWindow' -as [type]) { return }
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GMTIsaacWindow {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  public static void Click(int x, int y) { SetCursorPos(x,y); mouse_event(2,0,0,0,UIntPtr.Zero); mouse_event(4,0,0,0,UIntPtr.Zero); }
}
'@
    [GMTIsaacWindow]::SetProcessDPIAware() | Out-Null
}

function Resolve-GMTIsaacUploaderPath {
    param([string]$ExplicitPath)
    if ($ExplicitPath) {
        $resolved=(Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
        if ([IO.Path]::GetFileName($resolved) -ne 'ModUploader.exe') { throw "不是 ModUploader.exe：$resolved" }
        return $resolved
    }
    $roots=[Collections.Generic.List[string]]::new()
    $steam=Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($steam.SteamPath) { $roots.Add(($steam.SteamPath -replace '/','\')) }
    foreach ($file in @($roots | ForEach-Object { Join-Path $_ 'steamapps\libraryfolders.vdf' })) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($match in [regex]::Matches((Get-Content -Raw -LiteralPath $file),'"path"\s+"([^"]+)"')) {
            $root=$match.Groups[1].Value -replace '\\\\','\'
            if (-not $roots.Contains($root)) { $roots.Add($root) }
        }
    }
    foreach ($root in $roots) {
        $game=Join-Path $root 'steamapps\common\The Binding of Isaac Rebirth'
        if (-not (Test-Path -LiteralPath $game -PathType Container)) { continue }
        $found=Get-ChildItem -LiteralPath $game -Filter ModUploader.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw '找不到 ModUploader.exe，请通过 -UploaderPath 指定。'
}

function Find-GMTIsaacWindow {
    param([int]$ProcessId,[string]$ExactTitle)
    $script:FoundWindow=[IntPtr]::Zero
    [GMTIsaacWindow]::EnumWindows({
        param($hwnd,$unused)
        if (-not [GMTIsaacWindow]::IsWindowVisible($hwnd)) { return $true }
        $owner=0; [GMTIsaacWindow]::GetWindowThreadProcessId($hwnd,[ref]$owner) | Out-Null
        if ($owner -ne $ProcessId) { return $true }
        $text=[Text.StringBuilder]::new(512); [GMTIsaacWindow]::GetWindowText($hwnd,$text,512) | Out-Null
        if ($text.ToString() -eq $ExactTitle) { $script:FoundWindow=$hwnd }
        return $true
    },[IntPtr]::Zero) | Out-Null
    return $script:FoundWindow
}

function Wait-GMTIsaacWindow {
    param([int]$ProcessId,[string]$ExactTitle,[int]$TimeoutSeconds=15,[switch]$Disappear)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $window=Find-GMTIsaacWindow $ProcessId $ExactTitle
        if ($Disappear -and $window -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
        if (-not $Disappear -and $window -ne [IntPtr]::Zero) { return $window }
        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)
    throw "等待窗口$(if($Disappear){'消失'}else{'出现'})超时：$ExactTitle"
}

function Focus-GMTIsaacWindow {
    param([int]$ProcessId,[string]$ExactTitle)
    # 每个动作前重新枚举；绝不复用旧 HWND。
    $window=Wait-GMTIsaacWindow $ProcessId $ExactTitle
    [GMTIsaacWindow]::ShowWindow($window,9) | Out-Null
    [GMTIsaacWindow]::BringWindowToTop($window) | Out-Null
    [GMTIsaacWindow]::SetForegroundWindow($window) | Out-Null
    $deadline=(Get-Date).AddSeconds(3)
    while ([GMTIsaacWindow]::GetForegroundWindow() -ne $window -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100; [GMTIsaacWindow]::SetForegroundWindow($window) | Out-Null
    }
    if ([GMTIsaacWindow]::GetForegroundWindow() -ne $window) { throw "无法取得窗口焦点：$ExactTitle" }
    return $window
}

function Get-GMTIsaacRect {
    param([IntPtr]$Window)
    $rect=[GMTIsaacWindow+RECT]::new()
    if (-not [GMTIsaacWindow]::GetWindowRect($Window,[ref]$rect)) { throw '读取窗口矩形失败。' }
    return [ordered]@{Left=$rect.Left;Top=$rect.Top;Width=$rect.Right-$rect.Left;Height=$rect.Bottom-$rect.Top}
}

function Click-GMTIsaacRelative {
    param([IntPtr]$Window,[double]$X,[double]$Y)
    $r=Get-GMTIsaacRect $Window
    [GMTIsaacWindow]::Click([int]($r.Left+$r.Width*$X),[int]($r.Top+$r.Height*$Y))
}

function Save-GMTIsaacEvidence {
    param([IntPtr]$Window,[string]$EvidenceRoot,[string]$Name)
    $r=Get-GMTIsaacRect $Window; $bitmap=[Drawing.Bitmap]::new($r.Width,$r.Height); $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.CopyFromScreen($r.Left,$r.Top,0,0,$bitmap.Size); $path=Join-Path $EvidenceRoot ($Name+'.png'); $bitmap.Save($path); return $path }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Submit-GMTIsaacFileDialog {
    param([int]$ProcessId,[string]$Title,[string]$FilePath,[string]$EvidenceRoot)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "待选择文件不存在：$FilePath" }
    $dialog=Focus-GMTIsaacWindow $ProcessId $Title; $shell=New-Object -ComObject WScript.Shell
    $previous=[Windows.Forms.Clipboard]::GetText()
    try {
        $shell.SendKeys('%n'); Start-Sleep -Milliseconds 250; [Windows.Forms.Clipboard]::SetText($FilePath)
        $shell.SendKeys('^a'); $shell.SendKeys('^v'); Start-Sleep -Milliseconds 750
        Save-GMTIsaacEvidence $dialog $EvidenceRoot ('dialog-'+($Title -replace '\W+','-')) | Out-Null
        $shell.SendKeys('{ENTER}'); Wait-GMTIsaacWindow $ProcessId $Title 15 -Disappear | Out-Null
    } finally { if($previous){[Windows.Forms.Clipboard]::SetText($previous)}else{[Windows.Forms.Clipboard]::Clear()} }
}

function Set-GMTIsaacText {
    param([string]$Text)
    $shell=New-Object -ComObject WScript.Shell; $previous=[Windows.Forms.Clipboard]::GetText()
    try { [Windows.Forms.Clipboard]::SetText($Text); $shell.SendKeys('^a'); $shell.SendKeys('^v'); Start-Sleep -Milliseconds 500 }
    finally { if($previous){[Windows.Forms.Clipboard]::SetText($previous)}else{[Windows.Forms.Clipboard]::Clear()} }
}

function Open-GMTWorkshopUploader {
    param($Configuration,[string]$EvidenceRoot)
    Initialize-GMTIsaacWindowAutomation
    $title=if($Configuration.PSObject.Properties['mainWindowTitle']){[string]$Configuration.mainWindowTitle}else{'The Binding of Isaac: Afterbirth+ Mod Uploader'}
    $explicitPath=if($Configuration.PSObject.Properties['uploaderPath']){[string]$Configuration.uploaderPath}else{''}
    $path=Resolve-GMTIsaacUploaderPath $explicitPath
    $process=Get-Process ModUploader -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $process) { $process=Start-Process -FilePath $path -PassThru }
    Wait-GMTIsaacWindow $process.Id $title 20 | Out-Null
    return [ordered]@{Process=$process;Title=$title;UploadTriggered=$false}
}

function Open-GMTWorkshopProject {
    param($Session,$Item,[string]$EvidenceRoot)
    $Session.UploadTriggered=$false
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title; Click-GMTIsaacRelative $main 0.09 0.16
    Wait-GMTIsaacWindow $Session.Process.Id 'Choose Metadata' 10 | Out-Null
    Submit-GMTIsaacFileDialog $Session.Process.Id 'Choose Metadata' $Item.Facts.MetadataPath $EvidenceRoot
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title; Start-Sleep -Seconds 1
    Save-GMTIsaacEvidence $main $EvidenceRoot "$($Item.Variant.name)-metadata-loaded" | Out-Null
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title; Click-GMTIsaacRelative $main 0.39 0.55
    Wait-GMTIsaacWindow $Session.Process.Id 'Choose Preview' 10 | Out-Null
    Submit-GMTIsaacFileDialog $Session.Process.Id 'Choose Preview' $Item.Facts.RemotePreviewPath $EvidenceRoot
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title; Start-Sleep -Seconds 1
    Save-GMTIsaacEvidence $main $EvidenceRoot "$($Item.Variant.name)-preview-loaded" | Out-Null
}

function Invoke-GMTWorkshopUploadOnce {
    param($Session,$Item,[string]$EvidenceRoot)
    if ($Session.UploadTriggered) { throw '本次上传器会话已经触发过上传，拒绝重复点击。' }
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title; Click-GMTIsaacRelative $main 0.70 0.12
    Set-GMTIsaacText ([string]$Item.ChangeNotes)
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title
    Save-GMTIsaacEvidence $main $EvidenceRoot "$($Item.Variant.name)-before-upload" | Out-Null
    $main=Focus-GMTIsaacWindow $Session.Process.Id $Session.Title
    $Session.UploadTriggered=$true
    Click-GMTIsaacRelative $main 0.26 0.16
}

function Close-GMTWorkshopUploader {
    param($Session)
    if ($Session -and $Session.Process -and -not $Session.Process.HasExited) { $Session.Process.CloseMainWindow() | Out-Null }
}

Export-ModuleMember -Function Open-GMTWorkshopUploader,Open-GMTWorkshopProject,Invoke-GMTWorkshopUploadOnce,Close-GMTWorkshopUploader
