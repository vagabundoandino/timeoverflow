class ApplicationController < ActionController::Base
  before_filter :configure_permitted_parameters, if: :devise_controller?
  after_filter :store_location

  include Pundit
  protect_from_forgery
  helper :glyph

  helper_method :current_organization, :admin?, :superadmin?

  # before_filter do
  #   ap session.keys
  # end

  MissingTOSAcceptance = Class.new(Exception)
  OutadedTOSAcceptance = Class.new(Exception)

  before_filter :set_locale
  before_filter :set_current_organization

  append_before_filter :check_for_terms_acceptance!, unless: :devise_controller?

  rescue_from MissingTOSAcceptance, OutadedTOSAcceptance do
    redirect_to terms_path
  end

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_up) << :username
  end

  def set_current_organization
    if org_id = session[:current_organization_id]
      @current_organization = Organization.find(org_id)
    elsif current_user
      @current_organization = current_user.organizations.first
    end
  end

  def store_location
    # store last url - this is needed for post-login redirect to whatever the
    # user last visited.
    return unless request.get?
    paths = ["/users/sign_in", "/users/sign_up", "/users/password/new",
             "/users/password/edit", "/users/confirmation", "/users/sign_out"]
    if !paths.include?(request.path) && !request.xhr?
      session[:previous_url] = request.fullpath
    end
  end

  def after_sign_in_path_for(user)
    session[:previous_url] ||
      if user.members.present?
        if user.members.any? &:manager
          users_path
        else
          users_path
        end
      else
        page_path("home")
      end
  end

  private

  def check_for_terms_acceptance!
    if user_signed_in?
      accepted = current_user.terms_accepted_at
      if accepted.nil?
        raise MissingTOSAcceptance
      elsif accepted < Document.terms_and_conditions.updated_at
        raise OutadedTOSAcceptance
      end
    end
  end

  def current_organization
    @current_organization ||= current_user.try(:organizations).try(:first)
  end

  def admin?
    current_user.try :manages?, current_organization
  end

  def superadmin?
    current_user.try :superuser?
  end

  alias :superuser? :superadmin?

  def authenticate_superuser!
    superuser? || redirect_to(root_path)
  end

  # To get locate from client supplied information
  # see http://guides.rubyonrails.org/i18n.html#setting-the-locale-from-the-client-supplied-information
  def options_locale
    current_user.try(:locale) ||
      session[:locale] ||
      http_accept_language.compatible_language_from(I18n.available_locales) ||
      I18n.default_locale
  end

  def set_locale
    # read locale from params, the session or the Accept-Language header
    I18n.locale =
      if params[:locale]
        current_user.update_attributes(locale: params[:locale]) if current_user
        params[:locale]
      else
        options_locale
      end
    # set in the session (so ppl can override what the browser sends)
    session[:locale] = I18n.locale
  end

  def user_not_authorized
    flash[:error] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end
end
