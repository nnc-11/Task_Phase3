param(
    [string]$AccountId = "197826770971",
    [string]$Region = "ap-southeast-1",
    [ValidateSet("PreAttach", "PostAttach")]
    [string]$Stage = "PreAttach"
)

$ErrorActionPreference = "Stop"
$boundaryArn = "arn:aws:iam::$AccountId`:policy/techx-corp-tf3-ci-audit-boundary"
$roleNames = @(
    "techx-corp-tf3-gha-terraform-plan",
    "techx-corp-tf3-gha-terraform-apply"
)
$applyRoleArn = "arn:aws:iam::$AccountId`:role/techx-corp-tf3-gha-terraform-apply"
$trailArn = "arn:aws:cloudtrail:$Region`:$AccountId`:trail/techx-corp-tf3-audit-detection-ap-southeast-1-trail"
$bucketArn = "arn:aws:s3:::techx-corp-tf3-audit-trail-ap-southeast-1-$AccountId"
$objectArn = "$bucketArn/AWSLogs/$AccountId/test-object"
$ruleArn = "arn:aws:events:$Region`:$AccountId`:rule/techx-corp-tf3-audit-detection-ap-southeast-1-g1-audit"
$functionArn = "arn:aws:lambda:$Region`:$AccountId`:function:techx-corp-tf3-audit-detection-ap-southeast-1-router"
$topicArn = "arn:aws:sns:$Region`:$AccountId`:techx-corp-tf3-audit-detection-ap-southeast-1-alerts"
$queueArn = "arn:aws:sqs:$Region`:$AccountId`:techx-corp-tf3-audit-detection-ap-southeast-1-router-dlq"
$alarmArn = "arn:aws:cloudwatch:$Region`:$AccountId`:alarm:techx-corp-tf3-m12-audit-heartbeat-missing"
$outsidePassRoleArn = "arn:aws:iam::$AccountId`:role/not-approved-by-m12"
$approvedPassRoleArn = "arn:aws:iam::$AccountId`:role/techx-corp-tf3-example-service-role"
$eksClusterArn = "arn:aws:eks:$Region`:$AccountId`:cluster/techx-corp-tf3"
$auditAlias = "alias/techx-corp-tf3-audit-detection-$Region-audit"
$tempPolicy = Join-Path $env:TEMP "m12-ci-boundary-policy-$PID.json"

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Pass {
    param([string]$Message)
    Write-Host "PASS  $Message" -ForegroundColor Green
}

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
    Write-Host "FAIL  $Message" -ForegroundColor Red
}

function Invoke-AwsJson {
    param(
        [string]$CheckName,
        [string[]]$Arguments
    )

    $raw = & aws @Arguments --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "$CheckName failed: $($raw -join ' ')"
        return $null
    }

    try {
        return ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    }
    catch {
        Add-Failure "$CheckName returned invalid JSON: $($_.Exception.Message)"
        return $null
    }
}

function Test-CustomDecision {
    param(
        [string]$Action,
        [string]$Resource,
        [ValidateSet("allowed", "explicitDeny", "implicitDeny")]
        [string]$Expected,
        [string]$ContextEntry = ""
    )

    $arguments = @(
        "iam", "simulate-custom-policy",
        "--policy-input-list", "file://$tempPolicy",
        "--action-names", $Action,
        "--resource-arns", $Resource
    )
    if ($ContextEntry) {
        $arguments += @("--context-entries", $ContextEntry)
    }

    $simulation = Invoke-AwsJson "custom simulation $Action" $arguments
    if ($null -eq $simulation -or @($simulation.EvaluationResults).Count -ne 1) {
        Add-Failure "$Action returned no unique evaluation result"
        return
    }

    $actual = $simulation.EvaluationResults[0].EvalDecision
    if ($actual -eq $Expected) {
        Add-Pass "$Action on $Resource => $actual"
    }
    else {
        Add-Failure "$Action on $Resource => $actual; expected $Expected"
    }
}

