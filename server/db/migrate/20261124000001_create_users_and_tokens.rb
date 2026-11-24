# Dashboard users and their browser sessions, personal API tokens, and the
# OAuth 2.1 server that lets MCP clients (claude.ai, Claude Code) connect.
class CreateUsersAndTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.string :password_digest
      t.string :role, null: false, default: "member"
      t.datetime :last_sign_in_at
      t.timestamps
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    create_table :oauth_clients do |t|
      t.string :client_id, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :redirect_uris, array: true, null: false, default: []
      t.timestamps
    end

    # Personal tokens, OAuth access tokens and OAuth refresh tokens. Only a
    # SHA-256 of each token is stored.
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_client, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :name
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at
      t.datetime :last_used_at
      t.timestamps
    end

    create_table :oauth_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_client, null: false, foreign_key: { on_delete: :cascade }
      t.string :code_digest, null: false, index: { unique: true }
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :resource
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
  end
end
