
Function TestInstalledFonts {
	Clear-Host
	$fonts = @(
		"SimSun", # Chinese (Mandarin)
		"Microsoft JhengHei", # Chinese (Cantonese)
		"Malgun Gothic", # Korean
		"Arial", # Russian
		"Arial", # Arabic
		"Meiryo" # Japanese
	)
	
	ForEach ($font In $fonts) {
		If ((Get-ChildItem "C:\Windows\Fonts" -Recurse | Where-Object { $_.Name -eq "$font.ttf" }).Count -eq 0) {
			Write-Host "Font for $font is not installed." -ForegroundColor Red
		} Else {
			Write-Host "Font for $font is installed." -ForegroundColor Green
		}
	}
}
