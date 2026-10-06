require "jwt"

# Issues the test JWTs. `valid` tokens are what PowerSync sync uses; the other modes produce
# deliberately broken tokens for the write API's auth rejection tests (TestPlan §2), requested by
# the frontend's /api/data proxy.
#
# Claims: iss = JWT_ISSUER (default write-api-harness), aud = JWT_AUDIENCE, falling back to
# POWERSYNC_URL, which PowerSync accepts without further configuration. Set both in backend/.env.
class TokenIssuer
  MODES = %w[valid expired not-yet-valid wrong-issuer wrong-audience wrong-key no-sub symmetric-hs256 malformed missing].freeze

  class ConfigurationError < StandardError; end

  class << self
    def issuer = ENV["JWT_ISSUER"].presence || "write-api-harness"

    def audience
      ENV["JWT_AUDIENCE"].presence || ENV["POWERSYNC_URL"].presence or
        raise ConfigurationError, "Set JWT_AUDIENCE (or POWERSYNC_URL) in backend/.env: the audience PowerSync and the write API accept."
    end

    def ttl_seconds = Integer(ENV["TOKEN_TTL_SECONDS"].presence || 3600)

    # Returns the token string, or nil for the `missing` mode (no Authorization header at all).
    def issue(user, mode: "valid")
      raise ArgumentError, "unknown mode #{mode.inspect}" unless MODES.include?(mode)
      return nil if mode == "missing"
      return "not-a.jwt.token" if mode == "malformed"

      now = Time.now.to_i
      payload = {
        "iss" => mode == "wrong-issuer" ? "#{issuer}-wrong" : issuer,
        "aud" => mode == "wrong-audience" ? "#{audience}-wrong" : audience,
        "role" => user.role,
        "name" => user.name,
        "iat" => now,
        "exp" => now + ttl_seconds
      }
      payload["sub"] = user.id unless mode == "no-sub"
      case mode
      when "expired" then payload.merge!("iat" => now - 7200, "exp" => now - 3600)
      when "not-yet-valid" then payload.merge!("nbf" => now + 3600, "exp" => now + 7200)
      end

      current = SigningKey.current
      return JWT.encode(payload, "x" * 32, "HS256", { kid: current.kid }) if mode == "symmetric-hs256"

      key = mode == "wrong-key" ? SigningKey.rogue : current
      JWT.encode(payload, key.private_key, "RS256", { kid: key.kid })
    end
  end
end
