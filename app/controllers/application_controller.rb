class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  prepend_before_filter :login_state_setup
  before_filter :authenticate
  around_action :webhook_action

  private
  def login_state_setup
    if session[:user_id]
      User.current = User.find_by_id(session[:user_id])
    else
      User.current = nil
    end

    if User.current
      User.current.access_token = session[:access_token]
    end

    return true
  end

  def authenticate
    return true if User.current

    session[:jumpto] = request.parameters
    redirect_to root_path
    return false
  end

  def webhook_action
    settings = ApplicationSettings.webhook.select do |setting|
      setting["events"].include?(action_name)
    end
    webhooks = settings.map {|setting| Webhook.new(setting)}

    @document = nil

    yield

    if @document
      webhooks.each do |webhook|
        logger.info "Posting minutes to #{webhook.uri}"

        payload = @document.attributes
        payload.merge!({"tags"=>[], "name"=>nil})
        @document.tags.each do |tag|
          payload["tags"] << tag.name
        end
        payload["name"] = @document.author.screen_name

        res = webhook.post(payload)

        unless res
          msg = "Failed to connect to #{webhook.uri}: Connection refused"
          flash[:error] = msg
          logger.info ("  " + msg)
        else
          logger.info "  Response: #{res.code} #{res.message}"
        end
      end
    end
  end
end
