param(
    [string]$Region = "ap-southeast-1",
    [string]$AccountId = "197826770971",
    [Parameter(Mandatory = $true)]
    [string]$DeploymentUserName,
    [ValidateSet("Foundation", "PreAttach", "PostAttach")]
    [string]$Stage = "Foundation",
    [int]$MinimumObjectLockDays = 365,
    [int]$MinimumLifecycleDays = 400
)

$ErrorActionPreference = "Stop"
$trailName = "techx-corp-tf3-audit-detection-ap-southeast-1-trail"
$auditBucket = "techx-corp-tf3-audit-trail-ap-southeast-1-$AccountId"
$heartbeatName = "techx-corp-tf3-m12-audit-heartbeat"
$scheduleName = "techx-corp-tf3-m12-audit-heartbeat-schedule"
$scheduleArn = "arn:aws:events:$Region`:$AccountId`:rule/$scheduleName"
$heartbeatArn = "arn:aws:lambda:$Region`:$AccountId`:function:$heartbeatName"
$boundaryArn = "arn:aws:iam::$AccountId`:policy/techx-corp-tf3-ci-audit-boundary"
$requiredDataEventArn = "arn:aws:s3:::techx-tf3-$AccountId-tfstate/"
$roleNames = @(
    "techx-corp-tf3-gha-terraform-plan",
    "techx-corp-tf3-gha-terraform-apply"
)
$expectedBoundaryMap = @{
    "arn:aws:iam::$AccountId`:role/techx-corp-tf3-gha-terraform-plan"  = $boundaryArn
    "arn:aws:iam::$AccountId`:role/techx-corp-tf3-gha-terraform-apply" = $boundaryArn
}
$expectedAlarmNames = @(
    "$heartbeatName-missing",
    "$heartbeatName-errors"
)
$topics = @(
    @{
        Name   = "primary"
        Region = $Region
        Arn    = "arn:aws:sns:$Region`:$AccountId`:techx-corp-tf3-audit-detection-$Region-alerts"
    },
    @{
        Name   = "global"
        Region = "us-east-1"
        Arn    = "arn:aws:sns:us-east-1:$AccountId`:techx-corp-tf3-audit-detection-us-east-1-alerts"
    },
    @{
        Name   = "fallback"
        Region = $Region
        Arn    = "arn:aws:sns:$Region`:$AccountId`:techx-corp-tf3-m12-audit-heartbeat-fallback"
    }
)

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
    Write-Host "NO-GO $Message" -ForegroundColor Red
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

function Test-RecentTimestamp {
    param(
        [string]$CheckName,
        [object]$Value,
        [int]$MaximumAgeMinutes
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        Add-Failure "$CheckName is missing"
        return
    }

    try {
        $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$Value)
        if ($age.TotalMinutes -gt $MaximumAgeMinutes) {
            Add-Failure "$CheckName is $([math]::Round($age.TotalMinutes, 1)) minutes old; maximum is $MaximumAgeMinutes"
        }
        else {
            Add-Pass "$CheckName is fresh ($([math]::Round($age.TotalMinutes, 1)) minutes)"
        }
    }
    catch {
        Add-Failure "$CheckName cannot be parsed: $Value"
    }
}

Write-Host "Mandate 12 IAM preflight - READ ONLY - stage $Stage"

$caller = Invoke-AwsJson "STS caller identity" @("sts", "get-caller-identity")
if ($null -ne $caller) {
    if ($caller.Account -eq $AccountId) {
        Add-Pass "caller is in account $AccountId"
    }
    else {
        Add-Failure "caller account is $($caller.Account), expected $AccountId"
    }

    if ($caller.Arn -match ":root$") {
        Add-Failure "root session must not deploy this change"
    }
    else {
        Add-Pass "caller is not root: $($caller.Arn)"
    }
}

