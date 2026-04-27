data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_authentication" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-invalidation-flow"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# --- ArgoCD OIDC ---

resource "authentik_provider_oauth2" "argocd" {
  name               = "ArgoCD"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_id          = "argocd"
  signing_key        = data.authentik_certificate_key_pair.default.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argocd.${local.domain}/auth/callback"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]
}

resource "authentik_application" "argocd" {
  name              = "ArgoCD"
  slug              = "argocd"
  protocol_provider = authentik_provider_oauth2.argocd.id
}

resource "authentik_policy_binding" "argocd_admin" {
  target = authentik_application.argocd.uuid
  group  = authentik_group.admin.id
  order  = 0
}

output "argocd_client_secret" {
  value     = authentik_provider_oauth2.argocd.client_secret
  sensitive = true
}

# --- Vault OIDC ---

resource "authentik_provider_oauth2" "vault" {
  name               = "Vault"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_id          = "vault"
  signing_key        = data.authentik_certificate_key_pair.default.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://vault.${local.domain}/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8250/oidc/callback"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]
}

resource "authentik_application" "vault" {
  name              = "Vault"
  slug              = "vault"
  protocol_provider = authentik_provider_oauth2.vault.id
}

resource "authentik_policy_binding" "vault_admin" {
  target = authentik_application.vault.uuid
  group  = authentik_group.admin.id
  order  = 0
}

output "vault_client_secret" {
  value     = authentik_provider_oauth2.vault.client_secret
  sensitive = true
}

# --- Actual Budget OIDC (admin group only) ---

resource "authentik_provider_oauth2" "actual_budget" {
  name               = "Actual Budget"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_id          = "actual-budget"
  signing_key        = data.authentik_certificate_key_pair.default.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://finances.${local.domain}/openid/callback"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]
}

resource "authentik_application" "actual_budget" {
  name              = "Actual Budget"
  slug              = "actual-budget"
  protocol_provider = authentik_provider_oauth2.actual_budget.id
}

resource "authentik_policy_binding" "actual_budget_admin" {
  target = authentik_application.actual_budget.uuid
  group  = authentik_group.admin.id
  order  = 0
}

output "actual_budget_client_secret" {
  value     = authentik_provider_oauth2.actual_budget.client_secret
  sensitive = true
}

# --- Grafana OIDC (admin group) ---

resource "authentik_provider_oauth2" "grafana" {
  name               = "Grafana"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_id          = "grafana"
  signing_key        = data.authentik_certificate_key_pair.default.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://metrics.${local.domain}/login/generic_oauth"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
}

resource "authentik_policy_binding" "grafana_admin" {
  target = authentik_application.grafana.uuid
  group  = authentik_group.admin.id
  order  = 0
}

output "grafana_client_secret" {
  value     = authentik_provider_oauth2.grafana.client_secret
  sensitive = true
}

# --- Karakeep OIDC (admin group only) ---

resource "authentik_provider_oauth2" "karakeep" {
  name               = "Karakeep"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_id          = "karakeep"
  signing_key        = data.authentik_certificate_key_pair.default.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://bookmarks.${local.domain}/api/auth/callback/custom"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]
}

resource "authentik_application" "karakeep" {
  name              = "Karakeep"
  slug              = "karakeep"
  protocol_provider = authentik_provider_oauth2.karakeep.id
}

resource "authentik_policy_binding" "karakeep_admin" {
  target = authentik_application.karakeep.uuid
  group  = authentik_group.admin.id
  order  = 0
}

output "karakeep_client_secret" {
  value     = authentik_provider_oauth2.karakeep.client_secret
  sensitive = true
}
