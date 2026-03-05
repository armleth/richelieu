resource "keycloak_openid_client" "argocd" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = "argocd"
  name      = "ArgoCD"
  enabled   = true

  access_type              = "CONFIDENTIAL"
  standard_flow_enabled    = true
  direct_access_grants_enabled = false

  root_url = "https://argocd.armleth.fr"
  valid_redirect_uris = [
    "https://argocd.armleth.fr/auth/callback",
  ]
  web_origins = [
    "https://argocd.armleth.fr",
  ]
}

resource "keycloak_openid_client" "vault" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = "vault"
  name      = "Vault"
  enabled   = true

  access_type              = "CONFIDENTIAL"
  standard_flow_enabled    = true
  direct_access_grants_enabled = false

  root_url = "https://vault.armleth.fr"
  valid_redirect_uris = [
    "https://vault.armleth.fr/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
  web_origins = [
    "https://vault.armleth.fr",
  ]
}

output "argocd_client_secret" {
  value     = keycloak_openid_client.argocd.client_secret
  sensitive = true
}

output "vault_client_secret" {
  value     = keycloak_openid_client.vault.client_secret
  sensitive = true
}

resource "keycloak_openid_client" "bbox" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = "bbox"
  name      = "Bbox"
  enabled   = true

  access_type              = "CONFIDENTIAL"
  standard_flow_enabled    = true
  direct_access_grants_enabled = false

  root_url = "https://bbox.armleth.fr"
  valid_redirect_uris = [
    "https://bbox.armleth.fr/oauth2/callback",
  ]
  web_origins = [
    "https://bbox.armleth.fr",
  ]
}

output "bbox_client_secret" {
  value     = keycloak_openid_client.bbox.client_secret
  sensitive = true
}
