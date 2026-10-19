# Chaîne JS d'une app hôte (Hotwire). La gem ajoute ses propres pins
# (upload_d_n_d) via son moteur.
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "controllers/application", to: "controllers/application.js"
