$content = Get-Content D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml
$content = $content -replace '<url>script>\|%3cscript\|javascript:\|onerror=\|onload=\|onmouseover=\|eval\\(\|document\\\.cookie\|alert\\(\|prompt\\(\|confirm\\(\|String\\\.fromCharCode\|&#x\|%3c%73%63%72%69%70%74</url>', '<url>script%3E|script%3e|%3Cscript|%3cscript|javascript:|onerror=|onload=|onmouseover=|eval\(|eval%28|document\.cookie|alert\(|alert%28|prompt\(|prompt%28|confirm\(|confirm%28|&#x</url>'
$content = $content -replace '/dvwa/vulnerabilities/', '/vulnerabilities/'
Set-Content -Path D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml -Value $content -Encoding utf8
