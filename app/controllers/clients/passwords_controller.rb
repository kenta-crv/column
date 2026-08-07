# frozen_string_literal: true

class Clients::PasswordsController < Devise::PasswordsController
  layout "auth"

  def create
    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    if successfully_sent?(resource)
      respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
    else
      respond_with(resource)
    end
  end

  protected

  def after_sending_reset_password_instructions_path_for(_resource_name)
    client_sign_in_path_for_locale
  end
end
