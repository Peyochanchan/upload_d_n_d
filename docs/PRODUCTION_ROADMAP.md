# 🚀 UploadDND - Roadmap Production

> Document de synthèse et planification pour la mise en production de la gem UploadDND.
> Dernière mise à jour : **2026-01-19**

---

## 📊 État actuel du projet

### Version
- **Version actuelle** : `0.1.0`
- **Statut** : ⚠️ **Alpha - Non production-ready**
- **Dernière modification** : 2026-01-06

### Métriques de qualité

```bash
# Tests
✅ 189 tests passants
⚠️ 21 tests échouants (uploadable_spec.rb - problème config RSpec)
📊 Couverture : 25.23% (325/1288 lignes)

# Fichiers non trackés
⚠️ spec/lib/upload_d_n_d/controllers/uploadable_spec.rb (21 tests à fixer)
```

### Derniers commits

```
7cb85b6 - Ajout tests BaseAttachmentsController (33 tests, XSS, validation, session)
6cde228 - Optimisations performance (scope N+1, validation MIME côté client)
d0ab61b - Ignore coverage reports
fa5003d - Amélioration tests et organisation docs (v0.1.0)
```

---

## 🎯 Objectifs de mise en production

### Option A : Publication PUBLIQUE (RubyGems.org)
**Exigences strictes :**
- ✅ 100% des tests passants (0 failure)
- ✅ Couverture minimale : 80%
- ✅ Audit sécurité complet
- ✅ Documentation exhaustive
- ✅ CI/CD fonctionnel
- ✅ CHANGELOG et versioning strict (SemVer)

### Option B : Publication PRIVÉE (GitHub Packages / Serveur interne)
**Exigences minimales :**
- ✅ Tests critiques passants (controllers, models)
- ✅ Couverture minimale : 60%
- ✅ Configuration sécurité de base
- ✅ README + guide déploiement
- ⚠️ Tests manuels en staging obligatoires

---

## 📋 ROADMAP DÉTAILLÉE

### PHASE 0 : Stabilisation critique (Pré-requis)

**Priorité : 🔴 CRITIQUE - Bloquant pour toute mise en production**

#### 0.1 Corriger les tests échouants

**Problème actuel :**
- 21 tests échouent dans `spec/lib/upload_d_n_d/controllers/uploadable_spec.rb`
- Erreur : `undefined method 'to_sym' for nil` dans `rails_helper.rb:51`
- Cause probable : Conflit DatabaseCleaner avec `controller(ActionController::Base)`

**Actions :**
```ruby
# À investiguer dans spec/rails_helper.rb
config.around(:each) do |example|
  DatabaseCleaner.cleaning do
    example.run  # Ligne 51 - problème ici
  end
end
```

**Tâches :**
- [ ] Débugger `rails_helper.rb` ligne 51
- [ ] Vérifier compatibilité DatabaseCleaner avec RSpec controller tests
- [ ] Tester alternative : `use_transactional_fixtures = true`
- [ ] Valider tous les tests : `bundle exec rspec` (objectif : 210/210 ✅)

**Estimation :** 1-2 jours

---

#### 0.2 Augmenter la couverture de tests

**Objectif :** Passer de 25% à 70%+ (idéal : 80%)

**Tests prioritaires à ajouter :**

1. **Tests ViewComponent** (`spec/components/upload_d_n_d/upload_component_spec.rb`)
   - [ ] Rendu du composant avec/sans record
   - [ ] Génération attributs data Stimulus
   - [ ] Support multiple vs single upload
   - [ ] Résolution configuration (modèle > composant > global)
   - [ ] Auto-détection has_one vs has_many

2. **Tests Concern Uploadable** (modèle)
   - [ ] Méthode `uploadable` avec options
   - [ ] Callback `after_create :attach_temporary_uploads`
   - [ ] Gestion `temp_upload_session_id`
   - [ ] Validation configuration par attribut

3. **Tests Helpers** (`spec/helpers/upload_d_n_d/upload_helper_spec.rb`)
   - [ ] `upload_field` avec différentes options
   - [ ] `file_icon_class` pour différents types
   - [ ] `file_type_badge_class`
   - [ ] Conversion MIME types

