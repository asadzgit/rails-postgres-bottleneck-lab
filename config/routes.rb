Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"
  get "lab/connections", to: "lab#connection_work"
  get "lab/pool", to: "lab#pool"
  post "lab/locks/increment", to: "lab#increment"
  get "lab/metrics", to: "lab_metrics#show"
  get "lab/cache/items/:id", to: "advanced_lab#cache_read"
  post "lab/cache/items/:id/increment", to: "advanced_lab#cache_write"
  get "lab/replica/items/:id", to: "advanced_lab#replica_read"
  post "lab/replica/items/:id/increment", to: "advanced_lab#replica_write"
  get "lab/partitions/summary", to: "advanced_lab#partition_summary"
  get "lab/shards/customers/:id/orders", to: "advanced_lab#shard_orders"
  get "lab/shards/summary", to: "advanced_lab#shard_summary"
  resources :customers, only: [ :index, :show ] do
    resources :orders, only: :index
  end
end
