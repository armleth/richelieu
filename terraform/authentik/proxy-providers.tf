# --- Homepage (any authenticated user) ---

resource "authentik_provider_proxy" "homepage" {
  name               = "Homepage"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://home.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "homepage" {
  name              = "Homepage"
  slug              = "homepage"
  protocol_provider = authentik_provider_proxy.homepage.id
}

# --- Bbox (admin + bbox groups) ---

resource "authentik_provider_proxy" "bbox" {
  name               = "Bbox"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://bbox.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "bbox" {
  name              = "Bbox"
  slug              = "bbox"
  protocol_provider = authentik_provider_proxy.bbox.id
}

resource "authentik_policy_binding" "bbox_admin" {
  target = authentik_application.bbox.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "bbox_bbox" {
  target = authentik_application.bbox.uuid
  group  = authentik_group.bbox.id
  order  = 1
}

# --- Code Server (admin + dev groups) ---

resource "authentik_provider_proxy" "code_server" {
  name               = "Code Server"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://dev.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "code_server" {
  name              = "Code Server"
  slug              = "code-server"
  protocol_provider = authentik_provider_proxy.code_server.id
}

resource "authentik_policy_binding" "code_server_admin" {
  target = authentik_application.code_server.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "code_server_dev" {
  target = authentik_application.code_server.uuid
  group  = authentik_group.dev.id
  order  = 1
}

# --- Radarr (admin + media groups) ---

resource "authentik_provider_proxy" "radarr" {
  name               = "Radarr"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://movies.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "radarr" {
  name              = "Radarr"
  slug              = "radarr"
  protocol_provider = authentik_provider_proxy.radarr.id
}

resource "authentik_policy_binding" "radarr_admin" {
  target = authentik_application.radarr.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "radarr_media" {
  target = authentik_application.radarr.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- Sonarr (admin + media groups) ---

resource "authentik_provider_proxy" "sonarr" {
  name               = "Sonarr"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://series.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "sonarr" {
  name              = "Sonarr"
  slug              = "sonarr"
  protocol_provider = authentik_provider_proxy.sonarr.id
}

resource "authentik_policy_binding" "sonarr_admin" {
  target = authentik_application.sonarr.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "sonarr_media" {
  target = authentik_application.sonarr.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- Bazarr (admin + media groups) ---

resource "authentik_provider_proxy" "bazarr" {
  name               = "Bazarr"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://subtitles.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "bazarr" {
  name              = "Bazarr"
  slug              = "bazarr"
  protocol_provider = authentik_provider_proxy.bazarr.id
}

resource "authentik_policy_binding" "bazarr_admin" {
  target = authentik_application.bazarr.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "bazarr_media" {
  target = authentik_application.bazarr.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- Prowlarr (admin + media groups) ---

resource "authentik_provider_proxy" "prowlarr" {
  name               = "Prowlarr"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://trackers.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "prowlarr" {
  name              = "Prowlarr"
  slug              = "prowlarr"
  protocol_provider = authentik_provider_proxy.prowlarr.id
}

resource "authentik_policy_binding" "prowlarr_admin" {
  target = authentik_application.prowlarr.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "prowlarr_media" {
  target = authentik_application.prowlarr.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- qBittorrent (admin + media groups) ---

resource "authentik_provider_proxy" "qbittorrent" {
  name               = "qBittorrent"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://torrents.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "qbittorrent" {
  name              = "qBittorrent"
  slug              = "qbittorrent"
  protocol_provider = authentik_provider_proxy.qbittorrent.id
}

resource "authentik_policy_binding" "qbittorrent_admin" {
  target = authentik_application.qbittorrent.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "qbittorrent_media" {
  target = authentik_application.qbittorrent.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- Flood (admin + media groups) ---

resource "authentik_provider_proxy" "flood" {
  name               = "Flood"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://downloads.media.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "flood" {
  name              = "Flood"
  slug              = "flood"
  protocol_provider = authentik_provider_proxy.flood.id
}

resource "authentik_policy_binding" "flood_admin" {
  target = authentik_application.flood.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "flood_media" {
  target = authentik_application.flood.uuid
  group  = authentik_group.media.id
  order  = 1
}

# --- Lathibandolaise Test (admin + dev groups) ---

resource "authentik_provider_proxy" "lathibandolaise_test" {
  name               = "Lathibandolaise Test"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://test.lathibandolaise.dev.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "lathibandolaise_test" {
  name              = "Lathibandolaise Test"
  slug              = "lathibandolaise-test"
  protocol_provider = authentik_provider_proxy.lathibandolaise_test.id
}

resource "authentik_policy_binding" "lathibandolaise_test_admin" {
  target = authentik_application.lathibandolaise_test.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "lathibandolaise_test_dev" {
  target = authentik_application.lathibandolaise_test.uuid
  group  = authentik_group.dev.id
  order  = 1
}

# --- Lathibandolaise Prod (admin + dev groups) ---

resource "authentik_provider_proxy" "lathibandolaise_prod" {
  name               = "Lathibandolaise Prod"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://prod.lathibandolaise.dev.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "lathibandolaise_prod" {
  name              = "Lathibandolaise Prod"
  slug              = "lathibandolaise-prod"
  protocol_provider = authentik_provider_proxy.lathibandolaise_prod.id
}

resource "authentik_policy_binding" "lathibandolaise_prod_admin" {
  target = authentik_application.lathibandolaise_prod.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "lathibandolaise_prod_dev" {
  target = authentik_application.lathibandolaise_prod.uuid
  group  = authentik_group.dev.id
  order  = 1
}

# --- DbGate (admin + dev groups) ---

resource "authentik_provider_proxy" "dbgate" {
  name               = "DbGate"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  external_host      = "https://db.lathibandolaise.dev.${local.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "dbgate" {
  name              = "DbGate"
  slug              = "dbgate"
  protocol_provider = authentik_provider_proxy.dbgate.id
}

resource "authentik_policy_binding" "dbgate_admin" {
  target = authentik_application.dbgate.uuid
  group  = authentik_group.admin.id
  order  = 0
}

resource "authentik_policy_binding" "dbgate_dev" {
  target = authentik_application.dbgate.uuid
  group  = authentik_group.dev.id
  order  = 1
}

# --- Embedded Outpost (serves /outpost.goauthentik.io/auth/traefik) ---

resource "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
  protocol_providers = [
    authentik_provider_proxy.homepage.id,
    authentik_provider_proxy.bbox.id,
    authentik_provider_proxy.code_server.id,
    authentik_provider_proxy.radarr.id,
    authentik_provider_proxy.sonarr.id,
    authentik_provider_proxy.bazarr.id,
    authentik_provider_proxy.prowlarr.id,
    authentik_provider_proxy.qbittorrent.id,
    authentik_provider_proxy.flood.id,
    authentik_provider_proxy.lathibandolaise_test.id,
    authentik_provider_proxy.lathibandolaise_prod.id,
    authentik_provider_proxy.dbgate.id,
  ]
}
