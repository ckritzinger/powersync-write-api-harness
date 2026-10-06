require_relative "boot"
require_relative "../lib/source_database"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"

# Exactly one ORM is loaded, matching the write API's DATABASE_TYPE, so a Mongo setup never needs
# an ActiveRecord connection and vice versa.
if SourceDatabase.mongodb?
  require "mongoid"
else
  require "active_record/railtie"
  # Not built into ActiveRecord; registers the sqlserver adapter (Bundler.require is not used).
  require "activerecord-sqlserver-adapter" if SourceDatabase.type == "mssql"
end

module ReadApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = Rails.env.production?

    # Both directories define List and Todo; only the active ORM's set is on the load path.
    # They live outside app/ because Rails autoloads every app/* directory.
    models_dir = SourceDatabase.mongodb? ? "models/mongoid" : "models/active_record"
    config.autoload_paths << Rails.root.join(models_dir)
    config.eager_load_paths << Rails.root.join(models_dir)

    # No sessions, cookies, or forms that post: this app only reads.
    config.secret_key_base = ENV["SECRET_KEY_BASE"].presence || SecureRandom.hex(64)
    config.session_store :disabled
    config.action_controller.allow_forgery_protection = false

    config.hosts.clear
    config.logger = ActiveSupport::Logger.new($stdout)
    config.log_level = ENV.fetch("LOG_LEVEL", "info")
  end
end
