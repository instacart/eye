require File.dirname(__FILE__) + '/../../spec_helper'

describe "ChildProcess" do

  describe "starting, monitoring" do
    after :each do
      @process.stop if @process
    end

    it "should just monitoring, and do nothin" do
      start_ok_process(C.p3.merge(:monitor_children => {:checks => C.check_mem}))
      sleep 6

      @process.state_name.should == :up
      @process.children.keys.should_not == []
      @process.children.keys.size.should == 3
      @process.watchers.keys.should == [:check_alive, :check_identity, :check_children]

      @children = @process.children.values
      @children.each do |child|
        child.watchers.keys.should == [:check_memory]
        dont_allow(child).schedule :restart
      end

      sleep 7
    end

    it "should check children even when one of them respawned" do
      start_ok_process(C.p3.merge(:monitor_children => {:checks => C.check_mem}, :children_update_period => Eye::SystemResources::cache.expire + 1))
      @process.watchers.keys.should == [:check_alive, :check_identity, :check_children]

      sleep 6 # ensure that children are found

      @process.children.size.should == 3

      # now restarting
      died = @process.children.keys.sample
      die_process!(died, 9)

      # sleep enought for update list
      sleep (Eye::SystemResources::cache.expire * 2 + 3).seconds

      @process.children.size.should == 3
      @process.children.keys.should_not include(died)

      @children = @process.children.values
      @children.each do |child|
        child.watchers.keys.should == [:check_memory]
        dont_allow(child).schedule :restart
      end
    end

    it "some child get condition" do
      start_ok_process(C.p3.merge(:monitor_children => {:checks =>
        C.check_mem(:below => 50.megabytes, :times => 2)}))
      sleep 6

      @process.children.size.should == 3

      @children = @process.children.values
      crazy = @children.shift

      @children.each do |child|
        child.watchers.keys.should == [:check_memory]
        dont_allow(child).schedule(hash_including(:command => :restart))
      end

      stub(Eye::SystemResources).memory(crazy.pid){ 55.megabytes }
      stub(Eye::SystemResources).memory(anything){ 5.megabytes }

      crazy.watchers.keys.should == [:check_memory]
      mock(crazy).notify(:warn, "Bounded memory(<50Mb): [*55Mb, *55Mb] send to [:restart]")
      mock(crazy).schedule(hash_including(:command => :restart))

      sleep 4
      crazy.remove_watchers # for safe end spec
    end
  end
end