4. **Tests Générateurs**
   - [ ] `spec/generators/install_generator_spec.rb`
   - [ ] `spec/generators/model_generator_spec.rb`
   - [ ] Support namespaces (Admin::Article, Manager::Report)
   - [ ] Options (--multiple, --content_type, --max_size)

5. **Tests Performance** (enrichir existants)
   - [ ] Upload concurrent (50+ fichiers)
   - [ ] Gros fichiers (>100MB)
   - [ ] Requêtes N+1 (scope `with_blobs`)
   - [ ] Timeout réseau

**Estimation :** 3-5 jours

---

### PHASE 1 : Fonctionnalités critiques manquantes

**Priorité : 🔴 HAUTE - Nécessaires pour parité avec l'app hôte et production**

#### 1.1 Support des Namespaces dans les routes

**Problème actuel :**
```ruby
# Gem actuelle : routes globales uniquement
UploadDND.attachments_path  # ❌ Pas de namespace

# l'app hôte : routes namespace-aware avec fallback
polymorphic_path([:app_core, record])   # ✅
polymorphic_path([:collaborator, record]) # ✅
```

**Impact :** Applications multi-namespace (admin, collaborator, public) ne peuvent pas utiliser la gem efficacement.

**Solution proposée :**
```ruby
# Option 1 : Ajouter namespace au composant
<%= upload_field :avatar, record: @user, namespace: :admin %>

# Option 2 : Auto-détection via controller
def controller_namespace
  self.class.name.deconstantize.underscore.presence&.to_sym
end

# Routes générées :
# /admin/upload_d_n_d/attachments (si namespace: :admin)
# /upload_d_n_d/attachments (si pas de namespace)
```

**Tâches :**
- [ ] Ajouter `namespace` param au ViewComponent
- [ ] Modifier path helpers (support `polymorphic_path`)
- [ ] Tester avec Admin::Article, Manager::Report
- [ ] Documenter usage multi-namespace

**Estimation :** 2-3 jours

**Référence :** Voir `doc/comparison_app_vs_gem.md` section 3.1

---

#### 1.2 Internationalisation (i18n)

**Problème actuel :**
```ruby
# Messages en anglais hardcodés
"Blob not found"
"Unauthorized to update this record"
"File is corrupted"
```

**Solution :**
```ruby
# config/locales/upload_d_n_d.fr.yml
fr:
  upload_d_n_d:
    errors:
      blob_not_found: "Fichier non trouvé"
      unauthorized: "Vous n'êtes pas autorisé à modifier ce fichier"
      corrupted: "Le fichier semble corrompu ou modifié"
      unrepresentable: "Le fichier n'est pas traitable"
      too_large: "Le fichier dépasse la taille maximale de %{max_size}"
      invalid_type: "Type de fichier non accepté. Formats autorisés : %{types}"
      max_files_exceeded: "Vous ne pouvez pas ajouter plus de %{max} fichiers"

# config/locales/upload_d_n_d.en.yml (anglais)
```

**Messages à internationaliser :**
- [ ] Erreurs serveur (controllers)
- [ ] Messages JavaScript (Stimulus)
- [ ] Labels et placeholders (ViewComponent)
- [ ] Notifications toast

**Tâches :**
- [ ] Créer fichiers locale FR + EN
- [ ] Remplacer tous les messages hardcodés
- [ ] Ajouter tests i18n (switch locale)
- [ ] Documenter ajout de nouvelles langues

**Estimation :** 2-3 jours

**Référence :** `doc/comparison_app_vs_gem.md` section 3.6

---

#### 1.3 Direct Upload vers S3/GCS

**Objectif :** Réduire charge serveur et améliorer performance pour gros fichiers.

**Fonctionnalités :**
```ruby
# Configuration
UploadDND.configure do |config|
  config.direct_upload_enabled = true
  config.direct_upload_service = :amazon # :google, :azure
  config.multipart_threshold = 100.megabytes
  config.retry_attempts = 3
end

# JavaScript : Upload direct client → S3
# Puis envoyer signed_blob_id au backend
```

**Avantages :**
- ⚡ Upload ne passe plus par le serveur Rails
- 🚀 Support fichiers > 100MB avec multipart
- 🔄 Retry automatique en cas d'échec réseau
- 📊 Barre de progression fiable

