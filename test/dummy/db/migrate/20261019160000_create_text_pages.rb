class CreateTextPages < ActiveRecord::Migration[7.2]
  def change
    create_table :text_pages do |t|
      t.text :body
      t.jsonb :payload
      t.timestamps
    end
  end
end
