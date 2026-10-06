# The test identities, for the frontend's user switcher, and the token modes it can request.
class UsersController < ActionController::API
  def index
    render json: {
      users: TestUsers::ALL.map { |user| { id: user.id, name: user.name, role: user.role } },
      token_modes: TokenIssuer::MODES
    }
  end
end
