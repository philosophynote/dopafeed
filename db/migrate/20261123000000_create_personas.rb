class CreatePersonas < ActiveRecord::Migration[8.1]
  # 後でモデルに検証や列が増えても、この migration が古い前提で落ちないよう、モデルを使わない
  class InitialPersona < ActiveRecord::Base
    self.table_name = "personas"
  end

  def up
    create_table :personas do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :title, null: false
      t.string :color, null: false
      t.string :description, null: false
      t.text :system_prompt, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :personas, :slug, unique: true

    insert_initial_personas
  end

  def down
    drop_table :personas
  end

  private

  # 本番の人物をデプロイだけで揃えるため、ここで一度だけ入れる。入れた後の書き換えを戻さないよう、空のときだけ
  def insert_initial_personas
    InitialPersona.reset_column_information
    return if InitialPersona.exists?

    now = Time.current
    rows = YAML.load_file(Rails.root.join("db/seeds/personas.yml")).fetch("personas").each_with_index.map do |attrs, index|
      attrs.slice("slug", "name", "title", "color", "description", "system_prompt").merge("position" => index, "created_at" => now, "updated_at" => now)
    end
    InitialPersona.insert_all!(rows)
  end
end
