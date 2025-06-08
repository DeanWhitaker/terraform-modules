# modules/secure-storage-account/main.tf

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

# Random string for unique storage account naming
resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  special = false
}

# Storage Account
resource "azurerm_storage_account" "this" {
  name                     = "${var.storage_account_name}${random_string.storage_suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  account_kind             = var.account_kind

  # Security configurations
  public_network_access_enabled   = var.public_network_access_enabled
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  shared_access_key_enabled       = var.shared_access_key_enabled
  https_traffic_only_enabled      = true
  min_tls_version                 = var.min_tls_version

  # Advanced threat protection
  enable_https_traffic_only = true

  # Network rules
  network_rules {
    default_action                 = var.network_default_action
    bypass                        = var.network_bypass
    ip_rules                      = var.allowed_ip_ranges
    virtual_network_subnet_ids    = var.allowed_subnet_ids
    private_link_access {
      endpoint_resource_id = "/subscriptions/${var.subscription_id}"
      endpoint_tenant_id   = var.tenant_id
    }
  }

  # Blob properties for additional security
  blob_properties {
    versioning_enabled       = var.blob_versioning_enabled
    change_feed_enabled      = var.blob_change_feed_enabled
    last_access_time_enabled = var.blob_last_access_time_enabled
    
    dynamic "delete_retention_policy" {
      for_each = var.blob_delete_retention_days > 0 ? [1] : []
      content {
        days = var.blob_delete_retention_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_delete_retention_days > 0 ? [1] : []
      content {
        days = var.container_delete_retention_days
      }
    }
  }

  # Identity configuration for managed identity
  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = var.identity_ids
    }
  }

  tags = var.tags
}

# Private DNS Zone for blob storage
resource "azurerm_private_dns_zone" "blob" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Private DNS Zone for file storage
resource "azurerm_private_dns_zone" "file" {
  count               = var.create_private_endpoint && var.enable_file_share ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Private DNS Zone for queue storage
resource "azurerm_private_dns_zone" "queue" {
  count               = var.create_private_endpoint && var.enable_queue ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Private DNS Zone for table storage
resource "azurerm_private_dns_zone" "table" {
  count               = var.create_private_endpoint && var.enable_table ? 1 : 0
  name                = "privatelink.table.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link Private DNS Zone to Virtual Network
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.create_private_endpoint ? 1 : 0
  name                  = "${var.storage_account_name}-blob-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  count                 = var.create_private_endpoint && var.enable_file_share ? 1 : 0
  name                  = "${var.storage_account_name}-file-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.file[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  count                 = var.create_private_endpoint && var.enable_queue ? 1 : 0
  name                  = "${var.storage_account_name}-queue-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.queue[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  count                 = var.create_private_endpoint && var.enable_table ? 1 : 0
  name                  = "${var.storage_account_name}-table-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.table[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

# Private Endpoint for Blob Storage
resource "azurerm_private_endpoint" "blob" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "${var.storage_account_name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.storage_account_name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }

  tags = var.tags
}

# Private Endpoint for File Storage
resource "azurerm_private_endpoint" "file" {
  count               = var.create_private_endpoint && var.enable_file_share ? 1 : 0
  name                = "${var.storage_account_name}-file-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.storage_account_name}-file-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "file-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.file[0].id]
  }

  tags = var.tags
}

# Private Endpoint for Queue Storage
resource "azurerm_private_endpoint" "queue" {
  count               = var.create_private_endpoint && var.enable_queue ? 1 : 0
  name                = "${var.storage_account_name}-queue-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.storage_account_name}-queue-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "queue-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.queue[0].id]
  }

  tags = var.tags
}

# Private Endpoint for Table Storage
resource "azurerm_private_endpoint" "table" {
  count               = var.create_private_endpoint && var.enable_table ? 1 : 0
  name                = "${var.storage_account_name}-table-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.storage_account_name}-table-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "table-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.table[0].id]
  }

  tags = var.tags
}

# Advanced Threat Protection
resource "azurerm_security_center_storage_defender" "this" {
  count              = var.enable_advanced_threat_protection ? 1 : 0
  storage_account_id = azurerm_storage_account.this.id
}

# Storage Account Customer Managed Keys (optional)
resource "azurerm_storage_account_customer_managed_key" "this" {
  count                     = var.customer_managed_key != null ? 1 : 0
  storage_account_id        = azurerm_storage_account.this.id
  key_vault_id              = var.customer_managed_key.key_vault_id
  key_name                  = var.customer_managed_key.key_name
  key_version               = var.customer_managed_key.key_version
  user_assigned_identity_id = var.customer_managed_key.user_assigned_identity_id
}

# modules/secure-storage-account/variables.tf

variable "storage_account_name" {
  description = "Base name of the storage account. A random suffix will be added to ensure uniqueness."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,15}$", var.storage_account_name))
    error_message = "Storage account name must be between 3-15 characters, lowercase letters and numbers only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where the storage account will be created."
  type        = string
}

variable "location" {
  description = "Azure region where the storage account will be created."
  type        = string
}

variable "account_tier" {
  description = "Storage account tier. Valid options are Standard and Premium."
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Storage account replication type."
  type        = string
  default     = "GRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Invalid replication type."
  }
}

variable "account_kind" {
  description = "Storage account kind."
  type        = string
  default     = "StorageV2"
  validation {
    condition     = contains(["BlobStorage", "BlockBlobStorage", "FileStorage", "Storage", "StorageV2"], var.account_kind)
    error_message = "Invalid account kind."
  }
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the storage account."
  type        = bool
  default     = false
}

variable "allow_nested_items_to_be_public" {
  description = "Allow or disallow nested items to be public."
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Indicates whether the storage account permits requests to be authorized with the account access key."
  type        = bool
  default     = false
}

