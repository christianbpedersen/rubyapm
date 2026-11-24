# SAML single sign-on settings (one row), edited by admins in the app.
class CreateSsoConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :sso_configs do |t|
      t.boolean :enabled, null: false, default: false
      t.string :button_label, null: false, default: "OneLogin"
      t.string :idp_metadata_url
      t.text :idp_metadata_xml
      t.boolean :auto_provision, null: false, default: false
      t.string :allowed_domains, array: true, null: false, default: []
      t.string :password_login, null: false, default: "everyone"
      t.timestamps
    end

    add_column :users, :last_sign_in_via, :string
  end
end
