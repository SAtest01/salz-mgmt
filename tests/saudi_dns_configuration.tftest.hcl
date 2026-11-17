mock_provider "alz" {}
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "azurerm" {
  alias = "connectivity"
}
mock_provider "azurerm" {
  alias = "management"
}
mock_provider "azapi" {}
mock_provider "azapi" {
  alias = "connectivity"
}
mock_provider "local" {}
mock_provider "random" {}
mock_provider "time" {}

override_module {
  target = module.config.module.regions
  outputs = {
    regions_by_name = {
      saudiarabiaeast = {
        geo_code   = null
        short_name = "sae"
      }
    }
  }
}

run "saudi_policy_uses_same_backup_geo_code_without_disabling_dns" {
  command = plan

  variables {
    connectivity_type            = "none"
    management_groups_enabled    = false
    management_resources_enabled = false
    enable_telemetry             = false
  }

  assert {
    condition = (
      jsondecode(local.policy_assignments_to_modify.corp.policy_assignments["Deploy-Private-DNS-Zones"].parameters.dnzZoneRegionShortNames).value.saudiarabiaeast == "sae" &&
      jsondecode(local.policy_default_values.private_dns_zone_region).value == "saudiarabiaeast"
    )
    error_message = "The real tfvars must pass the confirmed Saudi geo code and region to the Private DNS policy."
  }

  assert {
    condition = (
      module.config.outputs.virtual_hubs.primary.enabled_resources.private_dns_zones &&
      module.config.outputs.virtual_hubs.primary.enabled_resources.private_dns_resolver &&
      module.config.outputs.virtual_hubs.primary.private_dns_zones.auto_registration_zone_enabled
    )
    error_message = "The Saudi compatibility patch must preserve private DNS, DNS resolver, and auto-registration."
  }
}
