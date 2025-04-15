# Modified version that uses filenames as stable keys instead of indices

# Create a map of config files using filenames as keys for stable mapping
locals {
  # Convert the list inputs to a map with file name as the key
  config_files = {
    for i in range(var.config_file_count) : var.config_file_names[i] => {
      name = var.config_file_names[i]
      path = var.config_file_paths[i]
      merged_path = "${var.config_file_paths[i]}.merged.json"
    }
  }
  
  # Determine which path to use based on merged file existence
  config_content_paths = {
    for name, file in local.config_files : name => (
      fileexists(file.merged_path) ? file.merged_path : file.path
    )
  }
  
  # Process each file to ensure proper version field
  fixed_contents = {
    for name, path in local.config_content_paths : name => {
      flags   = jsondecode(file(path)).flags
      values  = jsondecode(file(path)).values
    }
  }
  
  # Generate a hash of meaningful content (excluding timestamps)
  meaningful_content_hash = {
    for name, content in local.fixed_contents : name => sha256(jsonencode({
      flags = content.flags,
      values_without_timestamps = {
        for flag_name, flag_values in content.values : flag_name => {
          for k, v in flag_values : k => v if !startswith(k, "_")
        }
      }
    }))
  }
}

# AWS AppConfig Deployment Strategy (shared across all deployments)
resource "aws_appconfig_deployment_strategy" "quick_deployment" {
  name                           = "quick-deployment-strategy"
  description                    = "Quick deployment strategy with no bake time or growth interval"
  deployment_duration_in_minutes = 0
  growth_factor                  = 100
  final_bake_time_in_minutes     = 0
  growth_type                    = "LINEAR"
  replicate_to                   = "NONE"
}

# Create resources for each config file using filename as a stable key
resource "aws_appconfig_application" "feature_flags_app" {
  for_each    = local.config_files
  
  name        = each.key
  description = "Feature flags application created from ${each.key}"
  
  # Include explicit tags to match existing resources
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# AWS AppConfig Environment for each application
resource "aws_appconfig_environment" "feature_flags_env" {
  for_each      = local.config_files
  
  name           = var.environment
  description    = "Environment for ${each.key} based on branch ${var.environment}"
  application_id = aws_appconfig_application.feature_flags_app[each.key].id
  
  # Include explicit tags to match existing resources
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# AWS AppConfig Configuration Profile for each application
resource "aws_appconfig_configuration_profile" "feature_flags_profile" {
  for_each      = local.config_files
  
  name           = each.key
  description    = "Configuration profile for ${each.key}"
  application_id = aws_appconfig_application.feature_flags_app[each.key].id
  location_uri   = "hosted"
  type           = "AWS.AppConfig.FeatureFlags"
  
  # Include explicit tags to match existing resources
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Track meaningful changes to configuration content
resource "terraform_data" "config_hash_tracker" {
  for_each = local.config_files
  
  # Use only meaningful content hash as input to trigger changes
  input = local.meaningful_content_hash[each.key]
  
  # Output the hash for reference in outputs
  output = local.meaningful_content_hash[each.key]
}

# Comprehensive debug for fixed content including attributes and metadata
resource "terraform_data" "debug_fixed_content" {
  for_each = local.fixed_contents
  
  input = {
    file_name = each.key
    counts = {
      flags = length(each.value.flags)
      values = length(each.value.values)
    }
    flags_details = {
      for flag_name, flag_data in each.value.flags : flag_name => {
        name = flag_data.name
        has_attributes = contains(keys(flag_data), "attributes")
        attributes = try(flag_data.attributes, {})
      }
    }
    values_details = {
      for value_name, value_data in each.value.values : value_name => {
        enabled = try(value_data.enabled, null)
        # Dynamically include all other properties
        metadata = {
          for k, v in value_data : k => v if k != "enabled"
        }
      }
    }
    # Add meaningful content hash for debugging
    meaningful_content_hash = local.meaningful_content_hash[each.key]
  }
}

# Hosted Configuration Version for each configuration profile
resource "aws_appconfig_hosted_configuration_version" "feature_flags_version" {
  for_each      = local.config_files
    
  application_id           = aws_appconfig_application.feature_flags_app[each.key].id
  configuration_profile_id = aws_appconfig_configuration_profile.feature_flags_profile[each.key].configuration_profile_id
  description              = "Feature flags version ${var.config_version}"
    
  content_type             = "application/json"
    
  # Use raw JSON format with direct interpolation and version as a string
  content = <<-EOT
{
  "flags": ${jsonencode(local.fixed_contents[each.key].flags)},
  "values": ${jsonencode(local.fixed_contents[each.key].values)},
  "version": "1"
}
EOT

  # Add lifecycle configuration to prevent unnecessary updates
  lifecycle {
    # Only replace when the meaningful content hash changes
    replace_triggered_by = [
      terraform_data.config_hash_tracker[each.key]
    ]
    
    # Ignore changes to content since we're controlling replacement with the hash tracker
    ignore_changes = [
      content
    ]
  }
}

# Note: Deployment resource has been removed to allow deployment through Angular UI instead