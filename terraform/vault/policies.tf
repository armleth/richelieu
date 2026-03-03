resource "vault_policy" "external_secrets" {
  name = "external-secrets"

  policy = <<-EOT
    path "secret/data/*" {
      capabilities = ["read"]
    }

    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "admin" {
  name = "admin"

  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}
