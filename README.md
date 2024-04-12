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
