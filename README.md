# UploadDND

[![CI](https://github.com/Peyochanchan/upload_d_n_d/actions/workflows/ci.yml/badge.svg)](https://github.com/Peyochanchan/upload_d_n_d/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](MIT-LICENSE)
![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-red)
![Rails](https://img.shields.io/badge/rails-7.2%20%7C%208.0%20%7C%208.1-red)

🇫🇷 [Version française](README.fr.md)

Secure drag & drop file uploads for Rails, built on ActiveStorage, Stimulus and ViewComponent.

One line in a view gives you a drop zone with progress, previews and removal — while every file is checked server-side against the limits declared on the model, and every request goes through your authorization layer, fail-closed.

```erb
<%= upload_field :documents, record: @project %>
```

## Why

ActiveStorage handles storage; it does not handle the hard parts of a production upload flow:

- **Trusting the browser.** `accept` attributes and JS size checks are UX, not security. UploadDND re-applies the model's limits on the server as soon as the file lands, and optionally sniffs the real content type (Marcel) to catch spoofed extensions.
- **Uploading before the record exists.** Creation forms need files before `save`. Temporary uploads are scoped to the session, survive a page reload, and are re-validated when wired to the record.
- **Authorization gaps.** Upload endpoints are easy to leave open. Here every upload and deletion goes through Pundit or CanCanCan; with no usable adapter, everything is refused (403). Disabling it (`:none`) is explicit and reported at boot.
- **Storage garbage.** DirectUpload puts the file in your bucket before anyone validates it. Rejected blobs are purged in the background, and an opt-in job removes orphan blobs — without touching files still referenced in stored HTML.

## Features

- Drag & drop with progress bar, image and PDF previews
- `has_one_attached` and `has_many_attached`, with `max_files`
- Server-side validation: allowlisted MIME types, size, count, optional anti-spoofing
- Temporary uploads for creation forms, persisted across reloads
- Fail-closed authorization (Pundit, CanCanCan, or explicit opt-out)
- One file, one owner: an already-attached `signed_id` can't be re-attached elsewhere
- Rate limiting on the engine endpoints
- Cleanup jobs for expired temporary files, rejected and orphan blobs
- Works in any namespace (`Admin::`, `Manager::`…), no routes required in the host app
- Generators for install, models and Pundit policies
- I18n (EN/FR) server messages

## Installation

```ruby
# Gemfile
gem "upload_d_n_d", github: "Peyochanchan/upload_d_n_d"
```

```bash
bundle install
bin/rails generate upload_d_n_d:install
bin/rails db:migrate
```

The installer adds `view_component` and `stimulus-rails` if missing, creates the temporary uploads migration, mounts the engine, writes the initializer and, if Pundit is present, the policies.

Everything else (JS, CSS, components, concerns) is served from the gem: upgrading is a `bundle update`.

With **jsbundling-rails** (bun/esbuild), the `upload_d_n_d:link_js` task copies the gem's JS/CSS into `node_modules/upload_d_n_d` so your bundler can resolve `import "upload_d_n_d"` and `@import "upload_d_n_d/styles"`. It is a real directory (not a symlink), so the gem's own imports of `@hotwired/stimulus` and `@rails/activestorage` resolve against your app's `node_modules`. The task runs automatically on `javascript:build` (so `assets:precompile` at deploy is always up to date). Note: a watch-mode dev server such as `bin/dev` calls the bundler directly and does **not** run the task, so after upgrading the gem run `bin/rails javascript:build` once locally to refresh the copy.

CSS — one line, whichever bundler:

```css
/* Tailwind 3 (postcss-import), esbuild or bun */
@import "upload_d_n_d/styles";
```

With **Sprockets** (asset pipeline) instead of a JS bundler, use the stylesheet tag:

```erb
<%= stylesheet_link_tag "upload_d_n_d/application", media: "all" %>
```

ActiveStorage must be installed (`bin/rails active_storage:install`). With an external S3-like bucket and a strict CSP, serve files same-origin:

```ruby
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

## Usage

### Declare the field on the model

```ruby
class Project < ApplicationRecord
  include UploadDND::Uploadable

  uploadable :cover,                   # declares has_one_attached
             accept: [:jpg, :png, :webp],
             max_size: 5.megabytes,
             strict_mime_check: true

  uploadable :documents,               # declares has_many_attached
             accept: [:pdf, :docx],
             max_size: 20.megabytes,
             multiple: true,
             max_files: 10
end
```

The model is the source of truth: the same limits drive the browser checks and the server checks. Options passed to the view helper can only narrow them.

`strict_mime_check: true` sniffs the file's real bytes (Marcel) to catch a spoofed extension. It works both ways: with the gem's dropzone (DirectUpload — the content is read back from storage, where the file already sits) and with a plain Rails `file_field` (the file rides along with the form — the content is read from the pending upload, before it reaches storage). Either way the check runs during model validation, so a spoofed file is never persisted.

Or let the generator print the snippets for you:

```bash
bin/rails g upload_d_n_d:model Project --attribute=documents --multiple --content_type=pdf docx --max_size=20
```

### Use it in a form

```erb
<%= form_with model: @project do |f| %>
  <%= upload_session_field %>   <%# only needed for new records %>

  <%= f.text_field :name %>
  <%= upload_field :cover, record: @project %>
  <%= upload_field :documents, record: @project %>

  <%= f.submit %>
<% end %>
```

For a new record, files are stored temporarily and attached on save:

```ruby
class ProjectsController < ApplicationController
  include UploadDND::Controllers::Uploadable

  def create
    @project = Project.new(project_params)
    wire_temporary_uploads(@project) # checks the session, re-validates each file

    if @project.save
      redirect_to @project
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

### Authorize

```ruby
# Pundit — uploads and deletions on a record require update?
class ProjectPolicy < ApplicationPolicy
  def update?
    record.members.include?(user)
  end
end
```

```ruby
# CanCanCan
can :create, :upload_d_n_d_attachment
can [:create, :destroy], :upload_d_n_d_temporary_attachment
can :update, Project, members: { id: user.id }
```

`bin/rails g upload_d_n_d:policy` generates the gem's generic Pundit policies. The full rule matrix is in [docs/AUTHORIZATION.md](docs/AUTHORIZATION.md).

## Security model

| Layer | What it does |
|---|---|
| Content-type allowlist | Only declared types are accepted |
| Anti-spoofing | `strict_mime_check: true` inspects the actual bytes |
| Server-side limits | Size, type and count enforced on upload, again when temporary files are wired |
| Fail-closed authorization | No adapter → 403; `:none` must be explicit |
| Session isolation | Temporary files only visible to the session that uploaded them |
| Ownership | An attached blob can't be claimed by another record |
| Rate limiting | Per user + IP on the engine endpoints (`Rails.cache` backed) |
| Rejected blob purge | Background purge, never for attached blobs or unauthorized requests |

ActiveStorage's own `POST /rails/active_storage/direct_uploads` belongs to your app, not the gem: throttle it too, for example with [rack-attack](https://github.com/rack/rack-attack).

## Maintenance jobs

```yaml
# config/recurring.yml (solid_queue)
production:
  cleanup_temporary_uploads:
    class: UploadDND::CleanupTemporaryAttachmentsJob
    schedule: every day at 2am
  purge_orphan_blobs:
    class: UploadDND::PurgeOrphanBlobsJob
    args: [{ "apply": true }]
    schedule: every sunday at 3am
```

The orphan purge is opt-in and conservative: a blob is removed only if it has no attachment, is older than `orphan_blob_min_age`, and isn't referenced anywhere in the database's text and JSON columns (bucket key, `signed_id` or Action Text sgid). Dry-run first:

```bash
bin/rails upload_d_n_d:purge_orphans           # report only
APPLY=1 bin/rails upload_d_n_d:purge_orphans   # delete
```

PostgreSQL is required for the reference scan; on other databases the job raises instead of deleting blindly.

## Configuration

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  config.max_size = 10.megabytes
  config.accepted_types = ".pdf,.jpg,.jpeg,.png"
  config.main_color = "#E97451"
  config.temporary_files_retention = 7 # days

  # :pundit / :cancancan are auto-detected; :none disables authorization
  # config.authorization_adapter = :pundit

  config.rate_limit_enabled = true
  config.rate_limit_max_requests = 30 # one request per file
  config.rate_limit_period = 60

  config.on_upload_success = ->(blob, user) { AuditLog.record(:upload, blob, user) }
  config.on_file_removed = ->(record, attribute_name, user) { AuditLog.record(:removal, record, user) }
end
```

The French README covers every option in detail: nested and singular resources, custom delete routes, cancelling temporary uploads, styling.

## Development

```bash
bundle install
bundle exec rspec
bin/rubocop
```

The suite runs against a dummy app on PostgreSQL. CI runs RuboCop and the spec suite.

## Docs

- [Authorization](docs/AUTHORIZATION.md)
- [Generator examples](docs/GENERATOR_EXAMPLES.md)
- [Migrating to 0.5](docs/MIGRATION_0.5.md)
- [Changelog](docs/CHANGELOG.md)

## License

Released under the [MIT License](MIT-LICENSE).
