import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["progressBar"]
  static values = {
    attachUrl: String,
    attributeName: String,
    recordId: String,
    recordGid: String,
    multiple: Boolean,
    maxSize: Number,
    acceptedTypes: String,
    i18n: Object
  }

  connect() {
    this.dropzone = this.element.querySelector('.udnd-dropzone')
  }

  // --- Handlers Drag & Drop ---
  handleDragEnter(e) {
    e.preventDefault()
    this.dropzone.classList.add('dragover')
  }

  handleDragOver(e) {
    e.preventDefault()
    this.dropzone.classList.add('dragover')
  }

  handleDragLeave(e) {
    this.dropzone.classList.remove('dragover')
  }

  handleDrop(e) {
    e.preventDefault()
    this.dropzone.classList.remove('dragover')
    const files = Array.from(e.dataTransfer.files)
    this.processFiles(files)
  }

  previewFiles(e) {
    const files = Array.from(e.target.files)
    this.processFiles(files)
  }

  // --- Logique d'Upload ---
  async processFiles(files) {
    // VALIDATION UX : Si multiple: false, n'accepter qu'un seul fichier
    if (!this.multipleValue && files.length > 1) {
      const msg = this.i18nValue.alerts.singleFileOnly
      this.showAlert(msg.title, msg.text, "warning")
      // Ne traiter que le premier fichier
      files = [files[0]]
    }

    for (const file of files) {
      if (!this.validateFile(file)) continue

      // État UI "upload en cours"
      this.element.classList.add('upload-active')
      this.dropzone?.classList.add('upload-active')
      const upload = new DirectUpload(file, '/rails/active_storage/direct_uploads', this)

      upload.create((error, blob) => {
        if (error) {
          const msg = this.i18nValue.alerts.uploadError
          this.showAlert(msg.title, msg.text, "error")
          this.element.classList.remove('upload-active')
          this.dropzone?.classList.remove('upload-active')
        } else {
          this.attachBlob(blob)
        }
      })
    }
  }

  validateFile(file) {
    // Validation de la taille
    if (file.size > this.maxSizeValue) {
      const msg = this.i18nValue.alerts.fileTooLarge
      const maxSizeMB = this.maxSizeValue / 1048576
      this.showAlert(msg.title, msg.text.replace('%{max_size}', maxSizeMB), "error")
      return false
    }

    // Validation fichier vide
    if (file.size === 0) {
      const msg = this.i18nValue.alerts.emptyFile
      this.showAlert(msg.title, msg.text, "error")
      return false
    }

    // Validation de l'extension
    const ext = "." + file.name.split('.').pop().toLowerCase()
    if (!this.acceptedTypesValue.includes(ext)) {
      const msg = this.i18nValue.alerts.invalidFormat
      this.showAlert(msg.title, msg.text.replace('%{accepted_types}', this.acceptedTypesValue), "error")
      return false
    }

    // Validation du MIME type (sécurité supplémentaire)
    // Note: file.type peut être trompé mais c'est une première barrière
    if (file.type && this.hasAcceptedMimeTypesValue) {
      const acceptedMimes = this.getAcceptedMimeTypes(this.acceptedTypesValue)
      if (!acceptedMimes.includes(file.type)) {
        const msg = this.i18nValue.alerts.suspiciousType
        this.showAlert(msg.title, msg.text, "error")
        return false
      }
    }

    return true
  }

  // Mapping extensions → MIME types communs
  getAcceptedMimeTypes(extensions) {
    const mimeMap = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.csv': 'text/csv',
      '.txt': 'text/plain',
      '.zip': 'application/zip',
      '.mp4': 'video/mp4',
      '.mp3': 'audio/mpeg'
    }

    const exts = extensions.split(',').map(e => e.trim().toLowerCase())
    return exts.flatMap(ext => mimeMap[ext] || [])
  }

  get hasAcceptedMimeTypesValue() {
    return this.acceptedTypesValue && this.acceptedTypesValue.trim().length > 0
  }

  attachBlob(blob) {
    const payload = {
      signed_blob_id: blob.signed_id,
      attribute_name: this.attributeNameValue,
      multiple: this.multipleValue
    }

    // Si on a un record existant, on passe son GlobalID
    if (this.hasRecordGidValue && this.recordGidValue) {
      payload.record_gid = this.recordGidValue
    }

    fetch(this.attachUrlValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify(payload)
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
      return response.text()
    })
    .then(html => {
      Turbo.renderStreamMessage(html)
      this.element.classList.remove('upload-active')
      this.dropzone?.classList.remove('upload-active')
    })
    .catch(error => {
      console.error('Upload failed:', error)
      const msg = this.i18nValue.alerts.attachError
      this.showAlert(msg.title, msg.text, "error")
      this.element.classList.remove('upload-active')
      this.dropzone?.classList.remove('upload-active')
    })
  }

  async confirmDelete(e) {
    e.preventDefault()
    const url = e.currentTarget.dataset.url

    const msg = this.i18nValue.confirms.deleteFile
    const confirmed = await this.askConfirmation(
      msg.title,
      msg.text,
      msg.confirmButton,
      msg.cancelButton
    )

    if (confirmed) {
      fetch(url, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'text/vnd.turbo-stream.html'
        }
      })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        return response.text()
      })
      .then(html => Turbo.renderStreamMessage(html))
      .catch(error => {
        console.error('Delete failed:', error)
        const errorMsg = this.i18nValue.alerts.deleteError
        this.showAlert(errorMsg.title, errorMsg.text, "error")
      })
    }
  }

  // --- Helpers UI ---
  showAlert(title, text, icon) {
    // Utilise le système de modales natif
    this.createModal(title, text, icon, false)
  }

  async askConfirmation(title, text, confirmButtonText, cancelButtonText) {
    // Utilise le système de modales natif pour la confirmation
    return this.createModal(title, text, 'warning', true, confirmButtonText, cancelButtonText)
  }

  // Crée une modale (alert ou confirm) via DOM APIs (pas d'innerHTML)
  createModal(title, message, type, isConfirm, confirmText = "OK", cancelText = "Cancel") {
    return new Promise((resolve) => {
      // Overlay
      const overlay = document.createElement('div')
      overlay.className = 'udnd-modal-overlay'
      overlay.setAttribute('data-action', 'click->upload-d-n-d--uploads#closeModalOnOverlay')
      overlay.setAttribute('role', 'dialog')
      overlay.setAttribute('aria-modal', 'true')

      // Modal
      const modal = document.createElement('div')
      modal.className = 'udnd-modal'
      modal.setAttribute('data-action', 'click->upload-d-n-d--uploads#stopPropagation')

      // Header + icon
      const header = document.createElement('div')
      header.className = 'udnd-modal-header'
      const iconDiv = document.createElement('div')
      iconDiv.className = `udnd-modal-icon udnd-modal-icon--${type}`
      iconDiv.innerHTML = this.getIcon(type) // SVG icons are safe (static content)
      header.appendChild(iconDiv)

      // Body
      const body = document.createElement('div')
      body.className = 'udnd-modal-body'
      const h3 = document.createElement('h3')
      h3.className = 'udnd-modal-title'
      h3.textContent = title
      const p = document.createElement('p')
      p.className = 'udnd-modal-message'
      p.textContent = message
      body.appendChild(h3)
      body.appendChild(p)

      // Footer
      const footer = document.createElement('div')
      footer.className = 'udnd-modal-footer'

      if (isConfirm) {
        const cancelBtn = document.createElement('button')
        cancelBtn.type = 'button'
        cancelBtn.className = 'udnd-modal-button udnd-modal-button--cancel'
        cancelBtn.setAttribute('data-action', 'click->upload-d-n-d--uploads#cancelModal')
        cancelBtn.textContent = cancelText

        const confirmBtn = document.createElement('button')
        confirmBtn.type = 'button'
        confirmBtn.className = 'udnd-modal-button udnd-modal-button--confirm'
        confirmBtn.setAttribute('data-action', 'click->upload-d-n-d--uploads#confirmModal')
        confirmBtn.textContent = confirmText

        footer.appendChild(cancelBtn)
        footer.appendChild(confirmBtn)
      } else {
        const okBtn = document.createElement('button')
        okBtn.type = 'button'
        okBtn.className = 'udnd-modal-button udnd-modal-button--primary'
        okBtn.setAttribute('data-action', 'click->upload-d-n-d--uploads#closeModal')
        okBtn.textContent = confirmText
        footer.appendChild(okBtn)
      }

      modal.appendChild(header)
      modal.appendChild(body)
      modal.appendChild(footer)
      overlay.appendChild(modal)

      const container = document.createElement('div')
      container.appendChild(overlay)
      container._resolveFunction = resolve
      this.currentModalContainer = container

      document.body.appendChild(container)

      // Anime l'ouverture
      requestAnimationFrame(() => {
        overlay.classList.add('udnd-modal-overlay--active')
      })

      // Gestion Escape
      this.modalKeydownHandler = (e) => {
        if (e.key === 'Escape') {
          this.cancelModal()
        }
      }
      document.addEventListener('keydown', this.modalKeydownHandler)
    })
  }

  getIcon(type) {
    const icons = {
      info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>',
      success: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>',
      warning: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',
      error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>'
    }
    return icons[type] || icons.info
  }

  confirmModal() {
    if (this.currentModalContainer?._resolveFunction) {
      this.currentModalContainer._resolveFunction(true)
    }
    this.closeModal()
  }

  cancelModal() {
    if (this.currentModalContainer?._resolveFunction) {
      this.currentModalContainer._resolveFunction(false)
    }
    this.closeModal()
  }

  closeModal() {
    if (!this.currentModalContainer) return

    // Résout la Promise pour les alertes simples
    if (this.currentModalContainer._resolveFunction) {
      this.currentModalContainer._resolveFunction(true)
    }

    const overlay = this.currentModalContainer.querySelector('.udnd-modal-overlay')
    overlay.classList.remove('udnd-modal-overlay--active')

    // Supprime du DOM après l'animation
    setTimeout(() => {
      this.currentModalContainer?.remove()
      this.currentModalContainer = null
    }, 300)

    // Nettoie le listener Escape
    if (this.modalKeydownHandler) {
      document.removeEventListener('keydown', this.modalKeydownHandler)
      this.modalKeydownHandler = null
    }
  }

  closeModalOnOverlay(e) {
    if (e.target.classList.contains('udnd-modal-overlay')) {
      this.cancelModal()
    }
  }

  stopPropagation(e) {
    e.stopPropagation()
  }

  // Callback obligatoire pour DirectUpload (ActiveStorage)
  directUploadWillStoreFileWithXHR(xhr) {
    xhr.upload.addEventListener("progress", event => {
      const progress = (event.loaded / event.total) * 100
      if (this.hasProgressBarTarget) {
        this.progressBarTarget.style.width = `${progress}%`
      }
    })
  }
}