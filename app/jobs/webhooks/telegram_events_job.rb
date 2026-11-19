class Webhooks::TelegramEventsJob < ApplicationJob
  queue_as :default

  # Retries cover ~2 minutes of Telegram API trouble; after that the message is saved with a
  # notice instead of its attachment, so agents can ask the customer to resend it.
  retry_on Telegram::AttachmentDownload::AttachmentDownloadError, wait: :polynomially_longer, attempts: 4 do |job, _error|
    job.perform_with_attachment_fallback(*job.arguments)
  end

  def perform(params = {})
    return unless params[:bot_token]

    channel = Channel::Telegram.find_by(bot_token: params[:bot_token])

    if channel_is_inactive?(channel)
      log_inactive_channel(channel, params)
      return
    end

    process_event_params(channel, params)
  end

  def perform_with_attachment_fallback(params = {})
    @attachment_fallback = true
    perform(params)
  end

  private

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true unless channel.account.active?

    false
  end

  def log_inactive_channel(channel, params)
    message = if channel&.id
                "Account #{channel.account.id} is not active for channel #{channel.id}"
              else
                "Channel not found for bot_token: #{params[:bot_token]}"
              end
    Rails.logger.warn("Telegram event discarded: #{message}")
  end

  def process_event_params(channel, params)
    return unless params[:telegram]

    if params.dig(:telegram, :edited_message).present? || params.dig(:telegram, :edited_business_message).present?
      Telegram::UpdateMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    else
      Telegram::IncomingMessageService.new(
        inbox: channel.inbox,
        params: params['telegram'].with_indifferent_access,
        attachment_fallback: @attachment_fallback || false
      ).perform
    end
  end
end
