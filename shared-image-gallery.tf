# main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Data sources
data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_subnet" "pe_subnet" {
  count                = var.private_endpoint_enabled ? 1 : 0
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = var.private_endpoint_vnet_name
  resource_group_name  = var.private_endpoint_subnet_resource_group_name != null ? var.private_endpoint_subnet_resource_group_name : var.resource_group_name
}

# Random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Shared Image Gallery
resource "azurerm_shared_image_gallery" "main" {
  name                = var.gallery_name != null ? var.gallery_name : "sig-${var.name_prefix}-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location != null ? var.location : data.azurerm_resource_group.main.location
  description         = var.description

  tags = merge(
    var.tags,
    {
      "Environment" = var.environment
      "ManagedBy"   = "Terraform"
    }
  )
}

# Private DNS Zone for Shared Image Gallery
resource "azurerm_private_dns_zone" "sig" {
  count               = var.private_endpoint_enabled ? 1 : 0
  name                = "privatelink.gallery.azure.com"
  resource_group_name = data.azurerm_resource_group.main.name

  tags = var.tags
}

# Private DNS Zone Virtual Network Link
resource "azurerm_private_dns_zone_virtual_network_link" "sig" {
  count                 = var.private_endpoint_enabled ? 1 : 0
  name                  = "sig-dns-link-${random_string.suffix.result}"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.sig[0].name
  virtual_network_id    = data.azurerm_subnet.pe_subnet[0].virtual_network_id
  registration_enabled  = false

  tags = var.tags
}

# Private Endpoint for Shared Image Gallery
resource "azurerm_private_endpoint" "sig" {
  count               = var.private_endpoint_enabled ? 1 : 0
  name                = "pe-sig-${var.name_prefix}-${random_string.suffix.result}"
  location            = var.location != null ? var.location : data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = data.azurerm_subnet.pe_subnet[0].id

  private_service_connection {
    name                           = "psc-sig-${var.name_prefix}-${random_string.suffix.result}"
    private_connection_resource_id = azurerm_shared_image_gallery.main.id
    is_manual_connection           = false
    subresource_names              = ["gallery"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.sig[0].id]
  }

  tags = var.tags
}

# RBAC Assignment for Gallery (optional)
resource "azurerm_role_assignment" "gallery_reader" {
  count                = length(var.reader_principal_ids)
  scope                = azurerm_shared_image_gallery.main.id
  role_definition_name = "Reader"
  principal_id         = var.reader_principal_ids[count.index]
}

resource "azurerm_role_assignment" "gallery_contributor" {
  count                = length(var.contributor_principal_ids)
  scope                = azurerm_shared_image_gallery.main.id
  role_definition_name = "Contributor"
  principal_id         = var.contributor_principal_ids[count.index]
}

# Resource Lock (optional)
resource "azurerm_management_lock" "gallery_lock" {
  count      = var.enable_resource_lock ? 1 : 0
  name       = "sig-lock-${var.name_prefix}"
  scope      = azurerm_shared_image_gallery.main.id
  lock_level = var.lock_level
  notes      = "Terraform managed lock for Shared Image Gallery"
}

