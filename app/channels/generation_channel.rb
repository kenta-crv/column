class GenerationChannel < ApplicationCable::Channel
  def subscribed
    stream_from "GenerationChannel"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
