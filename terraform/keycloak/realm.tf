resource "keycloak_realm" "infrastructure" {
  realm   = "infrastructure"
  enabled = true

  display_name = "Infrastructure"

  login_theme   = "keycloak"
  account_theme = "keycloak.v3"

  access_token_lifespan = "5m"

  login_with_email_allowed  = true
  duplicate_emails_allowed  = false
  reset_password_allowed    = true
  remember_me              = true
}