$mfa = Invoke-AwsJson "named deployment MFA" @(
    "iam", "list-mfa-devices",
    "--user-name", $DeploymentUserName
)
if ($null -ne $mfa) {
    if (@($mfa.MFADevices).Count -gt 0) {
        Add-Pass "named deployment user $DeploymentUserName has an MFA device"
    }
    else {
        Add-Failure "named deployment user $DeploymentUserName has no MFA device"
    }
}

$accountSummary = Invoke-AwsJson "account/root summary" @("iam", "get-account-summary")
if ($null -ne $accountSummary) {
    if ([int]$accountSummary.SummaryMap.AccountMFAEnabled -eq 1) {
        Add-Pass "root/account MFA is enabled"
    }
    else {
        Add-Failure "root/account MFA is not enabled"
    }

    if ([int]$accountSummary.SummaryMap.AccountAccessKeysPresent -eq 0) {
        Add-Pass "root has no access key"
    }
    else {
        Add-Failure "root access key exists"
    }
}

$trail = Invoke-AwsJson "CloudTrail status" @(
    "cloudtrail", "get-trail-status",
    "--region", $Region,
    "--name", $trailName
)
if ($null -ne $trail) {
    if ($trail.IsLogging -eq $true) {
        Add-Pass "CloudTrail is logging"
    }
    else {
        Add-Failure "CloudTrail IsLogging is not true"
    }

    if ([string]::IsNullOrWhiteSpace([string]$trail.LatestDeliveryError)) {
        Add-Pass "CloudTrail has no latest delivery error"
    }
    else {
        Add-Failure "CloudTrail delivery error: $($trail.LatestDeliveryError)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$trail.LatestDigestDeliveryError)) {
        Add-Pass "CloudTrail has no latest digest delivery error"
    }
    else {
        Add-Failure "CloudTrail digest delivery error: $($trail.LatestDigestDeliveryError)"
    }

    Test-RecentTimestamp "latest log delivery" $trail.LatestDeliveryTime 40
    Test-RecentTimestamp "latest digest delivery" $trail.LatestDigestDeliveryTime 90
}

$selectors = Invoke-AwsJson "CloudTrail selectors" @(
    "cloudtrail", "get-event-selectors",
    "--region", $Region,
    "--trail-name", $trailName
)
if ($null -ne $selectors) {
    $managementCovered = @($selectors.EventSelectors | Where-Object {
        $_.IncludeManagementEvents -eq $true -and $_.ReadWriteType -eq "All"
    }).Count -gt 0

    $advancedReadOnlyValues = [System.Collections.Generic.List[string]]::new()
    foreach ($selector in @($selectors.AdvancedEventSelectors)) {
        $categoryFields = @($selector.FieldSelectors | Where-Object {
            $_.Field -eq "eventCategory" -and $_.Equals -contains "Management"
        })
        if ($categoryFields.Count -eq 0) {
            continue
        }

        # Không filter field readOnly nghĩa là selector lấy cả read và write.
        $readOnlyFields = @($selector.FieldSelectors | Where-Object {
            $_.Field -eq "readOnly"
        })
        if ($readOnlyFields.Count -eq 0) {
            $managementCovered = $true
            break
        }
        foreach ($field in $readOnlyFields) {
            @($field.Equals) | ForEach-Object {
                $advancedReadOnlyValues.Add(([string]$_).ToLowerInvariant())
            }
        }
    }
    if (
        $advancedReadOnlyValues -contains "true" -and
        $advancedReadOnlyValues -contains "false"
    ) {
        $managementCovered = $true
    }

    if ($managementCovered) {
        Add-Pass "management read/write events are covered"
    }
    else {
        Add-Failure "management read/write event coverage is missing"
    }

    $dataEventValues = [System.Collections.Generic.List[string]]::new()
    @(
        $selectors.EventSelectors |
            ForEach-Object { $_.DataResources } |
            Where-Object { $_.Type -eq "AWS::S3::Object" } |
            ForEach-Object { $_.Values }
    ) | ForEach-Object { $dataEventValues.Add([string]$_) }

    foreach ($selector in @($selectors.AdvancedEventSelectors)) {
        $isDataSelector = @($selector.FieldSelectors | Where-Object {
            $_.Field -eq "eventCategory" -and $_.Equals -contains "Data"
        }).Count -gt 0
        $isS3Selector = @($selector.FieldSelectors | Where-Object {
            $_.Field -eq "resources.type" -and $_.Equals -contains "AWS::S3::Object"
        }).Count -gt 0
        if (-not ($isDataSelector -and $isS3Selector)) {
            continue
        }

        @(
            $selector.FieldSelectors |
                Where-Object { $_.Field -eq "resources.ARN" } |
                ForEach-Object { $_.StartsWith }
        ) | ForEach-Object { $dataEventValues.Add([string]$_) }
    }

    if ($dataEventValues -contains $requiredDataEventArn) {
        Add-Pass "required S3 object data-event ARN is covered"
    }
    else {
        Add-Failure "missing S3 object data-event ARN $requiredDataEventArn"
    }
}

