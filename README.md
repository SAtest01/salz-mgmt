# Azure Landing Zones Accelerator Starter Module for Terraform - Azure Verified Modules Complete Multi-Region

This module is part of the Azure Landing Zones Accelerator solution. It is a complete multi-region implementation of the Azure Landing Zones Platform Landing Zone for Terraform.

This deployment includes a pinned [Saudi Arabia East DNS compatibility patch](modules/vendor/README.md).
It preserves private DNS zones and uses the Azure-confirmed Backup zone
`privatelink.sae.backup.windowsazure.com`. Run `tests\Invoke-Tests.ps1` before an
authenticated CI plan; passing mocked tests is not deployment approval.

Private DNS Resolver is intentionally disabled because Azure rejected its creation
in Saudi Arabia East. Private DNS zones, VNet links, auto-registration, and their
policy configuration remain enabled. The resolver's endpoints and dedicated
subnet are also omitted by the networking module; review a fresh plan for removals
after a partial deployment. DNS forwarding from on-premises or custom DNS servers
requires an alternative resolver design.

It deploys a hub and spoke virtual network or Virtual WAN architecture across multiple regions.

The module supports the following resources; the Saudi profile below deliberately
omits unsupported capabilities:

- Management group hierarchy
- Azure Policy definitions and assignments
- Role definitions
- Management resources, including Log Analytics workspace and Automation account
- Hub and spoke virtual network or Virtual WAN architecture across multiple regions
- DDOS protection plan
- Private DNS zones

## Saudi Arabia East deployment profile

`platform-landing-zone.auto.tfvars` configures workloads in `saudiarabiaeast`,
with an approved exception for Azure Policy assignment identities in `uaenorth`.
The profile keeps the standard ALZ management-group IDs, Virtual WAN, the sidecar
VNet, Bastion, and Private DNS zones and links. Global governance and Private DNS
resources still use Azure's `global` location where required.

| Capability | Saudi profile |
| --- | --- |
| Policy-assignment managed identities | Per-policy system-assigned identities use UAE North because Azure rejected policy identity creation in Saudi Arabia East with `IdentityServiceUnavailable`. This changes identity placement, not the identity subscription, management-group scope, or workload location. |
| Private DNS Resolver | Disabled, including its endpoints and dedicated subnet. Zones and links remain enabled. |
| Log Analytics and central monitoring | Disabled: Azure rejected the workspace location, and the subscription's provider metadata also omits Saudi Arabia East for data collection rules/endpoints. The management module requires a workspace, so its monitoring resource group, AMA identity, DCRs, solutions, and optional Sentinel onboarding are omitted together. |
| Monitoring deployment policies | Root overrides remove activity/resource log export and the workspace-backed Defender configuration assignment. Landing-zone overrides also remove SQL auditing to Log Analytics. Existing platform/landing-zone AMA exclusions remain in place. |
| Bastion | Enabled with `zones = []` on both the host and its Standard public IP. The pinned Bastion module requires matching zone sets. Changing the existing public IP's zones requires replacement. |

Microsoft's [Bastion public IP compatibility table](https://learn.microsoft.com/azure/bastion/configuration-settings#configure-public-ip-addresses-with-availability-zones-configured)
allows a nonzonal Bastion host to use an existing zonal or nonzonal public IP,
but the pinned Bastion module's precondition is stricter. Both resources are
configured without zones to satisfy the module and Saudi regional support.

`management_group_settings.location = "uaenorth"` supplies the policy-assignment
identity location. Keep `policy_default_values.resource_group_location` and
`private_dns_zone_region` set to Saudi Arabia East: the ALZ library also uses its
location input for policy defaults, so these explicit values prevent policy
deployments from following the identity region. The networking region remains
Saudi Arabia East. User-assigned identities are supported by Azure Policy, but
switching identity type is not established as a workaround for this regional
failure; this profile retains the standard, separately permissioned identities.

These exclusions mean there is no centralized Log Analytics ingestion, VM
Insights/change tracking, or workspace-backed Defender configuration supplied by
this profile. Both Microsoft cloud security benchmarks and independent endpoint
protection/integration policies remain assigned; monitoring audit controls can
therefore report intentional noncompliance. This reduced profile is not equivalent
to the full ALZ monitoring and security baseline. No replacement workspace or
monitoring destination is configured outside Saudi Arabia. Availability is
subscription-specific and can change; recheck it before re-enabling omitted
capabilities.

### Recovering the partially deployed environment

Keep the existing remote Terraform state. Run **01 CI** for a fresh plan before
**02 CD**; a previous successful plan cannot be reused after changing this profile.
Review all deletions/replacements, especially the monitoring resource group and
its unused AMA identity, the DNS resolver subnet, and the Bastion host/public IP.
The existing Bastion public IP will be replaced to remove its zones, so its
address can change; the failed Bastion host may also need replacement.
Disabling a managed resource group can delete any resources inside it, including
resources not represented in this configuration.