# Diagnostic Settings (optional)
resource "azurerm_monitor_diagnostic_setting" "sig" {
  count                      = var.enable_diagnostics ? 1 : 0
  name                       = "diag-sig-${var.name_prefix}"
  target_resource_id         = azurerm_shared_image_gallery.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# variables.tf
variable "resource_group_name" {
  description = "The name of the resource group where the Shared Image Gallery will be created"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "gallery_name" {
  description = "The name of the Shared Image Gallery. If not provided, will be auto-generated"
  type        = string
  default     = null
}

variable "location" {
  description = "The Azure location where resources will be created. If not provided, uses resource group location"
  type        = string
  default     = null
}

variable "description" {
  description = "A description for the Shared Image Gallery"
  type        = string
  default     = "Shared Image Gallery created by Terraform"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

variable "private_endpoint_enabled" {
  description = "Whether to create a private endpoint for the Shared Image Gallery"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_name" {
  description = "The name of the subnet where the private endpoint will be created"
  type        = string
  default     = ""
}

variable "private_endpoint_vnet_name" {
  description = "The name of the virtual network containing the private endpoint subnet"
  type        = string
  default     = ""
}

variable "private_endpoint_subnet_resource_group_name" {
  description = "The resource group name of the private endpoint subnet. If not provided, uses the main resource group"
  type        = string
  default     = null
}

variable "reader_principal_ids" {
  description = "List of principal IDs to assign Reader role on the gallery"
  type        = list(string)
  default     = []
}

variable "contributor_principal_ids" {
  description = "List of principal IDs to assign Contributor role on the gallery"
  type        = list(string)
  default     = []
}

variable "enable_resource_lock" {
  description = "Whether to enable resource lock on the gallery"
  type        = bool
  default     = false
}

variable "lock_level" {
  description = "The level of lock to apply (CanNotDelete or ReadOnly)"
  type        = string
  default     = "CanNotDelete"
  validation {
    condition     = contains(["CanNotDelete", "ReadOnly"], var.lock_level)
    error_message = "Lock level must be either 'CanNotDelete' or 'ReadOnly'."
  }
}

variable "enable_diagnostics" {
  description = "Whether to enable diagnostic settings"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for diagnostic settings"
  type        = string
  default     = null
}

# outputs.tf
output "gallery_id" {
  description = "The ID of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.id
}

output "gallery_name" {
  description = "The name of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.name
}

output "gallery_unique_name" {
  description = "The unique name of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.unique_name
}

output "gallery_location" {
  description = "The location of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.location
}

output "private_endpoint_id" {
  description = "The ID of the private endpoint"
  value       = var.private_endpoint_enabled ? azurerm_private_endpoint.sig[0].id : null
}

output "private_endpoint_private_ip" {
  description = "The private IP address of the private endpoint"
  value       = var.private_endpoint_enabled ? azurerm_private_endpoint.sig[0].private_service_connection[0].private_ip_address : null
}

output "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  value       = var.private_endpoint_enabled ? azurerm_private_dns_zone.sig[0].id : null
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

# tests/setup/main.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-sig-test-${random_string.test_suffix.result}"
  location = "East US"
}

resource "random_string" "test_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create test virtual network and subnet for private endpoint testing
resource "azurerm_virtual_network" "test" {
  name                = "vnet-sig-test-${random_string.test_suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_subnet" "test" {
  name                 = "subnet-pe-test"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.1.0/24"]
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "subnet_name" {
  value = azurerm_subnet.test.name
}

output "vnet_name" {
  value = azurerm_virtual_network.test.name
}

# tests/shared_image_gallery.tftest.hcl
# Unit tests for the Shared Image Gallery module

# Test 1: Basic gallery creation without private endpoint
run "test_basic_gallery_creation" {
  command = plan

  variables {
    resource_group_name     = "rg-test-sig"
    name_prefix            = "test"
    private_endpoint_enabled = false
    environment            = "test"
    description           = "Test gallery"
    tags = {
      Environment = "test"
      Owner      = "terraform-test"
    }
  }

  assert {
    condition     = azurerm_shared_image_gallery.main.name != null
    error_message = "Gallery name should not be null"
  }

  assert {
    condition     = azurerm_shared_image_gallery.main.description == "Test gallery"
    error_message = "Gallery description should match input"
  }

  assert {
    condition     = length(azurerm_private_endpoint.sig) == 0
    error_message = "Private endpoint should not be created when disabled"
  }
}

# Test 2: Gallery with private endpoint
run "test_gallery_with_private_endpoint" {
  command = plan

  variables {
    resource_group_name              = "rg-test-sig"
    name_prefix                     = "test"
    private_endpoint_enabled        = true
    private_endpoint_subnet_name    = "subnet-pe"
    private_endpoint_vnet_name      = "vnet-test"
    environment                     = "test"
  }

  assert {
    condition     = length(azurerm_private_endpoint.sig) == 1
    error_message = "Private endpoint should be created when enabled"
  }

  assert {
    condition     = length(azurerm_private_dns_zone.sig) == 1
    error_message = "Private DNS zone should be created with private endpoint"
  }

  assert {
    condition     = azurerm_private_dns_zone.sig[0].name == "privatelink.gallery.azure.com"
    error_message = "Private DNS zone should have correct name"
  }
}

# Test 3: Gallery with RBAC assignments
run "test_gallery_with_rbac" {
  command = plan

  variables {
    resource_group_name       = "rg-test-sig"
    name_prefix              = "test"
    private_endpoint_enabled = false
    reader_principal_ids     = ["11111111-1111-1111-1111-111111111111"]
    contributor_principal_ids = ["22222222-2222-2222-2222-222222222222"]
    environment              = "test"
  }

  assert {
    condition     = length(azurerm_role_assignment.gallery_reader) == 1
    error_message = "Reader role assignment should be created"
  }

  assert {
    condition     = length(azurerm_role_assignment.gallery_contributor) == 1
    error_message = "Contributor role assignment should be created"
  }

  assert {
    condition     = azurerm_role_assignment.gallery_reader[0].role_definition_name == "Reader"
    error_message = "Reader role assignment should have correct role"
  }
}

# Test 4: Gallery with resource lock
run "test_gallery_with_lock" {
  command = plan

  variables {
    resource_group_name     = "rg-test-sig"
    name_prefix            = "test"
    private_endpoint_enabled = false
    enable_resource_lock   = true
    lock_level            = "CanNotDelete"
    environment           = "test"
  }

  assert {
    condition     = length(azurerm_management_lock.gallery_lock) == 1
    error_message = "Resource lock should be created when enabled"
  }

  assert {
    condition     = azurerm_management_lock.gallery_lock[0].lock_level == "CanNotDelete"
    error_message = "Resource lock should have correct level"
  }
}

# Test 5: Validate variable constraints
run "test_invalid_lock_level" {
  command = plan

  variables {
    resource_group_name     = "rg-test-sig"
    name_prefix            = "test"
    private_endpoint_enabled = false
    enable_resource_lock   = true
    lock_level            = "InvalidLevel"
    environment           = "test"
  }

  expect_failures = [
    var.lock_level,
  ]
}

# Test 6: Integration test with all features enabled
run "test_full_integration" {
  command = plan

  variables {
    resource_group_name              = "rg-test-sig"
    name_prefix                     = "integration"
    gallery_name                    = "sig-integration-test"
    location                        = "West US 2"
    description                     = "Integration test gallery"
    environment                     = "integration"
    private_endpoint_enabled        = true
    private_endpoint_subnet_name    = "subnet-pe"
    private_endpoint_vnet_name      = "vnet-integration"
    reader_principal_ids            = ["11111111-1111-1111-1111-111111111111"]
    contributor_principal_ids       = ["22222222-2222-2222-2222-222222222222"]
    enable_resource_lock           = true
    lock_level                     = "ReadOnly"
    enable_diagnostics             = false
    tags = {
      Environment = "integration"
      Project     = "terraform-testing"
      Owner       = "devops-team"
    }
  }

  assert {
    condition     = azurerm_shared_image_gallery.main.name == "sig-integration-test"
    error_message = "Gallery should use provided name"
  }

  assert {
    condition     = azurerm_shared_image_gallery.main.location == "West US 2"
    error_message = "Gallery should use provided location"
  }

  assert {
    condition     = length(azurerm_private_endpoint.sig) == 1
    error_message = "Private endpoint should be created"
  }

  assert {
    condition     = length(azurerm_role_assignment.gallery_reader) == 1
    error_message = "RBAC assignments should be created"
  }

  assert {
    condition     = azurerm_management_lock.gallery_lock[0].lock_level == "ReadOnly"
    error_message = "Resource lock should have correct level"
  }
}

