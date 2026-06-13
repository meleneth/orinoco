class CreateDioramaGraph < ActiveRecord::Migration[8.1]
  def change
    create_table :dioramas, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :version, null: false, default: "0.1.0"
      t.text :description
      t.string :visibility, null: false, default: "private"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :dioramas, :slug, unique: true

    create_table :diorama_nodes, id: :uuid do |t|
      t.references :diorama, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :slug, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.text :description
      t.jsonb :data, null: false, default: {}
      t.jsonb :validation_state, null: false, default: {}

      t.timestamps
    end

    add_index :diorama_nodes, [ :diorama_id, :slug ], unique: true
    add_index :diorama_nodes, [ :diorama_id, :kind ]
    add_index :diorama_nodes, :data, using: :gin

    create_table :diorama_edges, id: :uuid do |t|
      t.references :diorama, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :from_node,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :diorama_nodes, on_delete: :cascade }
      t.references :to_node,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :diorama_nodes, on_delete: :cascade }
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :diorama_edges,
              [ :diorama_id, :from_node_id, :to_node_id, :kind ],
              unique: true,
              name: "idx_diorama_edges_unique_diorama_from_to_kind"
    add_index :diorama_edges, [ :diorama_id, :from_node_id ]
    add_index :diorama_edges, [ :diorama_id, :to_node_id ]
    add_index :diorama_edges, [ :diorama_id, :kind ]
  end
end