function Test-PrincipalDecision {
    param(
        [string]$Action,
        [string]$Resource,
        [ValidateSet("allowed", "explicitDeny", "implicitDeny")]
        [string]$Expected,
        [string]$ContextEntry = ""
    )

    $arguments = @(
        "iam", "simulate-principal-policy",
        "--policy-source-arn", $applyRoleArn,
        "--action-names", $Action,
        "--resource-arns", $Resource
    )
    if ($ContextEntry) {
        $arguments += @("--context-entries", $ContextEntry)
    }

    $simulation = Invoke-AwsJson "effective simulation $Action" $arguments
    if ($null -eq $simulation -or @($simulation.EvaluationResults).Count -ne 1) {
        Add-Failure "$Action returned no unique effective evaluation result"
        return
    }

    $actual = $simulation.EvaluationResults[0].EvalDecision
    if ($actual -eq $Expected) {
        Add-Pass "effective $Action on $Resource => $actual"
    }
    else {
        Add-Failure "effective $Action on $Resource => $actual; expected $Expected"
    }
}

try {
    Write-Host "Mandate 12 boundary verification - READ ONLY - stage $Stage"

    $policy = Invoke-AwsJson "boundary policy" @(
        "iam", "get-policy",
        "--policy-arn", $boundaryArn
    )
    if ($null -eq $policy) {
        throw "Boundary policy is unavailable."
    }

    $versionId = $policy.Policy.DefaultVersionId
    $policyVersion = Invoke-AwsJson "boundary policy version" @(
        "iam", "get-policy-version",
        "--policy-arn", $boundaryArn,
        "--version-id", $versionId
    )
    if ($null -eq $policyVersion) {
        throw "Boundary policy version is unavailable."
    }

    $policyDocument = $policyVersion.PolicyVersion.Document | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($tempPolicy, $policyDocument)

    $validation = Invoke-AwsJson "Access Analyzer policy validation" @(
        "accessanalyzer", "validate-policy",
        "--region", $Region,
        "--policy-type", "IDENTITY_POLICY",
        "--policy-document", "file://$tempPolicy"
    )
    if ($null -ne $validation) {
        $errorFindings = @($validation.Findings | Where-Object { $_.FindingType -eq "ERROR" })
        if ($errorFindings.Count -gt 0) {
            foreach ($finding in $errorFindings) {
                Add-Failure "Access Analyzer ERROR $($finding.IssueCode): $($finding.FindingDetails)"
            }
        }
        else {
            Add-Pass "Access Analyzer returned no ERROR finding"
        }

        foreach ($finding in @($validation.Findings | Where-Object {
            $_.FindingType -ne "ERROR"
        })) {
            if (
                $finding.FindingType -eq "SECURITY_WARNING" -and
                $finding.IssueCode -ne "PASS_ROLE_WITH_STAR_IN_ACTION_AND_RESOURCE"
            ) {
                Add-Failure "unapproved Access Analyzer SECURITY_WARNING $($finding.IssueCode): $($finding.FindingDetails)"
            }
            else {
                Write-Host "REVIEW $($finding.FindingType) $($finding.IssueCode): $($finding.FindingDetails)" -ForegroundColor Yellow
            }
        }
    }

    $aliases = Invoke-AwsJson "audit KMS alias lookup" @(
        "kms", "list-aliases",
        "--region", $Region
    )
    $aliasObject = @($aliases.Aliases | Where-Object { $_.AliasName -eq $auditAlias })
    $kmsKeyArn = $null
    if ($aliasObject.Count -eq 1 -and $aliasObject[0].TargetKeyId) {
        $kmsKeyArn = "arn:aws:kms:$Region`:$AccountId`:key/$($aliasObject[0].TargetKeyId)"
        Add-Pass "resolved audit KMS key from $auditAlias"
    }
    else {
        Add-Failure "cannot resolve exactly one KMS key for $auditAlias"
    }

    Test-CustomDecision "cloudtrail:StopLogging" $trailArn "explicitDeny"
    Test-CustomDecision "cloudtrail:DeleteTrail" $trailArn "explicitDeny"
    Test-CustomDecision "cloudtrail:PutEventSelectors" $trailArn "explicitDeny"
    Test-CustomDecision "s3:PutBucketPolicy" $bucketArn "explicitDeny"
    Test-CustomDecision "s3:PutBucketObjectLockConfiguration" $bucketArn "explicitDeny"
    Test-CustomDecision "s3:DeleteObjectVersion" $objectArn "explicitDeny"
    Test-CustomDecision "events:DisableRule" $ruleArn "explicitDeny"
    Test-CustomDecision "events:DeleteRule" $ruleArn "explicitDeny"
    Test-CustomDecision "lambda:DeleteFunction" $functionArn "explicitDeny"
    Test-CustomDecision "lambda:UpdateFunctionCode" $functionArn "explicitDeny"
    Test-CustomDecision "sns:DeleteTopic" $topicArn "explicitDeny"
    Test-CustomDecision "sns:SetTopicAttributes" $topicArn "explicitDeny"
    Test-CustomDecision "sns:Unsubscribe" "*" "explicitDeny"
    Test-CustomDecision "sns:SetSubscriptionAttributes" "*" "explicitDeny"
    Test-CustomDecision "sqs:DeleteQueue" $queueArn "explicitDeny"
    Test-CustomDecision "sqs:PurgeQueue" $queueArn "explicitDeny"
    Test-CustomDecision "sqs:SetQueueAttributes" $queueArn "explicitDeny"
    Test-CustomDecision "cloudwatch:DisableAlarmActions" $alarmArn "explicitDeny"
    Test-CustomDecision "iam:CreateRole" "*" "explicitDeny"
    Test-CustomDecision "iam:AttachRolePolicy" "*" "explicitDeny"
    Test-CustomDecision "iam:UpdateAssumeRolePolicy" "*" "explicitDeny"
    Test-CustomDecision "sts:AssumeRole" $outsidePassRoleArn "explicitDeny"
    Test-CustomDecision "iam:PassRole" $outsidePassRoleArn "explicitDeny"
    Test-CustomDecision "iam:PassRole" $approvedPassRoleArn "allowed"
    Test-CustomDecision "eks:DescribeCluster" $eksClusterArn "allowed"

    if ($kmsKeyArn) {
        $kmsContext = "ContextKeyName=kms:ResourceAliases,ContextKeyValues=$auditAlias,ContextKeyType=stringList"
        Test-CustomDecision "kms:DisableKey" $kmsKeyArn "explicitDeny" $kmsContext
        Test-CustomDecision "kms:PutKeyPolicy" $kmsKeyArn "explicitDeny" $kmsContext
        Test-CustomDecision "kms:ScheduleKeyDeletion" $kmsKeyArn "explicitDeny" $kmsContext
    }

    foreach ($roleName in $roleNames) {
        $role = Invoke-AwsJson "role boundary $roleName" @(
            "iam", "get-role",
            "--role-name", $roleName
        )
        if ($null -eq $role) {
            continue
        }

        $actualBoundary = $role.Role.PermissionsBoundary.PermissionsBoundaryArn
        if ($Stage -eq "PreAttach") {
            if ($actualBoundary) {
                Add-Failure "$roleName is unexpectedly attached before the attach phase"
            }
            else {
                Add-Pass "$roleName remains unattached before the attach phase"
            }
        }
        elseif ($actualBoundary -eq $boundaryArn) {
            Add-Pass "$roleName has the exact boundary"
        }
        else {
            Add-Failure "$roleName boundary is '$actualBoundary'; expected $boundaryArn"
        }
    }

    if ($Stage -eq "PostAttach") {
        Test-PrincipalDecision "cloudtrail:StopLogging" $trailArn "explicitDeny"
        Test-PrincipalDecision "iam:CreateRole" "*" "explicitDeny"
        Test-PrincipalDecision "iam:PassRole" $outsidePassRoleArn "explicitDeny"
        Test-PrincipalDecision "eks:DescribeCluster" $eksClusterArn "allowed"
    }
}
catch {
    Add-Failure $_.Exception.Message
}
finally {
    if (Test-Path -LiteralPath $tempPolicy) {
        Remove-Item -LiteralPath $tempPolicy -Force
    }
}

Write-Host ""
Write-Host "Summary: $($failures.Count) failure(s)"
foreach ($failure in $failures) {
    Write-Host "FAIL  $failure" -ForegroundColor Red
}

if ($failures.Count -gt 0) {
    exit 1
}

Write-Host "Boundary verification passed. No AWS state was changed." -ForegroundColor Green
exit 0
