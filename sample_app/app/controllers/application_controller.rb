class ApplicationController < ActionController::Base
  # Load generators post without CSRF tokens.
  skip_forgery_protection
end
