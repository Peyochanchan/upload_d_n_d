Rails.application.routes.draw do
  mount UploadDND::Engine => "/upload_d_n_d"

  resources :demo_projects, except: :destroy

  root "home#index"
end
