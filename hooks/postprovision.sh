#!/bin/bash

set -e

echo "Starting post-provision tasks..."

# Get the resource group name from azd environment
RESOURCE_GROUP_NAME=$(azd env get-values --output json | jq -r .AZURE_RESOURCE_GROUP_NAME)

# Get the workspace name from the ARM template outputs
WORKSPACE_NAME=$(az deployment group show --resource-group "$RESOURCE_GROUP_NAME" --name azuredeploy --query properties.outputs.workspaceName.value --output tsv)

echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Workspace Name: $WORKSPACE_NAME"

# Provision the managed network for the ML workspace
echo "Provisioning managed network for workspace '$WORKSPACE_NAME'..."
az ml workspace provision-network -g "$RESOURCE_GROUP_NAME" -n "$WORKSPACE_NAME"

echo "✅ Successfully provisioned managed network for workspace '$WORKSPACE_NAME'"
echo "Post-provision tasks completed successfully!"
