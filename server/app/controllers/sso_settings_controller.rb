# Admin page for SAML single sign-on: the values to enter at OneLogin, and
# the IdP metadata, auto-provisioning and password-login policy.
class SsoSettingsController < ApplicationController
  before_action :require_admin

  def show
    @config = SsoConfig.current
  end

  def update
    @config = SsoConfig.current
    attrs = params.expect(sso_config: [:enabled, :button_label, :idp_metadata_url, :idp_metadata_xml,
                                       :auto_provision, :allowed_domains, :password_login])
    attrs[:allowed_domains] = attrs[:allowed_domains].to_s.split(/[\s,]+/) if attrs.key?(:allowed_domains)
    @config.assign_attributes(attrs)
    @config.fetch_metadata! if params[:fetch].present? || (@config.idp_metadata_url_changed? && @config.idp_metadata_url.present?)
    if @config.save
      redirect_to sso_settings_path, notice: "Single sign-on settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  rescue SsoConfig::MetadataError => e
    @config.errors.add(:base, e.message)
    render :show, status: :unprocessable_entity
  end
end
