resource "keycloak_group" "admins" {
  realm_id = keycloak_realm.infrastructure.id
  name     = "admins"
}

# Protocol mapper to include groups in the OIDC token
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.argocd.id
  name      = "group-membership"

  claim_name = "groups"
  full_path  = false
}

resource "keycloak_openid_group_membership_protocol_mapper" "vault_groups" {
  realm_id  = keycloak_realm.infrastructure.id
  client_id = keycloak_openid_client.vault.id
  name      = "group-membership"

  claim_name = "groups"
  full_path  = false
}
