require 'rails_helper'

RSpec.describe Telegram::ContactAvatarJob do
  let(:channel) { create(:channel_telegram) }
  let(:contact) { create(:contact, account: channel.account) }
  let(:api) { "https://api.telegram.org/bot#{channel.bot_token}" }

  before do
    stub_request(:any, /api.telegram.org/).to_return(headers: { content_type: 'application/json' }, body: {}.to_json, status: 200)
  end

  it 'enqueues the job on the purgable queue' do
    expect { described_class.perform_later(contact, channel, 23) }.to have_enqueued_job(described_class).on_queue('purgable')
  end

  it 'enqueues an avatar download when the user has a profile photo' do
    stub_request(:get, "#{api}/getUserProfilePhotos?user_id=23").to_return(
      headers: { content_type: 'application/json' },
      body: { ok: true, result: { photos: [[{ file_id: 'small' }, { file_id: 'big' }]] } }.to_json
    )
    stub_request(:get, "#{api}/getFile?file_id=big").to_return(
      headers: { content_type: 'application/json' },
      body: { ok: true, result: { file_path: 'photos/file_1.jpg' } }.to_json
    )

    expect { described_class.perform_now(contact, channel, 23) }
      .to have_enqueued_job(Avatar::AvatarFromUrlJob)
      .with(contact, "https://api.telegram.org/file/bot#{channel.bot_token}/photos/file_1.jpg")
  end

  it 'does not raise when the Telegram API times out' do
    stub_request(:get, "#{api}/getUserProfilePhotos?user_id=23").to_timeout

    expect { described_class.perform_now(contact, channel, 23) }.not_to raise_error
  end
end
