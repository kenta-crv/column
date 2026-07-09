require "set"

# Development の class reload をまたいでも参照を保持する
module GenerationRuntime
  mattr_accessor :running_threads, :cancelled_ids, :mutex

  self.running_threads ||= {}
  self.cancelled_ids ||= Set.new
  self.mutex ||= Mutex.new
end

