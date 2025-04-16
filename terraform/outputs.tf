output "application_ids" {
  description = "Map of AWS AppConfig Application IDs"
  value       = { for key, app in aws_appconfig_application.feature_flags_app : app.name => app.id }
}

output "environment_ids" {
  description = "Map of AWS AppConfig Environment IDs"
  value       = { for key, env in aws_appconfig_environment.feature_flags_env : aws_appconfig_application.feature_flags_app[key].name => env.id }
}

output "debug_fixed_content" {
  description = "Detailed debug information about fixed content including attributes and metadata"
  value = {
    for k, v in terraform_data.debug_fixed_content : k => jsondecode(jsonencode(v.input))
  }
}

output "configuration_profile_ids" {
  description = "Map of AWS AppConfig Configuration Profile IDs"
  value       = { for key, profile in aws_appconfig_configuration_profile.feature_flags_profile : aws_appconfig_application.feature_flags_app[key].name => profile.id }
}

output "deployment_strategy_id" {
  description = "AWS AppConfig Deployment Strategy ID"
  value       = aws_appconfig_deployment_strategy.quick_deployment.id
}

output "hosted_configuration_versions" {
  description = "Map of AWS AppConfig Configuration Version Numbers"
  value       = { for key, version in aws_appconfig_hosted_configuration_version.feature_flags_version : aws_appconfig_application.feature_flags_app[key].name => version.version_number }
}

output "clean_content" {
  description = "Clean content for each configuration (without timestamps)"
  value       = { for name, content in local.clean_content : name => content }
}

# Removed deployment_ids and deployment_statuses outputs