variable "min_tls_version" {
  description = "The minimum supported TLS version for the storage account."
  type        = string
  default     = "TLS1_2"
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "network_default_action" {
  description = "Specifies the default action when no network rules are matched."
  type        = string
  default     = "Deny"
  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "Network default action must be Allow or Deny."
  }
}

variable "network_bypass" {
  description = "Specifies which traffic can bypass the network rules."
  type        = set(string)
  default     = ["AzureServices"]
  validation {
    condition = alltrue([
      for bypass in var.network_bypass : contains(["Logging", "Metrics", "AzureServices", "None"], bypass)
    ])
    error_message = "Invalid bypass option. Must be one or more of: Logging, Metrics, AzureServices, None."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP addresses or CIDR blocks that should be allowed to access the storage account."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs that should be allowed to access the storage account."
  type        = list(string)
  default     = []
}

variable "subscription_id" {
  description = "Azure subscription ID for private link access configuration."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID for private link access configuration."
  type        = string
}

variable "create_private_endpoint" {
  description = "Whether to create private endpoints for the storage account."
  type        = bool
  default     = true
}

variable "virtual_network_id" {
  description = "ID of the virtual network where private DNS zones will be linked. Required if create_private_endpoint is true."
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "ID of the subnet where private endpoints will be created. Required if create_private_endpoint is true."
  type        = string
  default     = null
}

variable "enable_file_share" {
  description = "Whether to enable file share service and create private endpoint for it."
  type        = bool
  default     = false
}

variable "enable_queue" {
  description = "Whether to enable queue service and create private endpoint for it."
  type        = bool
  default     = false
}

variable "enable_table" {
  description = "Whether to enable table service and create private endpoint for it."
  type        = bool
  default     = false
}

variable "blob_versioning_enabled" {
  description = "Whether blob versioning is enabled."
  type        = bool
  default     = true
}

variable "blob_change_feed_enabled" {
  description = "Whether blob change feed is enabled."
  type        = bool
  default     = true
}

variable "blob_last_access_time_enabled" {
  description = "Whether blob last access time tracking is enabled."
  type        = bool
  default     = true
}

variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted blobs. Set to 0 to disable."
  type        = number
  default     = 30
  validation {
    condition     = var.blob_delete_retention_days >= 0 && var.blob_delete_retention_days <= 365
    error_message = "Blob delete retention days must be between 0 and 365."
  }
}

variable "container_delete_retention_days" {
  description = "Number of days to retain deleted containers. Set to 0 to disable."
  type        = number
  default     = 30
  validation {
    condition     = var.container_delete_retention_days >= 0 && var.container_delete_retention_days <= 365
    error_message = "Container delete retention days must be between 0 and 365."
  }
}

variable "identity_type" {
  description = "Type of managed identity for the storage account."
  type        = string
  default     = null
  validation {
    condition     = var.identity_type == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type)
    error_message = "Identity type must be SystemAssigned, UserAssigned, or 'SystemAssigned, UserAssigned'."
  }
}

variable "identity_ids" {
  description = "List of user assigned identity IDs."
  type        = list(string)
  default     = []
}

variable "enable_advanced_threat_protection" {
  description = "Whether to enable advanced threat protection for the storage account."
  type        = bool
  default     = true
}

variable "customer_managed_key" {
  description = "Customer managed key configuration for storage account encryption."
  type = object({
    key_vault_id              = string
    key_name                  = string
    key_version               = optional(string)
    user_assigned_identity_id = string
  })
  default = null
}

variable "tags" {
  description = "Tags to be applied to all resources."
  type        = map(string)
  default     = {}
}

# modules/secure-storage-account/outputs.tf

output "storage_account_id" {
  description = "The ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "The primary access key of the storage account."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "The secondary access key of the storage account."
  value       = azurerm_storage_account.this.secondary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string of the storage account."
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
}

output "storage_account_secondary_connection_string" {
  description = "The secondary connection string of the storage account."
  value       = azurerm_storage_account.this.secondary_connection_string
  sensitive   = true
}

output "private_endpoint_blob_id" {
  description = "The ID of the blob private endpoint."
  value       = var.create_private_endpoint ? azurerm_private_endpoint.blob[0].id : null
}

output "private_endpoint_file_id" {
  description = "The ID of the file private endpoint."
  value       = var.create_private_endpoint && var.enable_file_share ? azurerm_private_endpoint.file[0].id : null
}

output "private_endpoint_queue_id" {
  description = "The ID of the queue private endpoint."
  value       = var.create_private_endpoint && var.enable_queue ? azurerm_private_endpoint.queue[0].id : null
}

output "private_endpoint_table_id" {
  description = "The ID of the table private endpoint."
  value       = var.create_private_endpoint && var.enable_table ? azurerm_private_endpoint.table[0].id : null
}

output "private_dns_zone_blob_id" {
  description = "The ID of the blob private DNS zone."
  value       = var.create_private_endpoint ? azurerm_private_dns_zone.blob[0].id : null
}

output "private_dns_zone_file_id" {
  description = "The ID of the file private DNS zone."
  value       = var.create_private_endpoint && var.enable_file_share ? azurerm_private_dns_zone.file[0].id : null
}

output "private_dns_zone_queue_id" {
  description = "The ID of the queue private DNS zone."
  value       = var.create_private_endpoint && var.enable_queue ? azurerm_private_dns_zone.queue[0].id : null
}

output "private_dns_zone_table_id" {
  description = "The ID of the table private DNS zone."
  value       = var.create_private_endpoint && var.enable_table ? azurerm_private_dns_zone.table[0].id : null
}

output "identity" {
  description = "The identity block of the storage account."
  value       = var.identity_type != null ? azurerm_storage_account.this.identity : null
}

# modules/secure-storage-account/versions.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

