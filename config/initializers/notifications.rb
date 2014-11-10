ActiveSupport::Notifications.subscribe 'unpermitted_parameters.action_controller' do |name, start, finish, id, payload|
  Rails.logger.debug(["notification:", name, start, finish, id, payload].join(" "))
end
