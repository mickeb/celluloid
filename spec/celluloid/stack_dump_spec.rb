require 'spec_helper'

describe Celluloid::StackDump do
  class BlockingActor
    include Celluloid

    def blocking
      Kernel.sleep
    end
  end

  before(:each) do
    [Celluloid::TaskFiber, Celluloid::TaskThread].each do |task_klass|
      actor_klass = Class.new(BlockingActor) do
        task_class task_klass
      end
      actor = actor_klass.new
      actor.async.blocking
    end
  end

  describe '#actors' do
    it 'should include all actors' do
      subject.actors.size.should == Celluloid::Actor.all.size
    end
  end

  describe '#threads' do
    it 'should include threads that are not actors' do
      subject.threads.size.should == Thread.list.reject { |t| t.celluloid? && t.actor && t.role == :actor }.size
    end

    it 'should include pooled threads' do
      pooled_thread = Celluloid.internal_pool.create
      subject.threads.map(&:thread_id).should include(pooled_thread.object_id)
    end

    it 'should include threads checked out of the pool for roles other than :actor' do
      thread = Celluloid.internal_pool.get
      thread.role = :other_thing
      subject.threads.map(&:thread_id).should include(thread.object_id)
    end
  end
end
