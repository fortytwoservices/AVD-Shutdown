# AVD-ShutdownWebhook

This script is used to send an email to all logged on users in a Azure Virtual Desktop (AVD) environment, when a sessionHost is scheduled to be shutdown.
It is setup as a webhook in a Function App.

The script retrieves an access token for the Graph and Management API, fetches all hostpools within a specified subscription, 
and sends an email notification if any issues are detected.

## Prerequisites

- Azure Virtual Desktop environment
- Azure Function App
- Azure AD App Registration or use the Managed Identity of the Function App.
- A user account with permissions to send emails.

## Permissions required

RBAC / IAM:

- Reader on the Resource Group containing the AVD environment

API Permissions:

- Microsoft Graph
  - User.Read
  - Mail.Send

### Sample data from the webhook

``` JSON
{
    "skipUrl":"https://prod.skipdelay.vsdth.visualstudio.com/skip?vmName=vm-t-pn-avdsh&guid=8fdb99d6-ed59-4bef-ab6e-d34ed3b7e574&subscriptionId=3ba20510-asdf-asdf-asdf-1387bd4f7c8c&operation=skip",
    "delayUrl60":"https://prod.skipdelay.vsdth.visualstudio.com/delay?vmName=vm-t-pn-avdsh&guid=8fdb99d6-ed59-4bef-ab6e-d34ed3b7e574&subscriptionId=3ba20510-asdf-asdf-asdf-1387bd4f7c8c&timeDelay=60&operation=delay",
    "delayUrl120":"https://prod.skipdelay.vsdth.visualstudio.com/delay?vmName=vm-t-pn-avdsh&guid=8fdb99d6-ed59-4bef-ab6e-d34ed3b7e574&subscriptionId=3ba20510-asdf-asdf-asdf-1387bd4f7c8c&timeDelay=120&operation=delay",
    "vmName":"vm-t-avdsh",
    "guid":"8fdb99d6-ed59-4bef-ab6e-d34ed3b7e574",
    "owner":null,
    "vmUrl":"https://portal.azure.com/#resource/subscriptions/3ba20510-asdf-asdf-asdf-1387bd4f7c8c/resourceGroups/rg-t-avd/providers/Microsoft.Compute/virtualMachines/vm-t-avdsh",
    "minutesUntilShutdown":"30",
    "eventType":"AutoShutdown",
    "text":"Azure DevTest Labs notification: The resource vm-t-pn-avdsh in resource group rg-t-avd with subscription Id 3ba20510-asdf-asdf-asdf-1387bd4f7c8c is scheduled for automatic shutdown in 30 minutes. this auto-shutdown. . .",
    "subscriptionId":"3ba20510-asdf-asdf-asdf-1387bd4f7c8c",
    "resourceGroupName":"rg-t-avd",
    "labName":null
}
```
