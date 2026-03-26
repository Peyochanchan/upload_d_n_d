import UploadsController from "./controllers/uploads_controller.js"
import PreviewController from "./controllers/preview_controller.js"

// Export nommés pour usage manuel
export { UploadsController, PreviewController }

// Auto-enregistrement des controllers Stimulus
// L'app hôte doit juste ajouter : import "upload_d_n_d"
const application = window.Stimulus
if (application) {
  application.register("upload-d-n-d--uploads", UploadsController)
  application.register("upload-d-n-d--preview", PreviewController)
}
