# Create example task ZIP for testing (Windows)

Write-Host "Creating example task ZIP..." -ForegroundColor Cyan

$sourcePath = "examples\simple-task"
$destPath = "simple-task-example.zip"

if (Test-Path $destPath) {
    Remove-Item $destPath -Force
}

Compress-Archive -Path "$sourcePath\*" -DestinationPath $destPath -Force

if (Test-Path $destPath) {
    $size = (Get-Item $destPath).Length / 1KB
    Write-Host "✅ Created: simple-task-example.zip" -ForegroundColor Green
    Write-Host "   Size: $([math]::Round($size, 2)) KB" -ForegroundColor Gray
    Write-Host ""
    Write-Host "You can now test this by uploading it to your Autobuild Web app!" -ForegroundColor Yellow
} else {
    Write-Host "❌ Failed to create ZIP" -ForegroundColor Red
    exit 1
}
