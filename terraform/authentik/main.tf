provider "authentik" {
  # Set via environment variables:
  #   AUTHENTIK_URL   (e.g. http://localhost:9000)
  #   AUTHENTIK_TOKEN (API token from Authentik admin UI)
}

locals {
  domain = "armleth.fr"
}
