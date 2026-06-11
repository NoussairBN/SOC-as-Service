$content = Get-Content D:\DevSecOps\pfs\SOC-as-Service\custom_rules_utf8.xml -Raw

# Remove the duplicate 100040 rules that got added incorrectly
$parts = $content -split '<rule id="100040" level="10">'
if ($parts.Count -gt 1) {
    # We will just rewrite the file from scratch using our template to ensure it is 100% correct
}
