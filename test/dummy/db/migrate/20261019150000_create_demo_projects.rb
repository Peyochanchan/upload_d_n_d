class CreateDemoProjects < ActiveRecord::Migration[7.2]
  def change
    create_table :demo_projects do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
