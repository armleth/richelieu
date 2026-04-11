data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_authentication" {
  slug = "default-authentication-flow"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# --- ArgoCD OIDC ---

resource "authentik_provider_oauth2" "argocd" {
  name               = "ArgoCD"
  authorization_flow = data.authentik_flow.default_authorization.id
  client_id          = "argocd"
  signing_key        = data.authentik_certificate_key_pair.default.id

  redirect_uris = [
    "https://argocd.${local.domain}/auth/callback",
  ]

  property_mappings = [
    data.authentik_scope_mapping.openid.id,
    data.authentik_scope_mapping.profile.id,
    data.authentik_scope_mapping.email.id,
    authentik_scope_mapping.groups.id,
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
  client_id          = "vault"
  signing_key        = data.authentik_certificate_key_pair.default.id

  redirect_uris = [
    "https://vault.${local.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  property_mappings = [
    data.authentik_scope_mapping.openid.id,
    data.authentik_scope_mapping.profile.id,
    data.authentik_scope_mapping.email.id,
    authentik_scope_mapping.groups.id,
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
