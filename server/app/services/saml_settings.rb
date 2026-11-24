# ruby-saml settings for this service provider. Entity ID and ACS URL derive
# from the public base URL, so they match what is registered at the IdP.
module SamlSettings
  module_function

  def for(base_url, config = SsoConfig.current)
    settings = OneLogin::RubySaml::Settings.new(config.idp_metadata_xml.present? ? config.idp : {})
    settings.sp_entity_id = "#{base_url}/saml/metadata"
    settings.assertion_consumer_service_url = "#{base_url}/saml/acs"
    settings.name_identifier_format = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    settings.security[:want_assertions_signed] = false # the response or the assertion must be signed; ruby-saml enforces one
    settings.security[:strict_audience_validation] = true
    settings.soft = true
    settings
  end
end
