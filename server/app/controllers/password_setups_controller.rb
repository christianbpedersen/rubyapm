# The page behind a setup link: new users choose their first password here,
# and the same kind of link resets a forgotten one. Links expire after three
# days and stop working once a password is set.
class PasswordSetupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 10.minutes, only: :update
  layout "auth"

  before_action :load_user

  def edit; end

  def update
    if params[:password].blank?
      @user.errors.add(:password, "can't be blank")
    else
      @user.assign_attributes(password: params[:password], password_confirmation: params[:password_confirmation])
      if @user.save
        @user.sessions.delete_all # a new password signs out everywhere else
        @user.api_tokens.where(kind: %w[access refresh]).delete_all
        start_session(@user)
        return redirect_to root_path, notice: "Password set. Welcome, #{@user.display_name}."
      end
    end
    render :edit, status: :unprocessable_entity
  end

  private

  def load_user
    @user = User.find_by_token_for(:password_setup, params[:token])
    render :invalid, status: :not_found unless @user
  end
end
