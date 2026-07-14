param(
  [string]$Name
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$railsRoot = Join-Path $repoRoot "railsapp"

if ([string]::IsNullOrWhiteSpace($Name)) {
  $Name = "wos_live_latest_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($Name)
$tmpRelative = "tmp/$baseName.png"
$fixtureRelative = "spec/fixtures/files/wos/$baseName.png"

$captureRuby = @"
require 'base64'
config = ObsConfig.first || ObsConfig.new
source = AffordanceConfig.fetch!(:wos_brain).screenshot_source_name.presence
out = Rails.root.join('$tmpRelative')
request_data = { 'imageFormat' => 'png', 'imageWidth' => 1280, 'imageHeight' => 720 }
request_data['sourceName'] = source if source
runner = ObsBridge::ObswsSessionRunner.new(host: config.host, port: config.port)
runner.run do |session|
  result = session.apply_request({ 'requestType' => 'GetSourceScreenshot', 'requestData' => request_data })
  encoded = result.fetch('imageData').to_s.sub(%r{\Adata:image/[a-zA-Z0-9.+-]+;base64,}, '')
  File.binwrite(out, Base64.decode64(encoded))
  puts out.to_s
end
"@

Push-Location $railsRoot
try {
  bash ./dev.sh runner $captureRuby

  $tmpPath = Join-Path $railsRoot ($tmpRelative -replace '/', [IO.Path]::DirectorySeparatorChar)
  $fixturePath = Join-Path $railsRoot ($fixtureRelative -replace '/', [IO.Path]::DirectorySeparatorChar)
  New-Item -ItemType Directory -Force -Path (Split-Path $fixturePath) | Out-Null
  Copy-Item -LiteralPath $tmpPath -Destination $fixturePath -Force

  $summaryRuby = @"
require 'json'
path = Rails.root.join('$fixtureRelative').to_s
result = Wos::ScreenshotRecognizer.new.call(path).to_h
puts JSON.pretty_generate({
  fixture: File.basename(path),
  letters: result[:letters].map { |tile| tile[:char] }.join,
  remaining_words: result[:remaining_words],
  solved_words: result[:solved_words].map { |row| {
    state: row[:state],
    word_length: row[:word_length],
    filled_count: row[:filled_count],
    correct_word: row[:correct_word],
    player: row[:player],
    raw_text: row[:raw_text]
  } }
})
"@

  bash ./dev.sh runner $summaryRuby

  Write-Output "tmp_path=$tmpPath"
  Write-Output "fixture_path=$fixturePath"
}
finally {
  Pop-Location
}