<#
.SYNOPSIS
This script is used to send an email to all logged on users in a Azure Virtual Desktop (AVD) environment, when a sessionHost is scheduled to be shutdown.
It is setup as a webhook in a Function App.

.DESCRIPTION
The script retrieves an access token for the Graph and Management API, fetches all hostpools within a specified subscription, 
and sends an email notification if any issues are detected.

.NOTES
Author: Christopher Thomsen - Fortytwo.io (Christopher.Thomsen@fortytwo.io)
Date:   12.04.2024
#>

# Documentation of the API https://learn.microsoft.com/en-us/rest/api/desktopvirtualization/operation-groups?view=rest-desktopvirtualization-2022-02-10-preview

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Write-Host "[DEBUG] Powershell version is:" ($psversiontable).psversion

# Variables -----------------------------------------------------------------------------------------------------------------------
# This is read from the environment variables in the functionApp

# The tenant where the AVD environment is located
$TenantId = $env:TenantId
# The client ID and secret of the App registration used to authenticate - set blank if using Managed Identity
$ClientId = $env:ClientId
$ClientSecret = $env:ClientSecret
# UPN of the sender user - the Appreg or Managed Identity must have the right to send email on behalf of this user
$mailsender = $env:mailsender
# Array of subscription IDs where we will look for hostpools
$subscriptionid = $env:subscriptionid -split ","
# use the Managed Identity of the functionApp to query the API's and send email?
# If set to false, use the App registration credentials above to authenticate
# PS! The Managed Identity or App Registration must have the correct permissions.
$useManagedIdentity = $env:useManagedIdentity


# --------------------------------------------------------------------------------------------------------------------------------

# Define/initialize lists
$hostPoolList = [System.Collections.Generic.List[object]]::new()
$userSessionList = [System.Collections.Generic.List[object]]::new()

# Function to set push output binding and exit.
function Invoke-OutputBinding {
    param (
        [int]$ResponseCode,
        [string]$returnBody
    )
    Write-Host $returnBody
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $ResponseCode
            Body       = $returnBody
        })
    if ($ResponseCode -lt 400) {
        exit 0
    }
    else {
        exit 1
    }
}

# Function to get the access token for either the Graph API or the Management API with Managed Identity or with ClientID and ClientSecret
function Get-AccessToken {
    param (
        [string]$resource,
        [string]$tenantId,
        [string]$clientId,
        [string]$clientSecret,
        [bool]$useManagedIdentity
    )
    if ($useManagedIdentity) {
        $requestAccessTokenUri = $env:IDENTITY_ENDPOINT + "?resource=$resource&api-version=2019-08-01"
        try {
            $token = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER" = "$env:IDENTITY_HEADER" } -Uri $requestAccessTokenUri
        }
        catch {
            Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] Could not get the access token.. $($_.Exception.Message)"
        }
    }
    else {
        $requestAccessTokenUri = "https://login.microsoftonline.com/$tenantId/oauth2/token"
        $body = "grant_type=client_credentials&client_id=$clientId&client_secret=$clientSecret&resource=$resource"
        try {
            $token = Invoke-RestMethod -Method Post -Uri $requestAccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
        }
        catch {
            Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] Could not get the access token.. $($_.Exception.Message)"
        }
    }
    return $token
}

# Check that the incoming data is correct
Write-Host "[INFO] Starting proccessing data.."
if ($Request.rawbody.Length -gt 0) {
    Write-Host "[INFO] There is data.."
    try {
        $shutdownData = $Request.rawbody | ConvertFrom-Json -Depth 10
    }
    catch {
        Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] The data recieved is not in valid JSON format.. $($_.Exception.Message)"
    }
}
else {
    Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] There is NO data.."
}

# Get the access token for the Management API
$mgmtToken = Get-AccessToken -resource "https://management.azure.com/" -tenantId $TenantId -clientId $ClientId -clientSecret $ClientSecret -useManagedIdentity $useManagedIdentity
$mgmtHeaders = @{"Authorization" = "$($mgmtToken.token_type) " + "$($mgmtToken.access_token)" }

# Get the access token for the Graph API
$graphToken = Get-AccessToken -resource "https://graph.microsoft.com/" -tenantId $TenantId -clientId $ClientId -clientSecret $ClientSecret -useManagedIdentity $useManagedIdentity
$graphHeaders = @{"Authorization" = "$($graphToken.token_type) " + "$($graphToken.access_token)" }


