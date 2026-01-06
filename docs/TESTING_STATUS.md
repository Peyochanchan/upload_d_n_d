# État des tests UploadDND

## 📊 Résumé actuel

```bash
bundle exec rspec
# 80 exemples total
# 0 failure
# Couverture (SimpleCov): ~20% (varie selon l'ordre/seed)
```

## ✅ Tests fonctionnels (passent)

### 1. Tests de configuration (`spec/lib/upload_d_n_d/configuration_spec.rb`)
- ✅ 16 exemples, 0 échecs
- Configuration par défaut
- Configuration personnalisée
- Callbacks (on_upload_success, on_upload_error)
- Reset de configuration

### 2. Tests multi-namespaces (`spec/integration/multi_namespace_spec.rb`)
- ✅ 14 exemples, 0 échecs
- GlobalID avec `User` (sans namespace)
- GlobalID avec `Admin::Article`
- GlobalID avec `Manager::Report`
- ViewComponent avec différents namespaces
- Récupération de records via GlobalID

## ⚠️ Tests qui nécessitent des ajustements

✅ Plus d'échecs sur la suite actuelle.

## 📋 Tests manquants à créer

### Tests de composants

1. **ViewComponent (`spec/components/upload_d_n_d/upload_component_spec.rb`)**
   - Rendu du composant
   - Génération des attributs data pour Stimulus
   - Gestion des records existants vs temporaires
   - Multiple vs single upload

2. **Concern Uploadable (`spec/models/concerns/uploadable_spec.rb`)**
   - Inclusion du concern
   - Méthode `uploadable`
   - Callback `attach_temporary_uploads`
   - Gestion du `temp_upload_session_id`

3. **Helpers (`spec/helpers/upload_d_n_d/upload_helper_spec.rb`)**
   - Méthode `upload_field`
   - Méthode `file_icon_class`
   - Méthode `file_type_badge_class`

### Tests de générateurs

4. **Générateur d'installation (`spec/generators/install_generator_spec.rb`)**
   - Génération de l'initializer
   - Copie des concerns
   - Installation de ViewComponent
   - Création de la migration

5. **Générateur de modèle (`spec/generators/model_generator_spec.rb`)**
   - Modification du modèle
   - Génération du controller
   - Génération des vues
   - Support des namespaces
   - Options (--multiple, --content_type, etc.)

## 🎯 Plan d'action recommandé

### Phase 1: Ajouter tests critiques (Priorité haute)

```bash
# 1. Tests du ViewComponent
# - Rendu de base
# - Attributs Stimulus

# 2. Tests du concern Uploadable
# - Fonctionnalité principale de la gem
```

### Phase 2: Tests complémentaires (Priorité moyenne)

```bash
# 3. Tests des helpers
# 4. Tests des générateurs
```

## 🔧 Problèmes techniques identifiés

### ActiveStorage en test

Le problème principal est la configuration d'ActiveStorage dans l'environnement de test:

```ruby
# Dans spec/support/active_storage.rb ou spec/rails_helper.rb
ActiveStorage::Blob.service = ActiveStorage::Service.configure(
  :test,
  test: { service: "Disk", root: Rails.root.join("tmp/storage") }
)
```

### Factories avec has_one_attached

```ruby
# La factory actuelle utilise after(:create) mais a des problèmes
# Il faut s'assurer que:
# 1. La table upload_dnd_temporary_attachments existe
# 2. Les tables ActiveStorage existent
# 3. Le service ActiveStorage est configuré
```

## 📈 Objectif de couverture

- **Actuel**: 16.6%
- **Court terme** (tests existants corrigés): ~40%
- **Moyen terme** (+ ViewComponent + Uploadable): ~65%
- **Long terme** (tests complets): ~85%

## 🚀 Commandes utiles

```bash
# Lancer tous les tests
bundle exec rspec

# Lancer un fichier spécifique
bundle exec rspec spec/lib/upload_d_n_d/configuration_spec.rb

# Avec couverture
COVERAGE=true bundle exec rspec

# Voir le rapport de couverture
open coverage/index.html

# Tests qui passent actuellement
bundle exec rspec spec/lib spec/integration
```

## ✍️ Notes

- Les tests d'intégration multi-namespaces sont excellents et passent tous ✅
- Les tests de configuration sont complets ✅
- Le focus doit être mis sur la correction des tests du modèle et du controller
- Les générateurs fonctionnent mais n'ont pas de tests automatisés