**Tâches :**
- [ ] Implémenter DirectUpload API (ActiveStorage)
- [ ] Support multipart pour gros fichiers
- [ ] Retry automatique avec backoff exponentiel
- [ ] Tests avec fichiers 500MB+
- [ ] Documentation configuration S3/GCS

**Estimation :** 5-7 jours

**Priorité après :** Tests + i18n + namespaces

---

#### 1.4 Scan Antivirus

**Objectif :** Protection contre malware avant attachement/persist.

**Options d'implémentation :**

**Option A : ClamAV (open-source, local)**
```ruby
# Gemfile
gem 'clamav-client'

# Configuration
UploadDND.configure do |config|
  config.antivirus_enabled = Rails.env.production?
  config.antivirus_service = :clamav
  config.clamav_host = ENV['CLAMAV_HOST'] || 'localhost'
  config.clamav_port = ENV['CLAMAV_PORT'] || 3310
end

# Callback avant attachement
before_attach do |blob|
  if UploadDND.configuration.antivirus_enabled
    scanner = ClamAV::Client.new
    result = scanner.scan_io(blob.download)
    raise SecurityError, "Virus detected" if result.virus?
  end
end
```

**Option B : VirusTotal API (cloud, payant)**
```ruby
gem 'virustotal'

config.antivirus_service = :virustotal
config.virustotal_api_key = ENV['VIRUSTOTAL_API_KEY']

# Scan asynchrone (pas bloquer l'upload)
ScanFileJob.perform_later(blob.id)
```

**Tâches :**
- [ ] Choisir solution (ClamAV recommandé pour démarrer)
- [ ] Implémenter callback `before_attach`
- [ ] Gérer fichiers infectés (quarantine, notification)
- [ ] Tests avec fichiers EICAR (test virus)
- [ ] Documentation installation ClamAV

**Estimation :** 3-4 jours

**Note :** Peut être fait après v0.2.0 (non bloquant pour publication initiale).

---

### PHASE 2 : Amélioration UX & Sécurité

**Priorité : 🟡 MOYENNE - Améliore expérience utilisateur**

#### 2.1 SweetAlert2 ou alternative moderne

**Problème actuel :**
```javascript
// Confirmation native (UX pauvre)
if (confirm("Supprimer ce fichier ?")) {
  this.deleteFile(fileId)
}
```

**Solution l'app hôte :**
```javascript
// SweetAlert2 (UX riche)
Swal.fire({
  title: 'Supprimer ce fichier ?',
  text: "Cette action est irréversible",
  icon: 'warning',
  showCancelButton: true,
  confirmButtonText: 'Oui, supprimer',
  cancelButtonText: 'Annuler'
}).then((result) => {
  if (result.isConfirmed) {
    this.deleteFile(fileId)
  }
})

// Toast pour feedback
Swal.fire({
  toast: true,
  position: 'top-end',
  icon: 'success',
  title: 'Fichier uploadé avec succès',
  showConfirmButton: false,
  timer: 3000
})
```

**Alternatives :**
- **SweetAlert2** : 33KB minified (complet mais lourd)
- **Toastify.js** : 3KB (léger, juste toast)
- **Native Notification API** : 0KB (mais limité)

**Tâches :**
- [ ] Évaluer options (SweetAlert2 vs Toastify)
- [ ] Intégrer bibliothèque choisie
- [ ] Remplacer tous les `confirm()` natifs
- [ ] Ajouter toasts pour feedback
- [ ] Tests Stimulus avec nouveaux dialogues

**Estimation :** 2-3 jours

---

#### 2.2 Rate Limiting (rack-attack)

**Objectif :** Protection contre flood d'uploads.

**Implémentation :**
```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle("uploads/ip", limit: 10, period: 60) do |req|
  if req.path.start_with?('/upload_d_n_d/') && req.post?
    req.ip
  end
end

# Configuration UploadDND
UploadDND.configure do |config|
  config.rate_limit_enabled = true
  config.max_uploads_per_minute = 10
  config.rate_limit_by = :ip # ou :user_id
end
```

**Stratégies :**
- **Par IP** : 10 uploads/minute/IP
- **Par utilisateur** : 20 uploads/minute/user
- **Par session** : 15 uploads/minute/session

