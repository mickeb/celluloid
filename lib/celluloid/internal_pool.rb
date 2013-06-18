require 'thread'

module Celluloid
  # Maintain a thread pool FOR SPEED!!
  class InternalPool
    def initialize
      @group = ThreadGroup.new
      @mutex = Mutex.new

      reset
    end

    def busy_size
      @group.list.select(&:busy).size
    end

    def idle_size
      @group.list.reject(&:busy).size
    end

    def running?
      @group.list.any?
    end

    def reset
      # TODO: should really adjust this based on usage
      @max_idle = 16
    end

    # Get a thread from the pool, running the given block
    def get(&block)
      @mutex.synchronize do
        begin
          idle = @group.list.reject(&:busy)
          if idle.empty?
            thread = create
          else
            thread = idle.first
          end
        end until thread.status # handle crashed threads

        thread.busy = true
        thread[:celluloid_queue] << block
        thread
      end
    end

    # Return a thread to the pool
    def put(thread)
      @mutex.synchronize do
        thread.busy = false
        if idle_size >= @max_idle
          thread[:celluloid_queue] << nil
        else
          clean_thread_locals(thread)
        end
      end
    end

    # Create a new thread with an associated queue of procs to run
    def create
      queue = Queue.new
      thread = Thread.new do
        while proc = queue.pop
          begin
            proc.call
          rescue => ex
            Logger.crash("thread crashed", ex)
          end

          put thread
        end
      end

      thread[:celluloid_queue] = queue
      @group.add(thread)
      thread
    end

    # Clean the thread locals of an incoming thread
    def clean_thread_locals(thread)
      thread.keys.each do |key|
        next if key == :celluloid_queue

        # Ruby seems to lack an API for deleting thread locals. WTF, Ruby?
        thread[key] = nil
      end
    end

    def shutdown
      @mutex.synchronize do
        finalize
        @group.list.each do |thread|
          thread[:celluloid_queue] << nil
        end
      end
    end

    def kill
      @mutex.synchronize do
        finalize
        @group.list.each(&:kill)
      end
    end

    private

    def finalize
      @max_idle = 0
    end
  end
end
