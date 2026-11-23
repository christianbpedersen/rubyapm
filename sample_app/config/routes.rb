Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"
  resources :products, only: %i[index show]
  get "search", to: "search#index"
  resources :orders, only: %i[index show create]
  get "reports/sales", to: "reports#sales"
  get "reports/live", to: "reports#live"
  get "customers/:id/history", to: "customers#history", as: :customer_history
  namespace :api do
    resources :products, only: %i[index show]
    post "inventory/sync", to: "inventory#sync"
  end
  post "/graphql", to: "graphql#execute"
end
