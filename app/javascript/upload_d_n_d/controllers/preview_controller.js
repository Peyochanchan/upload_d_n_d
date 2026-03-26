import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "title"]
  static values = {
    url: String,
    filename: String,
    contentType: String
  }

  // Ouvrir la modale avec prévisualisation
  open(event) {
    event.preventDefault()

    const url = event.currentTarget.dataset.previewUrl
    const filename = event.currentTarget.dataset.previewFilename
    const contentType = event.currentTarget.dataset.previewContentType

    this.showPreview(url, filename, contentType)
  }

  // Afficher la prévisualisation selon le type de fichier
  showPreview(url, filename, contentType) {
    const modal = this.createModal()

    // Titre
    const title = modal.querySelector('[data-preview-target="title"]')
    title.textContent = filename

    // Contenu selon le type
    const content = modal.querySelector('[data-preview-target="content"]')

    if (this.isImage(contentType)) {
      content.innerHTML = `
        <img src="${url}"
             alt="${filename}"
             class="udnd-preview-image"
             style="max-width: 100%; max-height: 80vh; object-fit: cover;">
      `
    } else if (this.isPDF(contentType)) {
      content.innerHTML = `
        <iframe src="${url}"
                class="udnd-preview-pdf"
                style="width: 100%; height: 80vh; border: none;">
        </iframe>
      `
    } else {
      content.innerHTML = `
        <div class="udnd-preview-unsupported">
          <svg class="udnd-icon udnd-icon-xl" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/></svg>
          <p>Aperçu non disponible pour ce type de fichier</p>
          <a href="${url}"
             download="${filename}"
             class="udnd-btn-download">
            Télécharger le fichier
          </a>
        </div>
      `
    }

    // Afficher la modale
    document.body.appendChild(modal)
    document.body.style.overflow = 'hidden'

    // Animation d'entrée
    setTimeout(() => modal.classList.add('show'), 10)
  }

  // Créer la structure HTML de la modale
  createModal() {
    const modal = document.createElement('div')
    modal.className = 'udnd-preview-modal'
    modal.dataset.controller = 'upload-d-n-d--preview'
    modal.dataset.action = 'keydown@window->upload-d-n-d--preview#handleKeydown'

    modal.innerHTML = `
      <div class="udnd-preview-overlay" data-action="click->upload-d-n-d--preview#close"></div>
      <div class="udnd-preview-container">
        <div class="udnd-preview-header">
          <h3 data-preview-target="title" class="udnd-preview-title"></h3>
          <button type="button"
                  class="udnd-preview-close"
                  data-action="click->upload-d-n-d--preview#close"
                  aria-label="Fermer">
            <svg class="udnd-icon" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
          </button>
        </div>
        <div class="udnd-preview-body" data-preview-target="content"></div>
      </div>
    `

    return modal
  }

  // Fermer la modale
  close() {
    const modal = document.querySelector('.udnd-preview-modal')
    if (modal) {
      modal.classList.remove('show')
      setTimeout(() => {
        modal.remove()
        document.body.style.overflow = ''
      }, 300)
    }
  }

  // Gérer la touche Escape
  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  // Helpers de détection de type
  isImage(contentType) {
    return contentType && (
      contentType.startsWith('image/jpeg') ||
      contentType.startsWith('image/jpg') ||
      contentType.startsWith('image/png') ||
      contentType.startsWith('image/webp') ||
      contentType.startsWith('image/gif')
    )
  }

  isPDF(contentType) {
    return contentType && contentType.includes('pdf')
  }
}