# Get all hostpools within the subscriptions specified
foreach ($sub in $subscriptionid) {
    $URLhostPools = "https://management.azure.com/subscriptions/$($sub)/providers/Microsoft.DesktopVirtualization/hostPools?api-version=2022-02-10-preview"
    try {
        $ResponseHostpools = Invoke-WebRequest -Method GET -Uri $URLhostPools -Headers $mgmtHeaders
    }
    catch {
        Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] Could not get the hostpools of Subscription $($sub).. $($_.Exception.Message)"
    }

    $hostpools = $ResponseHostpools.Content | ConvertFrom-Json -Depth 10
    foreach ($hostpool in $hostpools.value) {
        Write-Host "[INFO] Adding hostpool $($hostpool.id) to the list of hostpools"
        $hostPoolList.Add($hostpool.id) | Out-Null
    }
}

# Iterate all hostpools, and get all userSessions for for the sessionHost we are looking for
foreach ($hostpool in $hostPoolList) {
    Write-Host "[INFO] Checking userSessions in the hostpool: $($hostpool)"
    $URLusersessions = "https://management.azure.com$($hostpool)/userSessions?api-version=2022-02-10-preview"
    try {
        $ResponseUserSessions = Invoke-WebRequest -Method GET -Uri $URLusersessions -Headers $mgmtHeaders
    }
    catch {
        Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] Could not get the userSessions.. $($_.Exception.Message)"
    }
    $usersessions = $ResponseUserSessions.Content | ConvertFrom-Json -Depth 10
    foreach ($usersession in $usersessions.value) {
        if ($usersession.name -match $shutdownData.vmName -and $shutdownData.vmName.length -gt 0) {
            Write-Host "[INFO] Adding $($usersession.properties.userPrincipalName) from the sessionHost $($usersession.name) to the list of users"
            $userSessionList.Add(@{"emailAddress" = @{"Address" = "$($usersession.properties.userPrincipalName)" } }) | Out-Null
        }
    }
}

# If there is any, send email to all users who have sessions on the sessionhost
if ($userSessionList.Count -eq 0) {
    Invoke-OutputBinding -ResponseCode 200 -returnBody "[INFO] No users found on the sessionhost.. just shut it down already!"
}

$URLsendMail = "https://graph.microsoft.com/v1.0/users/$($mailsender)/sendMail"
$email = @{
    message         = @{
        subject      = "Shutdown Scheduled in  $($shutdownData.minutesUntilShutdown) minutes | $(Get-Date -UFormat "%d/%m/%Y")"
        body         = @{
            contentType = "html"
            content     = "
            <html>
             <head></head>
             <body>
               <p>Hi, You are logged on AVD terminal " + $shutdownData.vmName + ", and it is scheduled to be shutdown in " + $shutdownData.minutesUntilShutdown + " minutes.<br/><br/>
                  To Skip the shutdown for tonight, click this link: <a href='" + $shutdownData.skipUrl + "'>Skip Shutdown</a>.<br/>
                  To postpone 1 Hour, click this link: <a href='" + $shutdownData.delayUrl60 + "'>Postpone 1 Hour</a>.<br/>
                  To postpone 2 Hours, click this link: <a href='" + $shutdownData.delayUrl120 + "'>Postpone 2 Hours</a>.<br/><br/>
                  If you postpone - You will recieve a new email, like this one, 30minutes before the new shutdown schedule.
                  </p>
             </body>
            </html>"
        }
        toRecipients = @(
            $userSessionList
        )
        # ccRecipients = @(
        #     @{
        #         emailAddress = @{
        #             address = "test@fortytwo.io"
        #         }
        #     }
        # )
    }
    saveToSentItems = "false"
}
$email = $email | ConvertTo-Json -Depth 10

# Send the email
try {
    Invoke-RestMethod -Method POST -Uri $URLsendMail -Headers $graphHeaders -Body $email -ContentType 'application/json' | Out-Null
}
catch {
    Invoke-OutputBinding -ResponseCode 400 -returnBody "[ERROR] Could not send the email.. $($_.Exception.Message)"
    exit 1
}


# Finished, return the number of users that the email was sent to and set the response code to 200 (HTTP OK)
Invoke-OutputBinding -ResponseCode 200 -returnBody "Email sent to $($userSessionList.Count) users"