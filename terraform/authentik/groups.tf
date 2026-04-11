resource "authentik_group" "admin" {
  name         = "admin"
  is_superuser = true
}

resource "authentik_group" "bbox" {
  name = "bbox"
}

resource "authentik_group" "dev" {
  name = "dev"
}
