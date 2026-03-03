provider "keycloak" {
  # Set via environment variables:
  #   KEYCLOAK_URL       (e.g. http://localhost:8080)
  #   KEYCLOAK_USER      (admin)
  #   KEYCLOAK_PASSWORD  (from keycloak k8s secret)
  client_id = "admin-cli"
}
