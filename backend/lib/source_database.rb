require "uri"
require "active_support/core_ext/object/blank"

# Resolves the source database from the same variables the write API uses, so the two are
# switched in lockstep: DATABASE_TYPE (postgres | mysql | mssql | mongodb) and DATABASE_URI.
#
# DATABASE_URL (ActiveRecord) or MONGODB_URI (Mongoid) take precedence when set, for URLs that
# need adapter-specific options the write API's URI does not carry.
module SourceDatabase
  TYPES = %w[postgres mysql mssql mongodb].freeze
  AR_SCHEMES = { "postgres" => "postgresql", "mysql" => "mysql2", "mssql" => "sqlserver" }.freeze

  module_function

  def type
    value = ENV.fetch("DATABASE_TYPE", "postgres")
    raise ArgumentError, "DATABASE_TYPE must be one of #{TYPES.join(', ')}" unless TYPES.include?(value)
    value
  end

  def mongodb?
    type == "mongodb"
  end

  def active_record_url
    return ENV["DATABASE_URL"] if ENV["DATABASE_URL"].present?
    uri = ENV["DATABASE_URI"].presence or raise ArgumentError, "Set DATABASE_URI (or DATABASE_URL)"
    parsed = URI.parse(uri)
    parsed.scheme = AR_SCHEMES.fetch(type)
    parsed.to_s
  end

  def mongodb_uri
    ENV["MONGODB_URI"].presence || ENV["DATABASE_URI"].presence or raise ArgumentError, "Set DATABASE_URI (or MONGODB_URI)"
  end

  # For display: scheme, host and database only, never credentials.
  def description
    uri = URI.parse(mongodb? ? mongodb_uri : active_record_url)
    "#{type} #{uri.host}#{":#{uri.port}" if uri.port}#{uri.path}"
  rescue URI::InvalidURIError, ArgumentError
    "#{type} (unparseable URI)"
  end
end
