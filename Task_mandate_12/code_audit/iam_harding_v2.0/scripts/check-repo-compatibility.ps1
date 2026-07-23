param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [ValidateSet("Baseline", "Seed", "Guarded", "Attach")]
    [string]$Stage = "Baseline"
)

$ErrorActionPreference = "Stop"
$expectedBaseSha = "3c8ebd3953c2e017b2176aced2df058c42a92a8b"
$handoffRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Pass {
    param([string]$Message)
    Write-Host "PASS  $Message" -ForegroundColor Green
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message)
    Write-Host "WARN  $Message" -ForegroundColor Yellow
}

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
    Write-Host "FAIL  $Message" -ForegroundColor Red
}

function Get-RepoFile {
    param([string]$RelativePath)
    $path = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "missing product file: $RelativePath"
        return $null
    }
    return $path
}

function Test-Pattern {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )
    $path = Get-RepoFile $RelativePath
    if ($null -eq $path) {
        return
    }
    $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
    if ($content -match $Pattern) {
        Add-Pass $Description
    }
    else {
        Add-Failure "$Description ($RelativePath)"
    }
}

function Test-ExactOverlay {
    param(
        [string]$SourceRelativePath,
        [string]$DestinationRelativePath
    )
    $source = Join-Path $handoffRoot $SourceRelativePath
    $destination = Get-RepoFile $DestinationRelativePath
    if ($null -eq $destination) {
        return
    }
    $sourceContent = (Get-Content -LiteralPath $source -Raw -Encoding utf8) -replace "`r`n", "`n"
    $destinationContent = (Get-Content -LiteralPath $destination -Raw -Encoding utf8) -replace "`r`n", "`n"
    if ($sourceContent -ceq $destinationContent) {
        Add-Pass "exact overlay mapped: $DestinationRelativePath"
    }
    else {
        Add-Failure "overlay differs from handoff source: $DestinationRelativePath"
    }
}

Write-Host "Mandate 12 repo compatibility - READ ONLY - stage $Stage"