**Tâches :**
- [ ] Ajouter rack-attack en dépendance optionnelle
- [ ] Configuration rate limiting
- [ ] Tests avec flood d'uploads
- [ ] Documentation configuration

**Estimation :** 1-2 jours

---

#### 2.3 Content Security Policy (CSP)

**Objectif :** Sécuriser JavaScript Stimulus contre XSS.

**Configuration :**
```ruby
# config/initializers/content_security_policy.rb
Rails.application.config.content_security_policy do |policy|
  policy.script_src :self, :https

  # Autoriser Stimulus inline scripts avec nonce
  policy.script_src :self, :https, :unsafe_inline if Rails.env.development?

  # Production : utiliser nonce
  if Rails.env.production?
    policy.script_src :self, :https
  end

  # Permettre uploads vers ActiveStorage
  policy.connect_src :self, :https, ENV['ACTIVE_STORAGE_SERVICE_URL']
end
```

**Tâches :**
- [ ] Documenter configuration CSP
- [ ] Tester compatibilité Stimulus + CSP
- [ ] Support nonce pour inline scripts
- [ ] Tests CSP violations

**Estimation :** 1 jour

---

#### 2.4 Filename Sanitization renforcée

**Problème potentiel :**
```ruby
# Attaque path traversal
filename = "../../../etc/passwd"
filename = "../../config/database.yml"
```

**Solution actuelle :**
```ruby
# Déjà implémenté basiquement, à renforcer
def sanitize_filename(filename)
  filename.gsub(/[^0-9A-Za-z.\-_]/, '_')
end
```

**Amélioration :**
```ruby
def sanitize_filename(filename)
  # 1. Supprimer path traversal
  basename = File.basename(filename)

  # 2. Supprimer caractères dangereux
  basename.gsub(/[^0-9A-Za-z.\-_]/, '_')
          .gsub(/\.{2,}/, '.')  # Pas de ".."
          .gsub(/^\./, '')       # Pas de fichier caché
          .slice(0, 255)         # Limite longueur
end
```

**Tâches :**
- [ ] Renforcer sanitization
- [ ] Tests avec filenames malveillants
- [ ] Documenter règles de sanitization

**Estimation :** 0.5 jour

---

### PHASE 3 : Fonctionnalités avancées

**Priorité : 🟣 BASSE - Nice-to-have, non critique**

#### 3.1 Compression / Optimisation d'images

**Fonctionnalités :**
```ruby
uploadable :cover_image,
           content_type: ['image/png', 'image/jpeg'],
           max_size: 5.megabytes,
           optimize: true,  # Nouvelle option
           variants: {
             thumb: { resize_to_limit: [150, 150] },
             medium: { resize_to_limit: [800, 600] },
             large: { resize_to_limit: [1920, 1080] }
           },
           convert_to: :webp  # Conversion automatique
```

**Outils :**
- **ImageMagick** : Inclus avec ActiveStorage
- **libvips** : Plus rapide (nécessite installation)
- **ImageOptim** : Compression lossless

**Estimation :** 3-4 jours

---

#### 3.2 Prévisualisation avancée

**Améliorations :**
- [ ] PDF.js pour preview PDF complet (avec navigation pages)
- [ ] Prévisualisation vidéo avec contrôles
- [ ] Preview fichiers Office via Google Docs Viewer
- [ ] Galerie lightbox pour images multiples

**Estimation :** 2-3 jours

---

#### 3.3 Upload par URL

**Fonctionnalité :**
```ruby
# Télécharger depuis URL externe
attach_from_url(url: "https://example.com/file.pdf")

# Support Google Drive / Dropbox
attach_from_service(service: :google_drive, file_id: "abc123")
```

**Estimation :** 3-4 jours

---

#### 3.4 Watermarking automatique

**Fonctionnalité :**
```ruby
uploadable :product_images,
           watermark: {
             enabled: true,
             text: "© Pierre Cherbero 2026",
             position: :bottom_right,
             opacity: 0.5
           }
```

**Estimation :** 2-3 jours

---

#### 3.5 OCR (Extraction texte)

