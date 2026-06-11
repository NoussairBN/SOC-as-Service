$content = Get-Content D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml -Raw
$parts = $content -split '<rule id="100040" level="10">'
$rule40_body = $parts[1] -split '</rule>'
$rule40_full = '<rule id="100040" level="10">' + $rule40_body[0] + '</rule>'

$content = $content.Replace($rule40_full, '')
$content = $content.Replace('<!-- SQL Injection: patterns', $rule40_full + "`r`n`r`n  <!-- SQL Injection: patterns")

Set-Content -Path D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml -Value $content -Encoding utf8
