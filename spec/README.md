# Tests RSpec pour UploadDND

Ce répertoire contient les tests RSpec pour la gem UploadDND.

## Installation

Avant de lancer les tests, installez les dépendances :

```bash
bundle install
```

## Lancer les tests

### Tous les tests

```bash
bundle exec rspec
```

### Tests spécifiques

```bash
# Un fichier spécifique
bundle exec rspec spec/models/upload_d_n_d/temporary_attachment_spec.rb

# Une ligne spécifique
bundle exec rspec spec/models/upload_d_n_d/temporary_attachment_spec.rb:25

# Tous les tests de modèles
bundle exec rspec spec/models

# Tous les tests de controllers
bundle exec rspec spec/controllers
```

### Avec couverture de code

```bash
COVERAGE=true bundle exec rspec
```

Le rapport de couverture sera généré dans `coverage/index.html`.

## Structure des tests

```
spec/
├── controllers/          # Tests des controllers
│   └── upload_d_n_d/
│       └── attachments_controller_spec.rb
├── models/              # Tests des modèles
│   └── upload_d_n_d/
│       └── temporary_attachment_spec.rb
├── lib/                 # Tests de la configuration et autres lib
│   └── upload_d_n_d/
│       └── configuration_spec.rb
├── factories/           # Factories FactoryBot
│   └── temporary_attachments.rb
├── support/             # Helpers et configuration de test
│   └── active_storage.rb
├── spec_helper.rb       # Configuration RSpec de base
└── rails_helper.rb      # Configuration RSpec pour Rails
```

## Écrire de nouveaux tests

### Modèles

```ruby
# spec/models/my_model_spec.rb
require 'rails_helper'

RSpec.describe MyModel, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
  end

  describe 'associations' do
    it { should have_many(:items) }
  end
end
```

### Controllers

```ruby
# spec/controllers/my_controller_spec.rb
require 'rails_helper'

RSpec.describe MyController, type: :controller do
  routes { UploadDND::Engine.routes }

  describe 'GET #index' do
    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end
  end
end
```

### Factories

```ruby
# spec/factories/my_model.rb
FactoryBot.define do
  factory :my_model do
    name { Faker::Name.name }
    email { Faker::Internet.email }
  end
end
```

## Outils utilisés

- **RSpec Rails** : Framework de test pour Rails
- **FactoryBot** : Création de fixtures
- **Faker** : Génération de données aléatoires
- **Shoulda Matchers** : Matchers pour tests de modèles
- **Database Cleaner** : Nettoyage de la base de données entre tests
- **SimpleCov** : Couverture de code

## CI/CD

Les tests peuvent être intégrés dans votre pipeline CI/CD :

```yaml
# .github/workflows/test.yml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - uses: ruby/setup-ruby@v1
      with:
        bundler-cache: true
    - run: bundle exec rspec
```