$objectLock = Invoke-AwsJson "audit bucket Object Lock" @(
    "s3api", "get-object-lock-configuration",
    "--bucket", $auditBucket,
    "--region", $Region
)
if ($null -ne $objectLock) {
    $retention = $objectLock.ObjectLockConfiguration.Rule.DefaultRetention
    if (
        $objectLock.ObjectLockConfiguration.ObjectLockEnabled -eq "Enabled" -and
        $retention.Mode -eq "COMPLIANCE" -and
        [int]$retention.Days -ge $MinimumObjectLockDays
    ) {
        Add-Pass "Object Lock is COMPLIANCE $($retention.Days) days"
    }
    else {
        Add-Failure "Object Lock must be COMPLIANCE >= $MinimumObjectLockDays days"
    }
}

$lifecycle = Invoke-AwsJson "audit bucket lifecycle" @(
    "s3api", "get-bucket-lifecycle-configuration",
    "--bucket", $auditBucket,
    "--region", $Region
)
if ($null -ne $lifecycle) {
    $enabledRules = @($lifecycle.Rules | Where-Object { $_.Status -eq "Enabled" })
    $currentExpirations = @(
        $enabledRules |
            Where-Object { $null -ne $_.Expiration -and $null -ne $_.Expiration.Days } |
            ForEach-Object { [int]$_.Expiration.Days }
    )
    $noncurrentExpirations = @(
        $enabledRules |
            Where-Object {
                $null -ne $_.NoncurrentVersionExpiration -and
                $null -ne $_.NoncurrentVersionExpiration.NoncurrentDays
            } |
            ForEach-Object { [int]$_.NoncurrentVersionExpiration.NoncurrentDays }
    )

    if (
        $currentExpirations.Count -gt 0 -and
        ($currentExpirations | Measure-Object -Minimum).Minimum -ge $MinimumLifecycleDays
    ) {
        Add-Pass "current object lifecycle is >= $MinimumLifecycleDays days"
    }
    else {
        Add-Failure "current object lifecycle must be >= $MinimumLifecycleDays days"
    }

    if (
        $noncurrentExpirations.Count -gt 0 -and
        ($noncurrentExpirations | Measure-Object -Minimum).Minimum -ge $MinimumLifecycleDays
    ) {
        Add-Pass "noncurrent object lifecycle is >= $MinimumLifecycleDays days"
    }
    else {
        Add-Failure "noncurrent object lifecycle must be >= $MinimumLifecycleDays days"
    }
}

