class CreateUploadDndTemporaryAttachments < ActiveRecord::Migration[7.2]
  def change
    create_table :upload_d_n_d_temporary_attachments do |t|
      t.string :session_id, null: false
      t.string :attribute_name, null: false
      t.integer :user_id

      t.timestamps
    end

    add_index :upload_d_n_d_temporary_attachments, :session_id
    add_index :upload_d_n_d_temporary_attachments, :user_id
    add_index :upload_d_n_d_temporary_attachments, [ :session_id, :attribute_name ],
              name: "index_temp_attachments_on_session_and_attribute"
  end
end
