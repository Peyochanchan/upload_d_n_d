import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    filename: String,
    contentType: String
  }

  disconnect() {
    this.close()
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
    if (this.modal) this.close()

    this.previousFocus = document.activeElement
    this.modal = this.createModal(filename)

    const content = this.modal.querySelector('.udnd-preview-body')
    content.appendChild(this.buildContent(url, filename, contentType))

    document.body.appendChild(this.modal)
    document.body.style.overflow = 'hidden'

    // Gestion clavier (Escape + focus trap) et fermeture sur navigation Turbo
    this.keydownHandler = (e) => this.handleKeydown(e)
    this.beforeVisitHandler = () => this.close()
    document.addEventListener('keydown', this.keydownHandler)
    document.addEventListener('turbo:before-visit', this.beforeVisitHandler)

    this.modal.querySelector('.udnd-preview-close').focus()

    // Animation d'entrée
    requestAnimationFrame(() => this.modal.classList.add('show'))
  }

  // Contenu de la modale selon le type de fichier (DOM APIs, jamais d'innerHTML
  // avec des données utilisateur : filename est contrôlé par l'uploadeur)
  buildContent(url, filename, contentType) {
    if (this.isImage(contentType)) {
      const img = document.createElement('img')
      img.className = 'udnd-preview-image'
      img.setAttribute('src', url)
      img.setAttribute('alt', filename)
      return img
    }

    if (this.isPDF(contentType)) {
      // <object> plutôt qu'<iframe> : fallback natif quand le navigateur
      // ne sait pas afficher le PDF (Safari mobile notamment)
      const object = document.createElement('object')
      object.className = 'udnd-preview-pdf'
      object.setAttribute('type', 'application/pdf')
      object.setAttribute('data', url)
      object.appendChild(this.buildUnsupported(url, filename))
      return object
    }

    return this.buildUnsupported(url, filename)
  }

  buildUnsupported(url, filename) {
    const wrapper = document.createElement('div')
    wrapper.className = 'udnd-preview-unsupported'

    const icon = document.createElement('span')
    icon.innerHTML = this.fileIcon() // SVG statique, sans donnée utilisateur
    wrapper.appendChild(icon.firstElementChild)

    const message = document.createElement('p')
    message.textContent = 'Aperçu non disponible pour ce type de fichier'
    wrapper.appendChild(message)

    const link = document.createElement('a')
    link.className = 'udnd-btn-download'
    link.setAttribute('href', url)
    link.setAttribute('download', filename)
    link.textContent = 'Télécharger le fichier'
    wrapper.appendChild(link)

    return wrapper
  }

  // Créer la structure HTML de la modale (DOM APIs)
  createModal(filename) {
    const modal = document.createElement('div')
    modal.className = 'udnd-preview-modal'

    const overlay = document.createElement('div')
    overlay.className = 'udnd-preview-overlay'
    overlay.addEventListener('click', () => this.close())
    modal.appendChild(overlay)

    const container = document.createElement('div')
    container.className = 'udnd-preview-container'
    container.setAttribute('role', 'dialog')
    container.setAttribute('aria-modal', 'true')
    container.setAttribute('aria-labelledby', 'udnd-preview-title')

    const header = document.createElement('div')
    header.className = 'udnd-preview-header'

    const title = document.createElement('h3')
    title.className = 'udnd-preview-title'
    title.id = 'udnd-preview-title'
    title.textContent = filename
    header.appendChild(title)

    const closeButton = document.createElement('button')
    closeButton.type = 'button'
    closeButton.className = 'udnd-preview-close'
    closeButton.setAttribute('aria-label', 'Fermer')
    closeButton.innerHTML = this.closeIcon() // SVG statique, sans donnée utilisateur
    closeButton.addEventListener('click', () => this.close())
    header.appendChild(closeButton)

    const body = document.createElement('div')
    body.className = 'udnd-preview-body'

    container.appendChild(header)
    container.appendChild(body)
    modal.appendChild(container)

    return modal
  }

  // Fermer la modale
  close() {
    if (!this.modal) return

    const modal = this.modal
    this.modal = null

    document.removeEventListener('keydown', this.keydownHandler)
    document.removeEventListener('turbo:before-visit', this.beforeVisitHandler)

    modal.classList.remove('show')
    setTimeout(() => {
      modal.remove()
      document.body.style.overflow = ''
    }, 300)

    if (this.previousFocus && document.contains(this.previousFocus)) {
      this.previousFocus.focus()
    }
    this.previousFocus = null
  }

  // Escape ferme la modale, Tab reste piégé dedans
  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.close()
      return
    }

    if (event.key === 'Tab' && this.modal) {
      const focusables = this.modal.querySelectorAll('button, a[href], object')
      if (focusables.length === 0) return

      const first = focusables[0]
      const last = focusables[focusables.length - 1]

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
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

  // SVG statiques (contenu fixe, aucune interpolation)
  fileIcon() {
    return '<svg class="udnd-icon udnd-icon-xl" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/></svg>'
  }

  closeIcon() {
    return '<svg class="udnd-icon" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>'
  }
}
