require "onelogin/ruby-saml"

# A pretend SAML identity provider for tests: its own key and certificate,
# metadata, and signed responses built the way OneLogin sends them.
class FakeSamlIdp
  ENTITY = "https://idp.test/metadata".freeze
  SSO_URL = "https://idp.test/sso".freeze

  attr_reader :key, :cert

  def initialize
    @key = OpenSSL::PKey::RSA.new(2048)
    @cert = OpenSSL::X509::Certificate.new
    @cert.version = 2
    @cert.serial = 1
    @cert.subject = @cert.issuer = OpenSSL::X509::Name.parse("/CN=idp.test")
    @cert.public_key = @key.public_key
    @cert.not_before = 1.day.ago
    @cert.not_after = 1.year.from_now
    @cert.sign(@key, OpenSSL::Digest::SHA256.new)
  end

  def metadata
    <<~XML
      <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" entityID="#{ENTITY}">
        <md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          <md:KeyDescriptor use="signing"><ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:X509Data><ds:X509Certificate>#{Base64.strict_encode64(cert.to_der)}</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor>
          <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
          <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="#{SSO_URL}"/>
        </md:IDPSSODescriptor>
      </md:EntityDescriptor>
    XML
  end

  # Base64 SAMLResponse for +email+, signed (unless signed: false). Keyword
  # arguments bend one property at a time for negative tests.
  def response(email:, sp: "http://www.example.com", in_response_to: nil, attributes: {}, audience: nil,
               not_on_or_after: 5.minutes.from_now, signed: true, sign_with: nil, tamper: nil)
    now = Time.now.utc
    t = ->(time) { time.utc.strftime("%Y-%m-%dT%H:%M:%SZ") }
    irt = in_response_to ? %( InResponseTo="#{in_response_to}") : ""
    attrs = attributes.map { |k, v| %(<saml:Attribute Name="#{k}"><saml:AttributeValue>#{v}</saml:AttributeValue></saml:Attribute>) }.join
    xml = <<~XML.gsub(/>\s+</, "><").strip
      <samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_r#{SecureRandom.hex(16)}" Version="2.0" IssueInstant="#{t.(now)}" Destination="#{sp}/saml/acs"#{irt}>
        <saml:Issuer>#{ENTITY}</saml:Issuer>
        <samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
        <saml:Assertion ID="_a#{SecureRandom.hex(16)}" Version="2.0" IssueInstant="#{t.(now)}">
          <saml:Issuer>#{ENTITY}</saml:Issuer>
          <saml:Subject>
            <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">#{email}</saml:NameID>
            <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer"><saml:SubjectConfirmationData NotOnOrAfter="#{t.(not_on_or_after)}" Recipient="#{sp}/saml/acs"#{irt}/></saml:SubjectConfirmation>
          </saml:Subject>
          <saml:Conditions NotBefore="#{t.(now - 60)}" NotOnOrAfter="#{t.(not_on_or_after)}"><saml:AudienceRestriction><saml:Audience>#{audience || "#{sp}/saml/metadata"}</saml:Audience></saml:AudienceRestriction></saml:Conditions>
          <saml:AuthnStatement AuthnInstant="#{t.(now)}" SessionIndex="_s#{SecureRandom.hex(8)}"><saml:AuthnContext><saml:AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</saml:AuthnContextClassRef></saml:AuthnContext></saml:AuthnStatement>
          #{"<saml:AttributeStatement>#{attrs}</saml:AttributeStatement>" unless attrs.empty?}
        </saml:Assertion>
      </samlp:Response>
    XML
    if signed
      signer = sign_with || self
      doc = XMLSecurity::Document.new(xml)
      doc.sign_document(signer.key, signer.cert, XMLSecurity::Document::RSA_SHA256, XMLSecurity::Document::SHA256)
      xml = doc.to_s
    end
    xml = tamper.call(xml) if tamper
    Base64.strict_encode64(xml)
  end
end
