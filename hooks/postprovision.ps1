#!/usr/bin/env pwsh

param(
    [string] $ResourceGroupName,
    [string] $WorkspaceName
)

Write-Host "Starting post-provision tasks..."

# Get the resource group name from azd environment if not provided
if (-not $ResourceGroupName) {
    $ResourceGroupName = azd env get-values --output json | ConvertFrom-Json | Select-Object -ExpandProperty AZURE_RESOURCE_GROUP_NAME
}

# Get the workspace name from the ARM template outputs if not provided
if (-not $WorkspaceName) {
    $outputs = az deployment group show --resource-group $ResourceGroupName --name azuredeploy --query properties.outputs --output json | ConvertFrom-Json
    $WorkspaceName = $outputs.workspaceName.value
}

Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Workspace Name: $WorkspaceName"

# Provision the managed network for the ML workspace
Write-Host "Provisioning managed network for workspace '$WorkspaceName'..."
try {
    az ml workspace provision-network -g $ResourceGroupName -n $WorkspaceName
    Write-Host "✅ Successfully provisioned managed network for workspace '$WorkspaceName'"
}
catch {
    Write-Error "❌ Failed to provision managed network: $_"
    exit 1
}

Write-Host "Post-provision tasks completed successfully!"
