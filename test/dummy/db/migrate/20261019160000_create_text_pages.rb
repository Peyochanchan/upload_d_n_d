class CreateTextPages < ActiveRecord::Migration[8.1]
  def change
    create_table :text_pages do |t|
      t.text :body
      t.jsonb :payload
      t.timestamps
    end
  end
end
