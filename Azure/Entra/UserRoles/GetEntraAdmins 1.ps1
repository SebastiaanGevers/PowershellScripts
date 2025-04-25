<#
.SYNOPSIS
    Retrieves all Assigned and Eligible admins for Azure AD roles matching a given name filter.

.DESCRIPTION
    This script connects to Microsoft Graph and Azure AD to retrieve administrators assigned or eligible for directory roles.
    You can filter roles by name and optionally export results to a CSV.

.PARAMETER RoleNameFilter
    Regex or string filter to match role names. Default is 'admin'.

.PARAMETER OutputCSV
    Optional path to export results to CSV.

.EXAMPLE
    .\Get-AzureADAdmins.ps1 -RoleNameFilter "admin" -OutputCSV "C:\Reports\Admins.csv"
#>

param (
    [string]$RoleNameFilter = "admin",
    [string]$OutputCSV = "$HOME\Downloads\Admins.csv"
)

# Ensure required modules are loaded and connect
try {
    #Connect-AzureAD
    Connect-MgGraph -Scopes "RoleManagement.Read.All", "Directory.Read.All"
    Write-Host "Connected to Microsoft Graph successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Azure: $_"
    exit
}

function Get-EntityDetails {
    param (
        [Parameter(Mandatory)]
        [string]$PrincipalId
    )

    try {
        $user = Get-MgUser -UserId $PrincipalId -ErrorAction Stop
        return @{ Name = $user.DisplayName; Type = "User" }
    } catch {
        try {
            $app = Get-MgServicePrincipal -ServicePrincipalId $PrincipalId -ErrorAction Stop
            if ($app.Tags -contains "ManagedIdentity") {
                return @{ Name = $app.DisplayName; Type = "Managed Identity" }
            }
            return @{ Name = $app.DisplayName; Type = "Service Principal" }
        } catch {
            try {
                $group = Get-MgGroup -GroupId $PrincipalId -ErrorAction Stop
                return @{ Name = $group.DisplayName; Type = "Group" }
            } catch {
                return @{ Name = "Unknown"; Type = "Unknown" }
            }
        }
    }
}

function Get-AllAdminsForRole {
    param (
        [Parameter(Mandatory)]
        [string]$RoleId
    )

    $adminEntities = @()

    $roles = @{
        "Assigned" = Get-MgRoleManagementDirectoryRoleAssignment -Filter "roleDefinitionId eq '$RoleId'"
        "Eligible" = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "roleDefinitionId eq '$RoleId'"
    }

    foreach ($roleType in $roles.Keys) {
        foreach ($admin in $roles[$roleType]) {
            $entity = Get-EntityDetails -PrincipalId $admin.PrincipalId
            $adminEntities += [PSCustomObject]@{
                Name     = $entity.Name
                ID       = $admin.PrincipalId
                Type     = $entity.Type
                RoleType = $roleType
            }
        }
    }

    return $adminEntities
}

# Main logic
$results = @()
$roles = Get-MgRoleManagementDirectoryRoleDefinition | Where-Object { $_.DisplayName -match $RoleNameFilter }

foreach ($role in $roles) {
    Write-Host "`n[$($role.DisplayName)] (ID: $($role.Id))" -ForegroundColor Cyan

    $admins = Get-AllAdminsForRole -RoleId $role.Id

    foreach ($admin in $admins) {
        $results += [PSCustomObject]@{
            RoleName = $role.DisplayName
            Name     = $admin.Name
            ID       = $admin.ID
            Type     = $admin.Type
            RoleType = $admin.RoleType
        }
    }

    $admins | Format-Table Name, ID, Type, RoleType
}

# Export to CSV if needed
if ($OutputCSV) {
    try {
        $results | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8
        Write-Host "`nExported to: $OutputCSV" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export to CSV: $_"
    }
}