$requiredBaselineFiles = @(
    "infra/bootstrap/github-oidc/backend.tf",
    "infra/bootstrap/github-oidc/main.tf",
    "infra/bootstrap/github-oidc/variables.tf",
    "infra/bootstrap/github-oidc/ci-audit-boundary.tf",
    "infra/live/production/audit-heartbeat.tf",
    "infra/live/production/m12-variables.tf",
    "infra/live/production/production.auto.tfvars",
    ".github/workflows/terraform-apply.yml"
)
foreach ($relativePath in $requiredBaselineFiles) {
    [void](Get-RepoFile $relativePath)
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$head = & git -c "safe.directory=$repo" -C $repo rev-parse HEAD 2>&1
$gitExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($gitExitCode -eq 0) {
    $headSha = ($head -join "").Trim()
    if ($headSha -eq $expectedBaseSha) {
        Add-Pass "repo HEAD matches reviewed base $expectedBaseSha"
    }
    else {
        $ErrorActionPreference = "Continue"
        & git -c "safe.directory=$repo" -C $repo merge-base --is-ancestor $expectedBaseSha $headSha 2>$null
        $isDescendant = $LASTEXITCODE -eq 0
        $ErrorActionPreference = $previousErrorActionPreference
        if ($isDescendant) {
            Add-Pass "repo HEAD $headSha descends from reviewed base"
        }
        else {
            Add-Warning "repo HEAD is $headSha and not proven descendant of reviewed base $expectedBaseSha; perform three-way review"
        }
    }
}
else {
    Add-Failure "cannot read repo HEAD: $($head -join ' ')"
}

Test-Pattern "infra/bootstrap/github-oidc/main.tf" `
    'resource\s+"aws_iam_role"\s+"terraform_plan"' `
    "bootstrap root still owns the GHA plan role"
Test-Pattern "infra/bootstrap/github-oidc/main.tf" `
    'resource\s+"aws_iam_role"\s+"terraform_apply"' `
    "bootstrap root still owns the GHA apply role"
Test-Pattern ".github/workflows/terraform-apply.yml" `
    'name:\s+Create saved plan' `
    "production workflow still creates a saved plan"
Test-Pattern ".github/workflows/terraform-apply.yml" `
    'name:\s+Upload saved plan' `
    "production workflow still uploads the saved plan"
Test-Pattern "infra/live/production/audit-heartbeat.tf" `
    'BOUNDED_PRINCIPALS_JSON' `
    "heartbeat supports bounded-principal monitoring"
Test-Pattern "infra/live/production/m12-variables.tf" `
    'variable\s+"audit_detection_bounded_principals"' `
    "production root exposes the heartbeat boundary map"

if ($Stage -in @("Seed", "Guarded", "Attach")) {
    Test-ExactOverlay `
        "repo_overlay/infra/bootstrap/github-oidc/ci-audit-boundary.tf" `
        "infra/bootstrap/github-oidc/ci-audit-boundary.tf"

    Test-Pattern "infra/bootstrap/github-oidc/main.tf" `
        'state_bucket_name\}/\$\{var\.bootstrap_state_key\}' `
        "plan role reads the exact bootstrap state variable"
    Test-Pattern "infra/bootstrap/github-oidc/main.tf" `
        'state_bucket_name\}/\$\{var\.state_key\}' `
        "plan role retains production state read access"
    Test-Pattern "infra/bootstrap/github-oidc/variables.tf" `
        '(?s)variable\s+"bootstrap_state_key"\s*\{.*?default\s*=\s*"bootstrap/github-oidc/terraform\.tfstate"' `
        "bootstrap_state_key has the exact reviewed default"
    Test-Pattern "infra/bootstrap/github-oidc/variables.tf" `
        '(?s)variable\s+"additional_bounded_principal_arns"\s*\{.*?default\s*=\s*\[\s*\]' `
        "additional bounded principals default is empty"

    $codeownersPath = Get-RepoFile ".github/CODEOWNERS"
    if ($null -ne $codeownersPath) {
        $codeowners = Get-Content -LiteralPath $codeownersPath -Raw -Encoding utf8
        if ($codeowners -match '<SECURITY_OWNER>|<PLATFORM_OWNER>') {
            Add-Failure "CODEOWNERS still contains placeholder"
        }
        elseif (
            $codeowners.Contains("/scripts/ci/m12-terraform-scope-gate.py") -and
            $codeowners.Contains("/infra/bootstrap/github-oidc/") -and
            $codeowners.Contains("/infra/live/production/audit-heartbeat.tf") -and
            $codeowners.Contains("/infra/live/production/m12-iam-hardening.auto.tfvars")
        ) {
            Add-Pass "CODEOWNERS protects gate/bootstrap/heartbeat paths"
        }
        else {
            Add-Failure "CODEOWNERS does not protect every required Mandate 12 path"
        }
    }
}

if ($Stage -in @("Guarded", "Attach")) {
    Test-ExactOverlay `
        "repo_overlay/.github/workflows/terraform-bootstrap-plan.yml" `
        ".github/workflows/terraform-bootstrap-plan.yml"
    Test-ExactOverlay `
        "repo_overlay/scripts/ci/m12-terraform-scope-gate.py" `
        "scripts/ci/m12-terraform-scope-gate.py"

    $workflowPath = Get-RepoFile ".github/workflows/terraform-apply.yml"
    if ($null -ne $workflowPath) {
        $workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding utf8
        if ($workflow.Contains("terraform show -json tfplan > tfplan.json")) {
            Add-Pass "production workflow exports the exact saved plan as JSON"
        }
        else {
            Add-Failure "production workflow does not export tfplan.json"
        }
        if ($workflow.Contains("python ../../../scripts/ci/m12-terraform-scope-gate.py tfplan.json")) {
            Add-Pass "production workflow invokes the mapped scope gate"
        }
        else {
            Add-Failure "production workflow scope-gate command/path differs"
        }
        $gateIndex = $workflow.IndexOf("m12-terraform-scope-gate.py")
        $uploadIndex = $workflow.IndexOf("name: Upload saved plan")
        if ($gateIndex -ge 0 -and $uploadIndex -ge 0 -and $gateIndex -lt $uploadIndex) {
            Add-Pass "scope gate runs before saved-plan upload"
        }
        else {
            Add-Failure "scope gate must run before saved-plan upload"
        }
    }
}

$variablesPath = Get-RepoFile "infra/bootstrap/github-oidc/variables.tf"
if ($null -ne $variablesPath -and $Stage -in @("Seed", "Guarded", "Attach")) {
    $variables = Get-Content -LiteralPath $variablesPath -Raw -Encoding utf8
    $expectedDefault = if ($Stage -eq "Attach") { "true" } else { "false" }
    $enableBlock = [regex]::Match(
        $variables,
        '(?s)variable\s+"enable_ci_audit_boundary"\s*\{.*?default\s*=\s*(true|false).*?\}'
    )
    if ($enableBlock.Success -and $enableBlock.Groups[1].Value -eq $expectedDefault) {
        Add-Pass "tracked boundary default is $expectedDefault for stage $Stage"
    }
    else {
        Add-Failure "tracked boundary default must be $expectedDefault for stage $Stage"
    }
}

if ($Stage -eq "Attach") {
    Test-ExactOverlay `
        "repo_overlay/infra/live/production/m12-iam-hardening.auto.tfvars" `
        "infra/live/production/m12-iam-hardening.auto.tfvars"

    $productionRoot = Join-Path $repo "infra/live/production"
    $boundaryAssignments = @(
        Get-ChildItem -LiteralPath $productionRoot -File -Filter "*.tfvars" |
            Select-String -Pattern '^\s*audit_detection_bounded_principals\s*='
    )
    if ($boundaryAssignments.Count -eq 1) {
        Add-Pass "heartbeat boundary map is assigned exactly once"
    }
    else {
        Add-Failure "heartbeat boundary map must be assigned exactly once, found $($boundaryAssignments.Count)"
    }
}

Write-Host ""
Write-Host "Summary: $($failures.Count) failure(s), $($warnings.Count) warning(s)"
if ($failures.Count -gt 0) {
    exit 1
}

Write-Host "COMPATIBLE for mapping stage $Stage. No file or AWS state was changed." -ForegroundColor Green
exit 0