$lambda = Invoke-AwsJson "heartbeat Lambda" @(
    "lambda", "get-function-configuration",
    "--region", $Region,
    "--function-name", $heartbeatName
)
if ($null -ne $lambda) {
    if ($lambda.State -eq "Active") {
        Add-Pass "heartbeat Lambda is Active"
    }
    else {
        Add-Failure "heartbeat Lambda state is $($lambda.State)"
    }

    if ($Stage -eq "PostAttach") {
        try {
            $boundedPrincipals = $lambda.Environment.Variables.BOUNDED_PRINCIPALS_JSON |
                ConvertFrom-Json
            $boundedProperties = @($boundedPrincipals.PSObject.Properties)
            $mapMatches = $boundedProperties.Count -eq $expectedBoundaryMap.Count
            foreach ($principalArn in $expectedBoundaryMap.Keys) {
                $property = $boundedPrincipals.PSObject.Properties[$principalArn]
                if ($null -eq $property -or $property.Value -ne $expectedBoundaryMap[$principalArn]) {
                    $mapMatches = $false
                }
            }
            if ($mapMatches) {
                Add-Pass "heartbeat monitors the exact boundary on both GHA roles"
            }
            else {
                Add-Failure "heartbeat BOUNDED_PRINCIPALS_JSON does not match the two GHA roles"
            }
        }
        catch {
            Add-Failure "heartbeat BOUNDED_PRINCIPALS_JSON is missing or invalid"
        }
    }
}

$targets = Invoke-AwsJson "heartbeat schedule targets" @(
    "events", "list-targets-by-rule",
    "--region", $Region,
    "--rule", $scheduleName
)
if ($null -ne $targets) {
    $exactTargets = @($targets.Targets | Where-Object { $_.Arn -eq $heartbeatArn })
    if ($exactTargets.Count -eq 1 -and @($targets.Targets).Count -eq 1) {
        Add-Pass "heartbeat schedule has exactly the expected Lambda target"
    }
    else {
        Add-Failure "heartbeat schedule target must be exactly $heartbeatArn"
    }
}

$schedule = Invoke-AwsJson "heartbeat schedule" @(
    "events", "describe-rule",
    "--region", $Region,
    "--name", $scheduleName
)
if ($null -ne $schedule) {
    if ($schedule.State -eq "ENABLED" -and $schedule.ScheduleExpression -eq "rate(5 minutes)") {
        Add-Pass "heartbeat schedule is ENABLED at rate(5 minutes)"
    }
    else {
        Add-Failure "heartbeat schedule state/expression is not the approved value"
    }
}

$lambdaPolicy = Invoke-AwsJson "heartbeat invocation permission" @(
    "lambda", "get-policy",
    "--region", $Region,
    "--function-name", $heartbeatName
)
if ($null -ne $lambdaPolicy) {
    $policyText = [string]$lambdaPolicy.Policy
    if (
        $policyText.Contains("events.amazonaws.com") -and
        $policyText.Contains("lambda:InvokeFunction") -and
        $policyText.Contains($scheduleArn)
    ) {
        Add-Pass "heartbeat Lambda permits invocation from the exact schedule"
    }
    else {
        Add-Failure "heartbeat Lambda invocation permission does not match $scheduleArn"
    }
}

$alarmArguments = @(
    "cloudwatch", "describe-alarms",
    "--region", $Region,
    "--alarm-names"
) + $expectedAlarmNames
$alarms = Invoke-AwsJson "heartbeat alarms" $alarmArguments
if ($null -ne $alarms) {
    foreach ($alarmName in $expectedAlarmNames) {
        $alarm = @($alarms.MetricAlarms | Where-Object { $_.AlarmName -eq $alarmName })
        if ($alarm.Count -ne 1) {
            Add-Failure "heartbeat alarm $alarmName is missing"
            continue
        }
        if (@($alarm[0].AlarmActions).Count -lt 2 -or $alarm[0].ActionsEnabled -ne $true) {
            Add-Failure "heartbeat alarm $alarmName must have actions enabled on two paths"
            continue
        }
        if ($alarm[0].StateValue -eq "ALARM") {
            Add-Failure "heartbeat alarm $alarmName is ALARM"
            continue
        }
        Add-Pass "heartbeat alarm $alarmName exists, actions enabled, state $($alarm[0].StateValue)"
    }
}

