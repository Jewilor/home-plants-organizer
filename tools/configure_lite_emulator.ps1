<#
.SYNOPSIS
Создаёт облегчённый эмулятор Android 16 для проверки приложения.
.DESCRIPTION
Использует установленный образ Google APIs x86_64, два с половиной гигабайта памяти,
четыре ядра и аппаратную графику. Другие виртуальные устройства сохраняются.
.EXAMPLE
.\tools\configure_lite_emulator.ps1 -SdkPath 'D:\Android\Sdk' -JavaHome 'D:\Android-Studio\jbr'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SdkPath,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$AvdName = 'Plants_Lite_API_36',
    [string]$AvdRoot,
    [string]$AndroidUserHome
)

$ErrorActionPreference = 'Stop'
$SdkPath = (Get-Item -LiteralPath $SdkPath).FullName
if ($AvdName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Недопустимое имя виртуального устройства.' }
if (-not $AvdRoot) { $AvdRoot = Join-Path (Split-Path -Parent $SdkPath) 'avd' }
if (-not $AndroidUserHome) {
    $AndroidUserHome = $env:ANDROID_USER_HOME
    if (-not $AndroidUserHome) {
        $AndroidUserHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android'
    }
}
$AvdRoot = [IO.Path]::GetFullPath($AvdRoot)
$manager = Join-Path $SdkPath 'cmdline-tools\latest\bin\avdmanager.bat'
$image = Join-Path $SdkPath 'system-images\android-36\google_apis\x86_64\source.properties'
if (-not (Test-Path -LiteralPath $manager)) { throw 'В Android SDK отсутствуют Command-line Tools (latest).' }
if (-not (Test-Path -LiteralPath $image)) { throw 'Установите системный образ Google APIs x86_64 для Android 16 (API 36) через SDK Manager.' }
if ($JavaHome) { $env:JAVA_HOME = (Get-Item -LiteralPath $JavaHome).FullName }
$env:ANDROID_HOME = $SdkPath
$env:ANDROID_USER_HOME = $AndroidUserHome
$indexRoot = Join-Path $AndroidUserHome 'avd'
$env:ANDROID_AVD_HOME = $indexRoot
$devicePath = Join-Path $AvdRoot ($AvdName + '.avd')
$indexPath = Join-Path $indexRoot ($AvdName + '.ini')
$adb = Join-Path $SdkPath 'platform-tools\adb.exe'

# Не менять конфигурацию работающего устройства.
$devices = & $adb devices
foreach ($line in $devices) {
    if ($line -match '^(emulator-\d+)\s+device$') {
        $serial = $Matches[1]
        $runningName = & $adb -s $serial emu avd name
        if ($runningName -contains $AvdName) { throw "Сначала остановите эмулятор $AvdName." }
    }
}

if (-not (Test-Path -LiteralPath $indexPath)) {
    if (Test-Path -LiteralPath $devicePath) { throw 'Каталог устройства уже существует без записи в диспетчере. Данные не перезаписывались.' }
    New-Item -ItemType Directory -Force -Path $AvdRoot,$indexRoot | Out-Null
    'no' | & $manager create avd --name $AvdName --package 'system-images;android-36;google_apis;x86_64' --device 'medium_phone' --path $devicePath
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать виртуальное устройство.' }
}

$registeredPath = Get-Content -LiteralPath $indexPath | Where-Object { $_ -match '^path=' } | Select-Object -First 1
if (-not $registeredPath -or [IO.Path]::GetFullPath($registeredPath.Substring(5)) -ne $devicePath) {
    throw 'Устройство зарегистрировано в другом каталоге. Укажите его родительский каталог в AvdRoot.'
}

$configPath = Join-Path $devicePath 'config.ini'
$text = [IO.File]::ReadAllText($configPath)
$settings = [ordered]@{
    'avd.ini.displayname' = 'Plants Lite API 36'
    'hw.ramSize' = '2560'
    'hw.cpu.ncore' = '4'
    'hw.gpu.enabled' = 'yes'
    'hw.gpu.mode' = 'host'
    'hw.lcd.width' = '720'
    'hw.lcd.height' = '1600'
    'hw.lcd.density' = '280'
    'vm.heapSize' = '256'
    'showDeviceFrame' = 'no'
    'skin.dynamic' = 'yes'
    'skin.name' = '720x1600'
    'fastboot.forceColdBoot' = 'yes'
    'fastboot.forceFastBoot' = 'no'
    # Обычная загрузка не восстанавливает проблемное сохранённое состояние.
    'firstboot.bootFromDownloadableSnapshot' = 'no'
    'firstboot.bootFromLocalSnapshot' = 'no'
    'firstboot.saveToLocalSnapshot' = 'no'
    'disk.dataPartition.size' = '6G'
}
foreach ($key in $settings.Keys) {
    $pattern = '(?m)^' + [regex]::Escape($key) + '=.*$'
    $value = $key + '=' + $settings[$key]
    if ([regex]::IsMatch($text, $pattern)) { $text = [regex]::Replace($text, $pattern, $value) }
    else { $text = $text.TrimEnd() + "`r`n" + $value + "`r`n" }
}
[IO.File]::WriteAllText($configPath, $text, [Text.UTF8Encoding]::new($false))
Write-Output "Эмулятор $AvdName настроен: API 36, 2560 МиБ, 4 ядра, 720x1600, аппаратная графика."
Write-Output "Конфигурация: $configPath"
