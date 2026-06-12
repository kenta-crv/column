class GenerationChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'generation_channel'
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
