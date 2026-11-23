Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # MCP (Streamable HTTP) for the chirpbin MCP gateway; see McpController.
  post "mcp", to: "mcp#create"
  match "mcp", to: "mcp#unsupported", via: %i[get delete]

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
