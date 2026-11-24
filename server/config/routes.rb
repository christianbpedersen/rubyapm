Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Sign-in and users.
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  get "password/:token", to: "password_setups#edit", as: :password_setup
  patch "password/:token", to: "password_setups#update"
  resources :users, except: :show do
    post :setup_link, on: :member
  end
  resource :account, only: %i[show update], controller: "account" do
    patch :password
    delete :sessions, action: :sign_out_others, as: :other_sessions
  end
  resources :api_tokens, only: %i[create destroy], path: "account/tokens"
  delete "account/connections/:client_id", to: "api_tokens#revoke_client", as: :oauth_connection

  # MCP (Streamable HTTP) and the OAuth server its clients sign in with.
  post "mcp", to: "mcp#create"
  match "mcp", to: "mcp#unsupported", via: %i[get delete]
  get ".well-known/oauth-protected-resource(/mcp)", to: "oauth/metadata#protected_resource"
  get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  post "oauth/register", to: "oauth/registrations#create"
  get "oauth/authorize", to: "oauth/authorizations#new"
  post "oauth/authorize", to: "oauth/authorizations#create"
  post "oauth/token", to: "oauth/tokens#create"
  post "oauth/revoke", to: "oauth/tokens#revoke"

  namespace :api do
    namespace :v1 do
      post "ingest", to: "ingest#create"
    end
  end

  root "apps#index"
  resources :apps, only: %i[index show new create destroy] do
    member do
      get :settings
      post :regenerate_key
    end
    get "transactions", to: "transactions#index", as: :transactions
    get "transaction", to: "transactions#show", as: :transaction
    resources :traces, only: :show
    get "database", to: "database#index", as: :database
    get "sql/:key", to: "database#show", as: :sql
    resources :slow_queries, only: %i[index show], path: "slow-queries"
    get "code", to: "segments#index", as: :segments
    get "segment", to: "segments#show", as: :segment
    get "external", to: "external#index", as: :external
    get "external/:service", to: "external#show", as: :external_host, constraints: { service: %r{[^/]+} }
    get "graphql", to: "graphql#index", as: :graphql
    resources :errors, only: %i[index show], param: :fingerprint
    get "hosts", to: "hosts#index", as: :hosts
    resources :alerts, except: :show
    resources :deployments, only: %i[index show]
    get "search", to: "search#index", as: :search
  end
end
