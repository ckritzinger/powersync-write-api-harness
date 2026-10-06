# Issues test JWTs and publishes the public signing key. A local dev tool in the same spirit as the
# rest of this app: unauthenticated, and it hands a token to anyone who names a test user.
#
#   GET /api/auth/token?user_id=user-alice[&mode=expired]   -> { token, powersync_url, sub, mode }
#   GET /api/auth/keys, /.well-known/jwks.json               -> the public key as a JWKS
#
# The first path matches the PowerSync reference connector's demo token endpoint, so the connector
# runs unmodified against it (via the frontend server's proxy).
class AuthController < ActionController::API
  rescue_from TokenIssuer::ConfigurationError do |error|
    render json: { message: error.message }, status: :internal_server_error
  end

  def token
    user = TestUsers.find(params[:user_id].to_s)
    return render(json: { message: "Unknown user_id. Use one of: #{TestUsers.ids.join(', ')}" }, status: :bad_request) unless user

    mode = params.fetch(:mode, "valid").to_s
    unless TokenIssuer::MODES.include?(mode)
      return render(json: { message: "Unknown mode. Use one of: #{TokenIssuer::MODES.join(', ')}" }, status: :bad_request)
    end

    render json: {
      token: TokenIssuer.issue(user, mode: mode),
      powersync_url: ENV["POWERSYNC_URL"].presence,
      sub: user.id,
      mode: mode
    }
  end

  def keys
    render json: SigningKey.current.jwks
  end
end
