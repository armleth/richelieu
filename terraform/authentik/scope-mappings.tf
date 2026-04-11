data "authentik_scope_mapping" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_scope_mapping" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_scope_mapping" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

resource "authentik_scope_mapping" "groups" {
  name       = "groups"
  scope_name = "groups"
  expression = <<-EOF
    return {
        "groups": [group.name for group in request.user.ak_groups.all()],
    }
  EOF
}
