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
