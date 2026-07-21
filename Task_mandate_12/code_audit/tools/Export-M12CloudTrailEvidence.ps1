<#
.SYNOPSIS
Exports redacted Mandate 12 evidence from one downloaded CloudTrail .json.gz file.

.DESCRIPTION
The script works only on a local CloudTrail log file already copied from the
Object-Lock audit bucket. It does not call AWS and never exports unrestricted
request bodies or secret values. Access mode selects actor/session, time, API,
resource, request ID and result. ConfigChange mode additionally exports only an
explicit allowlist of non-secret configuration fields for the thin-log test.

.EXAMPLE
.\Export-M12CloudTrailEvidence.ps1 `
  -LogFile .\CloudTrail-ap-southeast-1-20260718T1200Z.json.gz `
  -EventName GetObject `
  -ResourceContains 'approved-sensitive-bucket/approved-prefix/' `
  -OutputPath .\evidence\M12-T03-s3-getobject.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$LogFile,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$EventName,

    [string]$ResourceContains,

    [ValidateSet('Access', 'ConfigChange')]
    [string]$EvidenceProfile = 'Access',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalProperty {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ApprovedConfigParameters {
    param(
        [AllowNull()]
        [object]$Request
    )

    # Never add credential, secret, token, body, payload, policy-document or
    # object-content fields here. Expand this list only through code review.
    $allowedFields = @(
        'actionsEnabled',
        'advancedEventSelectors',
        'alarmActions',
        'alarmName',
        'comparisonOperator',
        'datapointsToAlarm',
        'dimensions',
        'enableLogFileValidation',
        'evaluationPeriods',
        'eventPattern',
        'eventSelectors',
        'includeGlobalServiceEvents',
        'isMultiRegionTrail',
        'metricName',
        'name',
        'namespace',
        'period',
        'readWriteType',
        'scheduleExpression',
        'state',
        'statistic',
        'threshold',
        'trailName',
        'treatMissingData'
    )

    $approved = [ordered]@{}
    foreach ($field in $allowedFields) {
        $value = Get-OptionalProperty -Object $Request -Name $field
        if ($null -ne $value) {
            $approved[$field] = $value
        }
    }
    if ($approved.Count -eq 0) {
        return $null
    }
    return [PSCustomObject]$approved
}

if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf)) {
    throw "CloudTrail log file not found: $LogFile"
}

if ([System.IO.Path]::GetFullPath($LogFile) -eq [System.IO.Path]::GetFullPath($OutputPath)) {
    throw 'OutputPath must be different from LogFile.'
}

$inputStream = $null
$gzipStream = $null
$reader = $null

try {
    $inputStream = [System.IO.File]::OpenRead($LogFile)
    $gzipStream = [System.IO.Compression.GZipStream]::new(
        $inputStream,
        [System.IO.Compression.CompressionMode]::Decompress,
        $false
    )
    $reader = [System.IO.StreamReader]::new($gzipStream)
    $payload = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $gzipStream) { $gzipStream.Dispose() }
    elseif ($null -ne $inputStream) { $inputStream.Dispose() }
}

$cloudTrailDocument = $payload | ConvertFrom-Json
if ($null -eq $cloudTrailDocument.Records) {
    throw 'The decompressed file does not contain a CloudTrail Records array.'
}

$matches = foreach ($record in @($cloudTrailDocument.Records)) {
    if ($record.eventName -notin $EventName) {
        continue
    }

    $recordResources = Get-OptionalProperty -Object $record -Name 'resources'
    $resourceArns = @(
        $recordResources |
            ForEach-Object { Get-OptionalProperty -Object $_ -Name 'ARN' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $request = Get-OptionalProperty -Object $record -Name 'requestParameters'
    $requestTargets = @(
        $resourceArns
        Get-OptionalProperty -Object $request -Name 'bucketName'
        Get-OptionalProperty -Object $request -Name 'key'
        Get-OptionalProperty -Object $request -Name 'secretId'
        Get-OptionalProperty -Object $request -Name 'name'
        Get-OptionalProperty -Object $request -Name 'topicArn'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (-not [string]::IsNullOrWhiteSpace($ResourceContains) -and
        (($requestTargets -join "`n") -notlike "*$ResourceContains*")) {
        continue
    }

    # Base output is metadata-only; ConfigChange adds only the reviewed allowlist above.
    $userIdentity = Get-OptionalProperty -Object $record -Name 'userIdentity'
    $sessionContext = Get-OptionalProperty -Object $userIdentity -Name 'sessionContext'
    $sessionIssuer = Get-OptionalProperty -Object $sessionContext -Name 'sessionIssuer'
    $approvedChangeParameters = $null
    if ($EvidenceProfile -eq 'ConfigChange') {
        $approvedChangeParameters = Get-ApprovedConfigParameters -Request $request
        if ($null -eq $approvedChangeParameters) {
            continue
        }
    }

    [PSCustomObject]@{
        eventTime       = $record.eventTime
        eventName       = $record.eventName
        eventSource     = $record.eventSource
        awsRegion       = $record.awsRegion
        eventID         = $record.eventID
        requestID       = Get-OptionalProperty -Object $record -Name 'requestID'
        errorCode       = Get-OptionalProperty -Object $record -Name 'errorCode'
        errorMessage    = Get-OptionalProperty -Object $record -Name 'errorMessage'
        principalArn    = Get-OptionalProperty -Object $userIdentity -Name 'arn'
        principalId     = Get-OptionalProperty -Object $userIdentity -Name 'principalId'
        sessionIssuer   = Get-OptionalProperty -Object $sessionIssuer -Name 'arn'
        sourceIPAddress = Get-OptionalProperty -Object $record -Name 'sourceIPAddress'
        resourceArns    = $resourceArns
        requestTarget   = $requestTargets
        changeParameters = $approvedChangeParameters
    }
}

$result = @($matches)
if ($result.Count -eq 0) {
    throw "No matching event was found. Events: $($EventName -join ', '); resource filter: $ResourceContains"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$result |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Output "Exported $($result.Count) redacted CloudTrail record(s) to $OutputPath"
