module Oauth
  # Discovery documents for MCP clients: the protected resource metadata
  # (RFC 9728) names this server as the authorization server, whose metadata
  # (RFC 8414) lists the endpoints. Behind a path prefix (/apm) the proxy
  # also maps the host-root well-known URLs here.
  class MetadataController < Base
    def protected_resource
      render json: {
        resource: "#{issuer}/mcp",
        authorization_servers: [issuer],
        scopes_supported: ["mcp"],
        bearer_methods_supported: ["header"],
        resource_name: "RubyAPM"
      }
    end

    def authorization_server
      render json: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        response_types_supported: ["code"],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: ["S256"],
        token_endpoint_auth_methods_supported: ["none"],
        revocation_endpoint_auth_methods_supported: ["none"],
        scopes_supported: ["mcp"],
        service_documentation: "https://github.com/christianbpedersen/rubyapm"
      }
    end
  end
end