**Fonctionnalité :**
```ruby
uploadable :invoices,
           content_type: ['application/pdf'],
           ocr: true  # Extraction texte automatique

# Recherche full-text
Invoice.where("extracted_text ILIKE ?", "%facture%")
```

**Outils :**
- **Tesseract** : Open-source OCR
- **Google Vision API** : Cloud OCR (payant)

**Estimation :** 4-5 jours

---

## 🛡️ Checklist Sécurité Production

### Validation & Input

- [x] Validation MIME type (allowlist)
- [x] Anti-spoofing MIME (Marcel magic bytes)
- [x] Sanitisation filename basique
- [ ] Sanitisation filename renforcée (path traversal)
- [x] Validation taille fichier
- [x] Limite nombre de fichiers
- [ ] Validation extension côté serveur (en plus du MIME)

### Autorisation & Session

- [x] Protection CSRF (automatique Rails)
- [x] Authorization Pundit/CanCanCan
- [x] Isolation session (fichiers temporaires)
- [x] Vérification signed_blob_id
- [ ] Vérification propriété fichier stricte
- [ ] Tracking user_id pour audit

### Infrastructure

- [ ] Rate limiting (rack-attack)
- [ ] CSP headers
- [ ] Scan antivirus (ClamAV/VirusTotal)
- [ ] Logging & monitoring complet
- [ ] Alertes comportements suspects

### Stockage

- [x] Nettoyage fichiers temporaires expirés
- [ ] Direct Upload S3/GCS
- [ ] CDN pour assets Stimulus
- [ ] Backup régulier ActiveStorage

---

## 📚 Documentation à créer/enrichir

### Guides utilisateur

- [x] README principal ✅
- [x] GENERATOR_EXAMPLES.md ✅
- [x] AUTHORIZATION.md ✅
- [ ] **PRODUCTION_GUIDE.md** (nouveau)
  - Installation en production
  - Configuration environnement
  - Variables d'environnement
  - Déploiement (Heroku, Render, VPS)

- [ ] **SECURITY_GUIDE.md** (nouveau)
  - Hardening checklist
  - Configuration antivirus
  - Rate limiting
  - CSP headers
  - Audit logging

- [ ] **PERFORMANCE_GUIDE.md** (nouveau)
  - Direct Upload S3/GCS
  - CDN configuration
  - Optimisation images
  - Caching stratégies
  - Monitoring performance

### Guides développeur

- [x] TESTING_STATUS.md ✅
- [ ] **CONTRIBUTING.md** (nouveau)
  - Setup environnement dev
  - Conventions code
  - Process pull request
  - Tests requis

- [ ] **ARCHITECTURE.md** (nouveau)
  - Structure gem (engine)
  - Flow upload temporaire vs persistant
  - Diagrammes séquence
  - Design patterns utilisés

---

## 🎯 Plan d'action recommandé (Priorisation)

### Sprint 1 : Stabilisation (1-2 semaines)

**Objectif :** Rendre le code existant stable et testé.

```
✅ Priorité CRITIQUE
├── Fixer 21 tests échouants (uploadable_spec.rb)
├── Augmenter couverture à 70%+
│   ├── Tests ViewComponent
│   ├── Tests Concern Uploadable
│   ├── Tests Helpers
│   └── Tests Générateurs
└── Commit + push code propre
```

**Livrables :**
- ✅ 210/210 tests passants (0 failure)
- ✅ Couverture > 70%
- ✅ Code review interne

---

### Sprint 2 : Fonctionnalités critiques (2-3 semaines)

**Objectif :** Implémenter features manquantes pour parité l'app hôte.

```
🔴 Priorité HAUTE
├── Support namespaces dans routes
├── Internationalisation (i18n) FR + EN
├── SweetAlert2 (ou alternative UX)
└── Documentation PRODUCTION_GUIDE.md
```

**Livrables :**
- ✅ Multi-namespace fonctionnel
- ✅ Messages FR/EN
- ✅ UX dialogues moderne
- ✅ Guide production

---

### Sprint 3 : Sécurité & Performance (2-3 semaines)

**Objectif :** Hardening sécurité et optimisations.

```
🟡 Priorité MOYENNE
├── Rate limiting (rack-attack)
├── CSP headers
├── Filename sanitization renforcée
├── Direct Upload S3/GCS
└── Documentation SECURITY_GUIDE.md
```

