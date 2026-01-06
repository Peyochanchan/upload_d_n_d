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
    acceptedTypes: String
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
      this.showAlert(
        "Un seul fichier autorisé",
        "Vous ne pouvez uploader qu'un seul fichier pour ce champ.",
        "warning"
      )
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
          this.showAlert("Erreur", "Impossible d'uploader le fichier", "error")
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
      this.showAlert("Trop volumineux", `Max: ${this.maxSizeValue / 1048576}MB`, "error")
      return false
    }

    // Validation fichier vide
    if (file.size === 0) {
      this.showAlert("Fichier vide", "Le fichier ne peut pas être vide", "error")
      return false
    }

    // Validation de l'extension
    const ext = "." + file.name.split('.').pop().toLowerCase()
    if (!this.acceptedTypesValue.includes(ext)) {
      this.showAlert("Format invalide", `Acceptés: ${this.acceptedTypesValue}`, "error")
      return false
    }

    // Validation du MIME type (sécurité supplémentaire)
    // Note: file.type peut être trompé mais c'est une première barrière
    if (file.type && this.hasAcceptedMimeTypesValue) {
      const acceptedMimes = this.getAcceptedMimeTypes(this.acceptedTypesValue)
      if (!acceptedMimes.includes(file.type)) {
        this.showAlert(
          "Type de fichier suspect",
          `Le type réel du fichier ne correspond pas à l'extension`,
          "error"
        )
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
      this.showAlert("Erreur", "Impossible d'attacher le fichier", "error")
      this.element.classList.remove('upload-active')
      this.dropzone?.classList.remove('upload-active')
    })
  }

  async confirmDelete(e) {
    e.preventDefault()
    const url = e.currentTarget.dataset.url
    
    const confirmed = await this.askConfirmation(
      "Supprimer ?",
      "Voulez-vous vraiment retirer ce fichier ?"
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
        this.showAlert("Erreur", "Impossible de supprimer le fichier", "error")
      })
    }
  }

  // --- Helpers UI ---
  showAlert(title, text, icon) {
    // Si SweetAlert2 est disponible, l'utiliser
    if (window.Swal) {
      Swal.fire({ title, text, icon, confirmButtonColor: 'var(--udnd-accent-color)' })
    } else {
      // Utiliser l'alert natif du navigateur
      alert(`${title}\n${text}`)
    }
  }

  async askConfirmation(title, text) {
    // Si SweetAlert2 est disponible, l'utiliser
    if (window.Swal) {
      const result = await Swal.fire({
        title, text, icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#d33',
        confirmButtonText: 'Supprimer',
        cancelButtonText: 'Annuler'
      })
      return result.isConfirmed
    } else {
      // Utiliser le confirm natif du navigateur
      return confirm(`${title}\n${text}`)
    }
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