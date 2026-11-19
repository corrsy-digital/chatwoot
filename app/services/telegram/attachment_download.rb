# Downloads an incoming Telegram attachment. Transient failures raise AttachmentDownloadError so
# the job can retry; once retries are exhausted (attachment_fallback) the message is saved with a
# visible notice instead, so agents know to ask the customer to resend it.
module Telegram::AttachmentDownload
  class AttachmentDownloadError < StandardError; end

  DOWNLOAD_ERRORS = [Down::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError].freeze
  ATTACHMENT_FAILED_NOTICE = '⚠️ The customer sent a %<kind>s, but it could not be downloaded from Telegram. Ask them to send it again.'.freeze
  ATTACHMENT_KINDS = { sticker: 'sticker', photo: 'photo', voice: 'voice message', audio: 'audio file', video: 'video',
                       video_note: 'video' }.freeze

  private

  def download_attachment
    file_download_path = inbox.channel.get_telegram_file_path(file[:file_id])
    raise AttachmentDownloadError, "no download path for file #{file[:file_id]}" if file_download_path.blank?

    Down.download(file_download_path, open_timeout: 5, read_timeout: 30)
  rescue AttachmentDownloadError, *DOWNLOAD_ERRORS => e
    error = "#{e.class} - #{e.message}".gsub(inbox.channel.bot_token, '[TOKEN]')
    Rails.logger.warn "Telegram attachment download failed for inbox #{inbox.id}: #{error}"
    raise AttachmentDownloadError, error unless attachment_fallback
  end

  def mark_attachment_download_failed
    kind = attachment_kind
    @message.content = [format(ATTACHMENT_FAILED_NOTICE, kind: kind), @message.content].compact_blank.join("\n\n")
    @message.content_attributes = @message.content_attributes.merge(
      'attachment_download_failed' => { 'kind' => kind, 'file_id' => file[:file_id] }
    )
  end

  def attachment_kind
    key = ATTACHMENT_KINDS.keys.find { |k| params[:message][k].present? }
    ATTACHMENT_KINDS.fetch(key, 'file')
  end
end
