class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to login_path, alert: "Too many sign-in attempts. Try again in a few minutes." }
  layout "auth"

  def new
    redirect_to root_path if signed_in?
  end

  def create
    if (user = User.authenticate(params[:email], params[:password]))
      target = after_login_url # read before start_session resets the Rails session
      start_session(user)
      redirect_to target
    else
      flash.now[:alert] = "That email and password don't match an account."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    end_session
    redirect_to login_path, notice: "Signed out."
  end
end
