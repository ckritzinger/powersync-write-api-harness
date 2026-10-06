Rails.application.routes.draw do
  root "lists#index"
  resources :lists, only: %i[index show]
  resources :todos, only: %i[index]

  # Test auth: tokens for the frontend, and the public key PowerSync and the write API trust.
  get "api/auth/token" => "auth#token"
  get "api/auth/keys" => "auth#keys"
  get ".well-known/jwks.json" => "auth#keys"
  get "api/users" => "users#index"

  get "up" => proc { [200, {}, ["ok"]] }
end
