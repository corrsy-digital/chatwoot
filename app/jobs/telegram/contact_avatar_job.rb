# Looks up a Telegram contact's profile photo outside the incoming-message path,
# so a slow Telegram API can never cause an incoming message to be dropped.
class Telegram::ContactAvatarJob < ApplicationJob
  queue_as :purgable

  def perform(contact, channel, telegram_user_id)
    return if contact.avatar.attached?

    avatar_url = channel.get_telegram_profile_image(telegram_user_id)
    Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url) if avatar_url
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    Rails.logger.warn "Telegram::ContactAvatarJob failed for contact #{contact.id}: #{e.class} - #{e.message}"
  end
end
