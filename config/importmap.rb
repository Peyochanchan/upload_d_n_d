# Point d'entrée principal : import "upload_d_n_d" dans application.js
pin "upload_d_n_d", to: "upload_d_n_d/index.js"

# Pins individuels (pour import sélectif si besoin)
pin_all_from File.expand_path("../app/javascript/upload_d_n_d/controllers", __dir__), under: "upload_d_n_d/controllers"
