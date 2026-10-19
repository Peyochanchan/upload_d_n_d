class CreateDemoProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :demo_projects do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
