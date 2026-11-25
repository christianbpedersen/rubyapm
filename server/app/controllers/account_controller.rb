# The signed-in user's own page: profile, password, API tokens for MCP
# clients, connected OAuth apps and signed-in browsers.
class AccountController < ApplicationController
  def show
    load_lists
  end

  def update
    # Email is the identity SSO matches on, so only admins change it.
    fields = current_user.admin? ? %i[name email] : %i[name]
    if current_user.update(params.expect(user: fields))
      redirect_to account_path, notice: "Profile saved."
    else
      load_lists
      render :show, status: :unprocessable_entity
    end
  end

  def password
    user = current_user
    if !user.authenticate(params[:current_password].to_s)
      user.errors.add(:current_password, "is wrong")
    elsif params[:password].blank?
      user.errors.add(:password, "can't be blank")
    else
      user.assign_attributes(password: params[:password], password_confirmation: params[:password_confirmation])
      if user.save
        user.sessions.where.not(id: current_session.id).delete_all
        user.api_tokens.delete_all
        return redirect_to account_path, notice: "Password changed. Other browsers were signed out and API tokens and connected apps revoked."
      end
    end
    load_lists
    render :show, status: :unprocessable_entity
  end

  def sign_out_others
    current_user.sessions.where.not(id: current_session.id).delete_all
    redirect_to account_path, notice: "Signed out of all other browsers."
  end

  private

  def load_lists
    @tokens = current_user.api_tokens.personal.order(created_at: :desc)
    @connections = OauthClient.joins(:api_tokens).merge(ApiToken.live.where(user: current_user, kind: "refresh"))
                              .group("oauth_clients.id").select("oauth_clients.*, max(api_tokens.created_at) AS connected_at")
    @sessions = current_user.sessions.active.order(last_seen_at: :desc)
  end
end
