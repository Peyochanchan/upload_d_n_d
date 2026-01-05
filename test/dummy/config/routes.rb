Rails.application.routes.draw do
  mount UploadDND::Engine => "/upload_d_n_d"
  
  root "home#index"
end
