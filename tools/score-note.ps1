param([ValidateSet('check','windows','android')][string]$Action = 'check', [string]$DeviceId)
$ErrorActionPreference = 'Stop'
$onPath = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($onPath) { $onPath.Source } else { Join-Path $env:LOCALAPPDATA 'ScoreNoteTools\flutter\bin\flutter.bat' }
if (!(Test-Path -LiteralPath $flutter)) { throw 'Please install Flutter or add flutter to PATH.' }
Push-Location (Join-Path $PSScriptRoot '..')
try {
  & $flutter pub get
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  switch ($Action) {
    'check' { & $flutter analyze; if ($LASTEXITCODE) {exit $LASTEXITCODE}; & $flutter test }
    'windows' { & $flutter run -d windows }
    'android' { if ($DeviceId) { & $flutter run -d $DeviceId } else { & $flutter build apk --debug } }
  }
  exit $LASTEXITCODE
} finally { Pop-Location }
