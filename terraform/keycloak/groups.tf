resource "keycloak_group" "admins" {
  realm_id = keycloak_realm.infrastructure.id
  name     = "admins"
}

resource "keycloak_group" "bbox" {
  realm_id = keycloak_realm.infrastructure.id
  name     = "bbox"
}

# Client scope so that clients can request "groups" as an OIDC scope
resource "keycloak_openid_client_scope" "groups" {
  realm_id               = keycloak_realm.infrastructure.id
  name                   = "groups"
  description            = "Group membership"
  include_in_token_scope = true
}

# Protocol mapper to include groups in the token when the scope is requested
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = keycloak_realm.infrastructure.id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "group-membership"

  claim_name = "groups"
  full_path  = false
}

# Assign the groups scope to ArgoCD and Vault clients
resource "keycloak_openid_client_default_scopes" "argocd" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.argocd.id
  default_scopes = [
    "openid",
    "profile",
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}

resource "keycloak_openid_client_default_scopes" "vault" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.vault.id
  default_scopes = [
    "openid",
    "profile",
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}

resource "keycloak_openid_client_default_scopes" "bbox" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.bbox.id
  default_scopes = [
    "openid",
    "profile",
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}

resource "keycloak_openid_client_default_scopes" "jellyfin" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.jellyfin.id
  default_scopes = [
    "openid",
    "profile",
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}
