class GenerationChannel < ApplicationCable::Channel
  STREAM_NAME = "generation_channel"

  def subscribed
    stream_from STREAM_NAME
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
