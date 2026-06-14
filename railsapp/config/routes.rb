Rails.application.routes.draw do
  resources :dioramas,
            only: [ :index, :show ],
            format: false,
            constraints: { id: /[^\/]+/ } do
    post :bootstrap_default, on: :collection
    resources :nodes,
              controller: "diorama_nodes",
              only: [ :new, :create, :show, :edit, :update ],
              format: false,
              constraints: { id: /[^\/]+/, diorama_id: /[^\/]+/ }
  end

  resources :twitch_configs
  get  "chat/index"
  get  "basic_setup/index"
  post "clip_show/play"
  get  "clip_show/get_scenes"
  get  "clip_show" => "clip_show#get_scenes", as: :clip_show
  get  "interaction_demo" => "interaction_demo#show", as: :interaction_demo
  post "interaction_demo/starfall" => "interaction_demo#starfall", as: :interaction_demo_starfall
  post "interaction_demo/sunburst" => "interaction_demo#sunburst", as: :interaction_demo_sunburst
  post "interaction_demo/wtf" => "interaction_demo#wtf", as: :interaction_demo_wtf

  resource :obs_config, only: [ :show, :edit, :update, :create ]

  namespace :admin do
    resources :obs_bridges, only: [ :show ], param: :id do
      post :start, on: :member
      post :stop, on: :member
      post :refresh, on: :member
      post :capture_all, on: :member
    end
  end

  # root "clip_show#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "clip_show#get_scenes"
end
