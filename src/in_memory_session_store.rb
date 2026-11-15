require "securerandom"

module Foobara
  class McpConnector < CommandConnector
    class InMemorySessionStore
      DEFAULT_TTL = 60 * 60

      attr_reader :ttl, :clock

      def initialize(ttl: DEFAULT_TTL, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @ttl = ttl
        @clock = clock
        @entries = {}
        @mutex = Mutex.new
      end

      def create(session)
        id = SecureRandom.uuid

        @mutex.synchronize do
          prune_expired
          @entries[id] = [session, clock.call]
        end

        id
      end

      def find(id)
        @mutex.synchronize do
          session, last_seen_at = @entries[id]

          return nil unless session

          if expired?(last_seen_at)
            @entries.delete(id)
            return nil
          end

          @entries[id] = [session, clock.call]
          session
        end
      end

      def delete(id)
        @mutex.synchronize do
          !@entries.delete(id).nil?
        end
      end

      def size
        @mutex.synchronize { @entries.size }
      end

      private

      def prune_expired
        @entries.delete_if { |_id, (_session, last_seen_at)| expired?(last_seen_at) }
      end

      def expired?(last_seen_at)
        clock.call - last_seen_at > ttl
      end
    end
  end
end
