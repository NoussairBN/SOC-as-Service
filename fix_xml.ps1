$content = Get-Content D:\DevSecOps\pfs\SOC-as-Service\custom_rules.xml
$content = $content -replace '<if_sid>31103</if_sid>', '<if_sid>31100</if_sid>'
$content = $content -replace '<if_matched_sid>31103</if_matched_sid>', '<if_matched_sid>31100</if_matched_sid>'
Set-Content -Path D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml -Value $content -Encoding utf8