**Livrables :**
- ✅ Rate limiting actif
- ✅ CSP configuré
- ✅ Direct Upload S3
- ✅ Guide sécurité

---

### Sprint 4 : Publication (1 semaine)

**Objectif :** Préparer et publier gem.

```
📦 Publication
├── Audit sécurité final
├── Review documentation complète
├── Tests manuels staging
├── CI/CD GitHub Actions
├── Gemspec final
└── Publication RubyGems.org ou GitHub Packages
```

**Livrables :**
- ✅ Gem publiée (v0.2.0 ou v1.0.0)
- ✅ CI/CD fonctionnel
- ✅ Badge couverture
- ✅ Changelog mis à jour

---

### Sprint 5+ : Features avancées (optionnel)

```
🟣 Priorité BASSE
├── Scan antivirus (ClamAV)
├── Compression images automatique
├── Prévisualisation avancée (PDF.js)
├── Upload par URL
├── Watermarking
└── OCR
```

---

## 📊 Métriques de succès

### Version 0.2.0 (Beta publique)

- ✅ Tests : 210/210 passants (100%)
- ✅ Couverture : > 70%
- ✅ Features : Namespaces + i18n + UX
- ✅ Sécurité : Rate limiting + CSP
- ✅ Documentation : Guides production + sécurité

### Version 1.0.0 (Production stable)

- ✅ Tests : 250+ tests, couverture > 80%
- ✅ Features : Direct Upload S3 + Antivirus
- ✅ Performance : < 100ms moyenne upload
- ✅ Sécurité : Audit complet passé
- ✅ CI/CD : Tests auto + deploy auto
- ✅ Utilisateurs : 10+ projets en production

---

## 🔄 Processus de mise à jour de ce document

Ce document est un **document vivant** qui évolue avec le projet.

### Quand mettre à jour

- ✅ Après chaque sprint (tous les 2-3 semaines)
- ✅ Quand une feature est complétée
- ✅ Quand les priorités changent
- ✅ Après feedback utilisateurs

### Comment mettre à jour

```bash
# 1. Marquer tâches complétées avec ✅
- [x] Fixer tests uploadable_spec.rb ✅

# 2. Mettre à jour métriques
# Tests : 210/210 passants (était 189/210)
# Couverture : 72% (était 25%)

# 3. Ajouter nouvelles tâches si nécessaire
- [ ] Nouvelle feature découverte

# 4. Mettre à jour date en haut du document
# Dernière mise à jour : 2026-01-25

# 5. Commit
git add docs/PRODUCTION_ROADMAP.md
git commit -m "docs: Mise à jour roadmap après sprint 1"
```

---

## 📞 Ressources & Contacts

### Liens utiles

- **Repository** : https://github.com/Peyochanchan/upload_d_n_d
- **Issues** : https://github.com/Peyochanchan/upload_d_n_d/issues
- **Comparaison l'app hôte** : `doc/comparison_app_vs_gem.md`
- **Tests** : `docs/TESTING_STATUS.md`
- **Changelog** : `docs/CHANGELOG.md`

### Stack technique

- **Rails** : 7.2.3+
- **Ruby** : 3.0+
- **ActiveStorage** : Intégré Rails
- **Stimulus** : 3.0+
- **ViewComponent** : 3.0+
- **RSpec** : 3.12+

---

## 🏁 Conclusion

**UploadDND est une gem solide avec un excellent potentiel**, mais nécessite encore du travail avant publication production :

### Forces actuelles ✅
- Architecture propre (Rails Engine)
- Sécurité de base robuste
- Configuration flexible
- Générateurs utiles
- Support multi-namespace (modèles)

### Faiblesses à corriger ⚠️
- 21 tests échouants (bloquant)
- Couverture 25% (insuffisant)
- Pas de support namespace (routes)
- Pas d'i18n (anglais seulement)
- UX basique (confirm() natif)

### Recommandation

**Pour publication publique (RubyGems.org) :**
→ Suivre **Sprint 1-4** complet (8-10 semaines)

**Pour usage interne l'app hôte :**
→ Minimum **Sprint 1-2** (3-5 semaines) + tests staging

---