$heartbeatStartTime = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToUnixTimeMilliseconds()
$heartbeatLogs = Invoke-AwsJson "heartbeat recent result" @(
    "logs", "filter-log-events",
    "--region", $Region,
    "--log-group-name", "/aws/lambda/$heartbeatName",
    "--start-time", [string]$heartbeatStartTime,
    "--limit", "100"
)
if ($null -ne $heartbeatLogs) {
    $statusEvents = @(
        $heartbeatLogs.Events |
            Where-Object { $_.Message -match '"status"\s*:\s*"(PASS|FAIL)"' } |
            Sort-Object Timestamp -Descending
    )
    if ($statusEvents.Count -eq 0) {
        Add-Failure "no heartbeat PASS/FAIL result found in the last 20 minutes"
    }
    elseif ($statusEvents[0].Message -match '"status"\s*:\s*"PASS"') {
        Add-Pass "latest heartbeat result in the last 20 minutes is PASS"
    }
    else {
        Add-Failure "latest heartbeat result in the last 20 minutes is FAIL"
    }
}

foreach ($topic in $topics) {
    $subscriptions = Invoke-AwsJson "$($topic.Name) SNS subscriptions" @(
        "sns", "list-subscriptions-by-topic",
        "--region", $topic.Region,
        "--topic-arn", $topic.Arn
    )
    if ($null -ne $subscriptions) {
        $confirmed = @($subscriptions.Subscriptions | Where-Object {
            $_.SubscriptionArn -and $_.SubscriptionArn -ne "PendingConfirmation"
        })
        if ($confirmed.Count -gt 0) {
            Add-Pass "$($topic.Name) SNS topic has a confirmed receiver"
        }
        else {
            Add-Failure "$($topic.Name) SNS topic has no confirmed receiver"
        }
    }
}

$localPolicies = Invoke-AwsJson "local managed-policy inventory" @(
    "iam", "list-policies",
    "--scope", "Local"
)
if ($null -ne $localPolicies) {
    $candidatePolicies = @($localPolicies.Policies | Where-Object {
        $_.Arn -eq $boundaryArn
    })
    if ($Stage -eq "Foundation") {
        if ($candidatePolicies.Count -eq 0) {
            Add-Pass "candidate boundary is absent before bootstrap seed"
        }
        else {
            Add-Failure "candidate boundary already exists before seed; reconcile live/state ownership"
        }
    }
    elseif ($candidatePolicies.Count -eq 1) {
        Add-Pass "candidate boundary exists exactly once"
    }
    else {
        Add-Failure "candidate boundary is missing or ambiguous"
    }
}

if ($Stage -in @("PreAttach", "PostAttach")) {
    $policy = Invoke-AwsJson "candidate boundary" @(
        "iam", "get-policy",
        "--policy-arn", $boundaryArn
    )
    if ($null -ne $policy) {
        Add-Pass "candidate boundary exists: $boundaryArn"
    }
}

foreach ($roleName in $roleNames) {
    $role = Invoke-AwsJson "GHA role $roleName" @(
        "iam", "get-role",
        "--role-name", $roleName
    )
    if ($null -eq $role) {
        continue
    }

    $actualBoundary = $role.Role.PermissionsBoundary.PermissionsBoundaryArn
    if ($Stage -eq "PostAttach") {
        if ($actualBoundary -eq $boundaryArn) {
            Add-Pass "$roleName has the exact boundary"
        }
        else {
            Add-Failure "$roleName boundary is '$actualBoundary'; expected $boundaryArn"
        }
    }
    elseif ($actualBoundary) {
        Add-Failure "$roleName already has a boundary before the approved attach change"
    }
    else {
        Add-Pass "$roleName is not yet attached, as expected for stage $Stage"
    }
}

Write-Host ""
Write-Host "Summary: $($failures.Count) NO-GO, $($warnings.Count) warning(s)"
foreach ($warning in $warnings) {
    Write-Host "WARN  $warning" -ForegroundColor Yellow
}
foreach ($failure in $failures) {
    Write-Host "NO-GO $failure" -ForegroundColor Red
}

if ($failures.Count -gt 0) {
    exit 1
}

Write-Host "GO for stage $Stage. This script performed read-only AWS calls only." -ForegroundColor Green
exit 0
