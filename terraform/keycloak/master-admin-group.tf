data "keycloak_realm" "master" {
  realm = "master"
}

data "keycloak_role" "master_admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

data "keycloak_role" "master_create_realm" {
  realm_id = data.keycloak_realm.master.id
  name     = "create-realm"
}

resource "keycloak_group" "master_admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

resource "keycloak_group_roles" "master_admin" {
  realm_id = data.keycloak_realm.master.id
  group_id = keycloak_group.master_admin.id

  role_ids = [
    data.keycloak_role.master_admin.id,
    data.keycloak_role.master_create_realm.id,
  ]
}