Management-group IDs are tenant-wide unique. The configured child IDs, including
`platform`, must no longer exist under the old Contoso hierarchy before this
deployment can create them under `salz`. The environment owner is handling that
cleanup separately; this configuration neither renames nor deletes those groups.
Confirm all configured IDs, not just `platform`, are free or already owned by
this deployment. A plan run as a signed-in user does not prove that the separate
pipeline identities have the required access.

The reusable CI/CD templates must retain
`ARM_PROVIDER_ENHANCED_VALIDATION_LOCATIONS: "false"` in every Terraform plan and
apply job while Azure's public region metadata omits Saudi Arabia East. This
only bypasses the stale location check; it does not make unavailable services
deployable. A push/merge to `main` automatically triggers CD, so review the
recovery plan before merging.

## Usage

The module is intended to be used with the [Azure Landing Zones Accelerator](https://aka.ms/alz/acc). Head over there to get started.

>NOTE: The module can be used independently if needed. Example `tfvars` files can be found in the `examples` directory for that use case.

### Running Directly

#### Run the local examples

Create a `terraform.tfvars` file in the root of the module directory with the following content, replacing the placeholders with the actual values:

```hcl
starter_locations            = ["uksouth", "ukwest"]
subscription_id_connectivity = "00000000-0000-0000-0000-000000000000"
subscription_id_identity     = "00000000-0000-0000-0000-000000000000"
subscription_id_management   = "00000000-0000-0000-0000-000000000000"
```

##### Hub and Spoke Virtual Networks Multi Region

```powershell
terraform init
terraform apply -var-file ./examples/full-multi-region/hub-and-spoke-vnet.tfvars
```

##### Virtual WAN Multi Region

```powershell
terraform init
terraform apply -var-file ./examples/full-multi-region/virtual-wan.tfvars
```

### Virtual WAN module v0.18.0 inputs

The template pins the Virtual WAN pattern to `0.18.0` and exposes its newer inputs:

- `virtual_hubs[hub_key].is_primary` selects the primary region used for default
  Virtual WAN, DDoS Protection Plan, and private DNS zone locations. Only one
  hub may be primary. If none is marked, the first hub key alphabetically is
  selected; the default is `false`.
- `virtual_hubs[hub_key].vpn_site_connections[connection_key].vpn_links[*].dpd_timeout_seconds` sets the VPN link's dead peer detection timeout in seconds (9–3600).
- `ignore_body_changes` configures shared ignored body paths for secured hub
  firewalls, firewall diagnostic settings, route maps, sidecar virtual networks,
  and sidecar subnets. Per-subnet `ignore_body_changes` takes precedence over
  the shared subnet paths. Leave the matching dedicated input unset for ignored
  paths. These paths are write-only provider state, take effect after `apply`,
  and non-empty lists require Terraform 1.11 or later.

### Customer-owned public IPs for secured Virtual WAN hubs

Configure `virtual_hubs[hub_key].firewall.ip_configurations[stable_key]` to attach caller-owned public IPs. Each entry requires `name` and `public_ip_address_id`. Use stable keys known at plan time; the public IP resource ID itself may be unknown until apply.

| Customer IP map | `vhub_public_ip_count` | Mode |
| --- | --- | --- |
| Empty or omitted | Omitted or `null` | Existing managed-IP default, unchanged |
| Empty | Positive integer as a string | Managed IPs with that count |
| Nonempty | Omitted, `null`, or `"0"` | Customer-owned IPs only |
| Nonempty | Positive count | Invalid; customer and managed IPs cannot be combined |

The public IPs must meet the [secured hub prerequisites](https://learn.microsoft.com/azure/firewall/secured-hub-customer-public-ip):
Standard SKU, Regional tier, static IPv4, the same subscription as the firewall,
and the hub's region. They must be unassociated or already attached to this
firewall. Configuration names and public IP IDs must be unique ignoring case.
The firewall must use the `Standard` or `Premium` SKU tier. The firewall
attaches these IPs but does not create or own their lifecycle.

Literal IDs and the Accelerator's built-in/custom replacements are supported.
Resource expressions cannot be used in `.tfvars`; for an IP created in the same
apply, pass its ID directly in an HCL module call. The template preserves
apply-time IDs separately from whole-hub JSON templating so unknown IDs do not
make hub or configuration keys unknown. `templated_inputs` includes the
resolved IDs.

Customer IPs can be used when creating a firewall and can be added, removed, or
replaced on a firewall already in customer mode. Plan such changes as
maintenance; they are not guaranteed to be outage-free. Converting an existing
firewall between managed and customer IP modes, including removing its last
customer IP, is not supported. Keep an existing managed firewall in managed
mode when upgrading.
