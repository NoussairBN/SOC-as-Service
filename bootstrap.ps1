param(
    [string]$Profile = "pfs-soc",
    [string]$Region  = "us-east-1",
    [string]$Email   = "your@email.com"
)

$ErrorActionPreference = "Stop"

# --- Read bucket name ---
$BucketFile = ".bootstrap_bucket_name"
if (Test-Path $BucketFile) {
    $BUCKET_NAME = (Get-Content $BucketFile -Encoding UTF8).Trim()
} else {
    $suffix = -join ((48..57) + (97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $BUCKET_NAME = "pfs-soc-tfstate-$suffix"
    $BUCKET_NAME | Out-File -FilePath $BucketFile -Encoding UTF8
}

$DYNAMO_TABLE = "pfs-soc-tfstate-lock"

Write-Host ""
Write-Host "=== Bootstrap Terraform Backend ===" -ForegroundColor Cyan
Write-Host "  Bucket  : $BUCKET_NAME"
Write-Host "  DynamoDB: $DYNAMO_TABLE"
Write-Host "  Region  : $Region"
Write-Host ""

# --- Verify AWS identity ---
Write-Host "[1/5] Checking AWS credentials..." -ForegroundColor Yellow
$identity = aws sts get-caller-identity --profile $Profile --output json | ConvertFrom-Json
Write-Host "  Account : $($identity.Account)"
Write-Host "  User    : $($identity.Arn)"

# --- Create S3 bucket ---
Write-Host ""
Write-Host "[2/5] Creating S3 bucket..." -ForegroundColor Yellow
try {
    aws s3api create-bucket `
        --bucket $BUCKET_NAME `
        --region $Region `
        --profile $Profile | Out-Null
    Write-Host "  OK: Bucket created"
} catch {
    Write-Host "  SKIP: Bucket already exists or error: $_" -ForegroundColor DarkYellow
}

# Enable versioning
aws s3api put-bucket-versioning `
    --bucket $BUCKET_NAME `
    --versioning-configuration Status=Enabled `
    --profile $Profile | Out-Null
Write-Host "  OK: Versioning enabled"

# Enable encryption
$encryptJson = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption `
    --bucket $BUCKET_NAME `
    --server-side-encryption-configuration $encryptJson `
    --profile $Profile | Out-Null
Write-Host "  OK: AES-256 encryption enabled"

# Block public access
$blockJson = '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
aws s3api put-public-access-block `
    --bucket $BUCKET_NAME `
    --public-access-block-configuration $blockJson `
    --profile $Profile | Out-Null
Write-Host "  OK: Public access blocked"

# --- Create DynamoDB table ---
Write-Host ""
Write-Host "[3/5] Creating DynamoDB table..." -ForegroundColor Yellow
try {
    aws dynamodb create-table `
        --table-name $DYNAMO_TABLE `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region `
        --profile $Profile | Out-Null
    Write-Host "  OK: DynamoDB table created"
} catch {
    Write-Host "  SKIP: Table already exists or error: $_" -ForegroundColor DarkYellow
}

# --- Generate SSH Key if not exists ---
Write-Host ""
Write-Host "[4/5] Checking SSH key..." -ForegroundColor Yellow
$keyPath = "$HOME\.ssh\pfs-soc-key"
if (-not (Test-Path $keyPath)) {
    ssh-keygen -t ed25519 -C "pfs-soc-key" -f $keyPath -N '""'
    Write-Host "  OK: SSH key generated at $keyPath"
} else {
    Write-Host "  SKIP: SSH key already exists at $keyPath"
}
Write-Host "  Public key:"
Get-Content "$keyPath.pub"

# --- Write backend.tf ---
Write-Host ""
Write-Host "[5/5] Writing terraform/backend.tf..." -ForegroundColor Yellow

$backendLines = @(
    'terraform {'
    '  backend "s3" {'
    "    bucket         = `"$BUCKET_NAME`""
    '    key            = "global/terraform.tfstate"'
    "    region         = `"$Region`""
    "    dynamodb_table = `"$DYNAMO_TABLE`""
    '    encrypt        = true'
    '  }'
    '}'
)
$backendLines | Out-File -FilePath "terraform\backend.tf" -Encoding UTF8
Write-Host "  OK: terraform/backend.tf written"

# --- Summary ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  BOOTSTRAP COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  S3 Bucket   : $BUCKET_NAME"
Write-Host "  DynamoDB    : $DYNAMO_TABLE"
Write-Host "  backend.tf  : terraform/backend.tf"
Write-Host "  SSH Key     : $keyPath"
Write-Host ""
Write-Host "Next step: push to GitHub and add Secrets" -ForegroundColor Cyan
Write-Host ""
