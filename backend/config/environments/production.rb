Rails.application.configure do
  config.enable_reloading = false
  # A local dev oracle: show errors (e.g. DB unreachable) instead of a generic 500 page.
  config.consider_all_requests_local = true
  config.public_file_server.enabled = true
end
