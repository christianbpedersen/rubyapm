# User management, for admins. There is no mail server: adding a user (or
# resetting a password) produces a setup link for the admin to pass on.
class UsersController < ApplicationController
  before_action :require_admin
  before_action :load_user, only: %i[edit update destroy setup_link]

  def index
    @users = User.order(:email)
    @session_counts = Session.active.group(:user_id).count
  end

  def new
    @user = User.new(role: "member")
  end

  def create
    @user = User.new(user_params)
    if @user.save
      @link = setup_url(@user)
      render :link, status: :created
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = user_params
    if @user.last_admin? && attrs[:role].present? && attrs[:role] != "admin"
      @user.assign_attributes(attrs)
      @user.errors.add(:role, "can't change: this is the only admin")
      return render :edit, status: :unprocessable_entity
    end
    if @user.update(attrs)
      redirect_to users_path, notice: "Saved #{@user.display_name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You can't remove yourself."
    elsif @user.last_admin?
      redirect_to users_path, alert: "#{@user.display_name} is the only admin."
    else
      @user.destroy!
      redirect_to users_path, notice: "Removed #{@user.display_name}. Their sessions and tokens no longer work."
    end
  end

  # A fresh setup link: for someone who lost the first one or forgot their
  # password. Their current password keeps working until they use it.
  def setup_link
    @link = setup_url(@user)
    render :link
  end

  private

  def load_user
    @user = User.find(params[:id])
  end

  def user_params
    params.expect(user: %i[email name role])
  end

  def setup_url(user)
    password_setup_url(user.generate_token_for(:password_setup))
  end
end
