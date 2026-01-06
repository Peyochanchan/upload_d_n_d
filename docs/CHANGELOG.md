# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-05

Première version stable de UploadDND, un système de drag & drop sécurisé pour Rails.

### Added

#### Fonctionnalités principales
- Interface drag & drop intuitive avec barre de progression
- Support multi-fichiers (has_one_attached et has_many_attached)
- Upload temporaire pour les formulaires de création (avant persistance du modèle)
- Prévisualisation des fichiers (images et PDF) côté client

#### Validation et sécurité
- Validation sécurisée côté serveur (MIME type, taille, nombre de fichiers)
- Protection contre le spoofing de fichiers via détection MIME avec Marcel
- Protection CSRF automatique
- Isolation des fichiers temporaires par session
- Sanitization des noms de fichiers
- Vérification des signatures de blob

#### Autorisation
- Support flexible d'autorisation (Pundit, CanCanCan, ou custom)
- Générateur de politique Pundit
- Concern `UploadDND::Controllers::UploadAuthorization` pour les contrôleurs

#### Configuration
- Configuration globale et par composant
- Module `MimeTypeHelper` avec support de 40+ extensions (images, documents, audio, vidéo, archives)
- Conversion automatique des extensions de fichiers en MIME types (ex: `jpg` → `image/jpeg`)
- Styles CSS personnalisables avec variables CSS
- Callbacks personnalisables (on_upload_success, on_upload_error)

#### Intégration Rails
- Compatible Rails 7 et 8
- Concern `UploadDND::Uploadable` pour les modèles
- Concern `UploadDND::Controllers::Uploadable` pour les contrôleurs
- Helper `upload_field` pour les vues
- Contrôleur Stimulus pour le drag & drop
- Modèle TemporaryAttachment pour les uploads temporaires
- Support automatique de Stimulus et des assets

#### Générateurs
- Générateur d'installation avec configuration automatique
  - Installation des dépendances (view_component, stimulus-rails)
  - Migration pour les fichiers temporaires
  - Copie des concerns, helpers et contrôleurs Stimulus
  - Styles CSS (compatible Tailwind et Asset Pipeline)
  - Configuration initiale
- Générateur de modèle
  - Support des namespaces (Admin::Article, Manager::Report, etc.)
  - Options configurables (--multiple, --content_type, --max_size, --max_files)
  - Génération optionnelle de controller et vues
  - Détection intelligente des attributs uploadables existants

#### Documentation
- README complet avec exemples
- Guide d'autorisation détaillé
- Exemples de générateurs
- Documentation de test

### Security
- Validation des paramètres pour empêcher l'injection
- Protection CSRF automatique
- Isolation des fichiers temporaires par session
- Vérification des signatures de blob
- Détection de spoofing MIME avec Marcel
- Sanitization des noms de fichiers
- Vérification de propriété des fichiers avant suppression
