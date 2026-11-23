class CreateShop < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.timestamps
    end
    create_table :products do |t|
      t.references :category, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false
      t.integer :stock, null: false, default: 0
      t.string :sku, null: false
      t.timestamps
    end
    create_table :customers do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :country
      t.timestamps
    end
    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :total_cents, null: false, default: 0
      t.string :payment_ref
      t.timestamps
    end
    create_table :line_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.integer :price_cents, null: false
      t.timestamps
    end
    create_table :reviews do |t|
      t.references :product, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.integer :rating, null: false
      t.text :body
      t.timestamps
    end
    # Deliberately unindexed beyond the primary key: the analytics queries
    # against it are the sample's slow, sequentially scanned statements.
    create_table :page_views do |t|
      t.bigint :product_id
      t.bigint :customer_id
      t.string :path
      t.string :referrer
      t.string :country
      t.integer :duration_ms
      t.datetime :viewed_at
    end
  end
end
