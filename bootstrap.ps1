# ============================================================
# bootstrap.ps1 — Création du Backend Terraform (S3 + DynamoDB)
# À exécuter UNE SEULE FOIS, avant le premier terraform init
# ============================================================
# Usage : .\bootstrap.ps1
# Prérequis : aws configure --profile pfs-soc effectué
# ============================================================

param(
    [string]$Profile = "pfs-soc",
    [string]$Region  = "us-east-1",
    [string]$Email   = "TON_EMAIL@example.com"
)

$ErrorActionPreference = "Stop"

# ── Lire le nom du bucket généré ──────────────────────────────
$BucketFile = ".bootstrap_bucket_name"
if (Test-Path $BucketFile) {
    $BUCKET_NAME = (Get-Content $BucketFile).Trim()
} else {
    $suffix = -join ((48..57) + (97..122) | Get-Random -Count 8 | % {[char]$_})
    $BUCKET_NAME = "pfs-soc-tfstate-$suffix"
    $BUCKET_NAME | Out-File -FilePath $BucketFile -Encoding utf8
}

$DYNAMO_TABLE = "pfs-soc-tfstate-lock"

Write-Host "`n🚀 Bootstrap Backend Terraform" -ForegroundColor Cyan
Write-Host "   Bucket  : $BUCKET_NAME"
Write-Host "   DynamoDB: $DYNAMO_TABLE"
Write-Host "   Region  : $Region`n"

# ── Vérifier l'identité AWS ──────────────────────────────────
Write-Host "🔑 Vérification des credentials AWS..." -ForegroundColor Yellow
$identity = aws sts get-caller-identity --profile $Profile --output json | ConvertFrom-Json
Write-Host "   Account : $($identity.Account)"
Write-Host "   User    : $($identity.Arn)"

# ── Créer le bucket S3 ───────────────────────────────────────
Write-Host "`n📦 Création du bucket S3..." -ForegroundColor Yellow
try {
    aws s3api create-bucket `
        --bucket $BUCKET_NAME `
        --region $Region `
        --profile $Profile | Out-Null
    Write-Host "   ✅ Bucket créé"
} catch {
    Write-Host "   ⚠️  Le bucket existe déjà ou erreur : $_" -ForegroundColor DarkYellow
}

# Versioning
aws s3api put-bucket-versioning `
    --bucket $BUCKET_NAME `
    --versioning-configuration Status=Enabled `
    --profile $Profile
Write-Host "   ✅ Versioning activé"

# Chiffrement AES-256
$encryptConfig = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption `
    --bucket $BUCKET_NAME `
    --server-side-encryption-configuration $encryptConfig `
    --profile $Profile
Write-Host "   ✅ Chiffrement AES-256 activé"

# Bloquer l'accès public
aws s3api put-public-access-block `
    --bucket $BUCKET_NAME `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" `
    --profile $Profile
Write-Host "   ✅ Accès public bloqué"

# ── Créer la table DynamoDB ──────────────────────────────────
Write-Host "`n🗄️  Création de la table DynamoDB..." -ForegroundColor Yellow
try {
    aws dynamodb create-table `
        --table-name $DYNAMO_TABLE `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region `
        --profile $Profile | Out-Null
    Write-Host "   ✅ Table DynamoDB créée"
} catch {
    Write-Host "   ⚠️  La table existe déjà ou erreur : $_" -ForegroundColor DarkYellow
}

# ── Créer l'alarme de budget ─────────────────────────────────
Write-Host "`n💰 Configuration de l'alarme budget AWS ($60)..." -ForegroundColor Yellow
$accountId = $identity.Account
$budgetJson = @"
{
  "BudgetName": "pfs-soc-alert",
  "BudgetLimit": {"Amount": "60", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
"@
$notifJson = @"
[{
  "Notification": {
    "NotificationType": "ACTUAL",
    "ComparisonOperator": "GREATER_THAN",
    "Threshold": 80,
    "ThresholdType": "PERCENTAGE"
  },
  "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$Email"}]
}]
"@

try {
    aws budgets create-budget `
        --account-id $accountId `
        --budget $budgetJson `
        --notifications-with-subscribers $notifJson `
        --profile $Profile | Out-Null
    Write-Host "   ✅ Alarme budget créée (alerte à 80% de $60 = $48)"
} catch {
    Write-Host "   ⚠️  Budget existant ou erreur : $_" -ForegroundColor DarkYellow
}

# ── Mettre à jour backend.tf ─────────────────────────────────
Write-Host "`n📝 Mise à jour de terraform/backend.tf..." -ForegroundColor Yellow
$backendContent = @"
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "global/terraform.tfstate"
    region         = "$Region"
    dynamodb_table = "$DYNAMO_TABLE"
    encrypt        = true
  }
}
"@
$backendContent | Out-File -FilePath "terraform/backend.tf" -Encoding utf8
Write-Host "   ✅ terraform/backend.tf mis à jour"

# ── Résumé final ─────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              ✅  BOOTSTRAP TERMINÉ !                 ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📦 S3 Bucket   : $BUCKET_NAME"
Write-Host "  🗄️  DynamoDB    : $DYNAMO_TABLE"
Write-Host "  📝 backend.tf  : terraform/backend.tf (mis à jour)"
Write-Host ""
Write-Host "  👉 Prochaine étape : Phase 1 — Code Terraform Networking" -ForegroundColor Cyan
Write-Host ""
