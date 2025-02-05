#Requires -Modules Microsoft.Graph.Applications, Az.Resources

# Required Permissions
#  - Entra ID Global Administrator or an Entra ID Privileged Role Administrator to execute the Set-APIPermissions function
#  - Resource Group Owner or User Access Administrator on the Microsoft Sentinel resource group to execute the Set-RBACPermissions function

# Note that we assume that the solution is installed in the same resource group as the log analytics workspace 

$TenantId = "" #Entra ID tenant
$AzureSubscriptionId = "" #Azure Subsription Id where the solution is deployed
$ResourceGroupName = "" #Azure Resrouce Group where the solution is deployed
$LogicAppName = "" #Name of the logic app used in the solution
$DCRName = "" #Name of the DCR used by the solution
$WorkspaceName= "" #Name of the log analytics worksapce where the solution sends the data

# Check if the script is running in Azure Cloud Shell
if( $env:AZUREPS_HOST_ENVIRONMENT -like "cloud-shell*" ) {
    Write-Host "[+] The script is running in Azure Cloud Shell, Device Code flow will be used for authentication." 
    Write-Host "[+] It will look like the connection is coming from the Azure data center and not your client's location." -ForegroundColor Yellow
    $DeviceCodeFlow = $true
}

# Connect to the Microsoft Graph API and Azure Management API
Write-Host "[+] Connect to the Entra ID tenant: $TenantId"
if ( $DeviceCodeFlow -eq $true ) {
    Connect-MgGraph -TenantId $TenantId -Scopes AppRoleAssignment.ReadWrite.All, Application.Read.All -NoWelcome -ErrorAction Stop
} else {
    Connect-MgGraph -TenantId $TenantId -Scopes AppRoleAssignment.ReadWrite.All, Application.Read.All -NoWelcome -ErrorAction Stop | Out-Null
}

Write-Host "[+] Connecting to  to the Azure subscription: $AzureSubscriptionId"
try
{
    if ( $DeviceCodeFlow -eq $true ) {
        Connect-AzAccount -Subscription $AzureSubscriptionId -Tenant $TenantId -ErrorAction Stop -UseDeviceAuthentication
    } else {
        Login-AzAccount -Subscription $AzureSubscriptionId -Tenant $TenantId -ErrorAction Stop | Out-Null
    }
}
catch
{
    Write-Host "[-] Login to Azure Management failed. $($error[0])" -ForegroundColor Red
    return
}

function Set-APIPermissions ($MSIName, $AppId, $PermissionName) {
    Write-Host "[+] Setting permission $PermissionName on $MSIName"
    $MSI = Get-AppIds -AppName $MSIName
    if ( $MSI.count -gt 1 )
    {
        Write-Host "[-] Found multiple principals with the same name." -ForegroundColor Red
        return 
    } elseif ( $MSI.count -eq 0 ) {
        Write-Host "[-] Principal not found." -ForegroundColor Red
        return 
    }
    Start-Sleep -Seconds 2 # Wait in case the MSI identity creation take some time
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$AppId'"
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    try
    {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MSI.Id -PrincipalId $MSI.Id -ResourceId $GraphServicePrincipal.Id -AppRoleId $AppRole.Id -ErrorAction Stop | Out-Null
    }
    catch
    {
        if ( $_.Exception.Message -eq "Permission being assigned already exists on the object" )
        {
            Write-Host "[-] $($_.Exception.Message)"
        } else {
            Write-Host "[-] $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }
    Write-Host "[+] Permission granted" -ForegroundColor Green
}

function Get-AppIds ($AppName) {
    Get-MgServicePrincipal -Filter "displayName eq '$AppName'"
}

function Set-RBACPermissions ($MSIName, $Role) {
    Write-Host "Adding $Role to $MSIName"
    $MSI = Get-AppIds -AppName $MSIName
    if ( $MSI.count -gt 1 )
    {
        Write-Host "[-] Found multiple principals with the same name." -ForegroundColor Red
        return 
    } elseif ( $MSI.count -eq 0 ) {
        Write-Host "[-] Principal not found." -ForegroundColor Red
        return 
    }
    if ( $Role -eq "Log Analytics Reader") {
      $Assign = New-AzRoleAssignment -ApplicationId $MSI.AppId -Scope "/subscriptions/$($AzureSubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/microsoft.operationalinsights/workspaces/$($WorkspaceName)" -RoleDefinitionName $Role -ErrorAction SilentlyContinue -ErrorVariable AzError
    } else {
      $Assign = New-AzRoleAssignment -ApplicationId $MSI.AppId -Scope "/subscriptions/$($AzureSubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.Insights/dataCollectionRules/$($DCRName)" -RoleDefinitionName $Role -ErrorAction SilentlyContinue -ErrorVariable AzError
    }
    if ( $null -ne $Assign )
    {
        Write-Host "[+] Role added" -ForegroundColor Green
    } elseif ( $AzError[0].Exception.Message -like "*Conflict*" ) {
        Write-Host "[-] Role already assigned"
    } else {
        Write-Host "[-] $($AzError[0].Exception.Message)" -ForegroundColor Red
    }
}

Set-RBACPermissions -MSIName $LogicAppName -Role "Log Analytics Reader"
Set-RBACPermissions -MSIName $LogicAppName -Role "Monitoring Metrics Publisher"
Set-APIPermissions -MSIName $LogicAppName -AppId "ca7f3f0b-7d91-482c-8e09-c5d840d0eac5" -PermissionName "Data.Read"

Write-Host "[+] End of the script. Please review the output and check for potential failures."
