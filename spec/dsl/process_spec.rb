require File.dirname(__FILE__) + '/../spec_helper'

describe "Eye::Dsl" do

  it "process without pid_file should raise" do
    conf = <<-E
      Eye.application("bla") do
        process("1") do
          stdout "1.log"
        end
      end
    E
    expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
  end

  it "valid process" do
    conf = <<-E
      Eye.application("bla") do
        process("1") do
          pid_file "1.pid"
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  it "process return Object" do
    conf = <<-E
    Eye.application("bla") do
      p = process("1") { pid_file "1.pid" }
      env "A" => p.pid_file
    end
    E
    Eye::Dsl.parse_apps(conf)['bla'][:environment].should == {'A' => '1.pid'}
  end

  it "not allowed : in names" do
    conf = <<-E
      Eye.application("bla") do
        process("1:2") do
          pid_file "1.pid"
        end
      end
    E
    expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
  end

  it "disable process" do
    conf = <<-E
      Eye.application("bla") do
        env "a" => 'b'
        xprocess("1") do
          pid_file "1.pid"
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla" => {:environment=>{"a"=>"b"}, :name => "bla"}}
  end

  it "process with times" do
    conf = <<-E
      Eye.application("bla") do
        2.times do |i|
          process("\#{i}") do
            pid_file "\#{i}.pid"
          end
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"0"=>{:pid_file=>"0.pid", :application=>"bla", :group=>"__default__", :name=>"0"}, "1"=>{:pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  it "process with def" do
    conf = <<-E
      def add_process(proxy, name)
        proxy.process(name) do
          pid_file "\#{name}.pid"
        end
      end

      Eye.application("bla") do
        add_process(self, "1")
        add_process(self, "2")
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}, "2"=>{:pid_file=>"2.pid", :application=>"bla", :group=>"__default__", :name=>"2"}}}}}}
  end

  it "process with def and without proxy, O_o this works!!!" do
    conf = <<-E
      def add_process(name)
        process(name) do
          pid_file "\#{name}.pid"
        end
      end

      Eye.application("bla") do
        add_process("1")
        group(:gr){ add_process("2") }
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name=>"bla", :groups=>{"__default__"=>{:name=>"__default__", :application=>"bla", :processes=>{"1"=>{:name=>"1", :application=>"bla", :group=>"__default__", :pid_file=>"1.pid"}}}, "gr"=>{:name=>"gr", :application=>"bla", :processes=>{"2"=>{:name=>"2", :application=>"bla", :group=>"gr", :pid_file=>"2.pid"}}}}}}
  end

  it "process with constant" do
    conf = <<-E
      BLA = "1.pid"

      Eye.application("bla") do
        process("1") do
          pid_file BLA
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  it "when 2 processes with same pid_file, its ERROR" do
    conf = <<-E
      def add_process(proxy, name)
        proxy.process(name) do
          pid_file "same.pid"
        end
      end

      Eye.application("bla") do
        add_process(self, "1")
        add_process(self, "2")
      end
    E
    expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
  end

  it "when 2 processes with same name, should squash" do
    conf = <<-E
      Eye.application("bla") do
        process("1"){pid_file "11"}
        process("1"){pid_file "12"}
      end
    E
    Eye::Dsl.parse_apps(conf).should == {'bla' => {:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"12", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  describe "stdout, stder, stdall" do
    it "stdout, stderr" do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            stdout  "1.log"
            stderr "2.log"
            pid_file "1.pid"
          end
        end
      E
      Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:stdout=>"1.log", :stderr=>"2.log", :pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
    end

    it "stdall" do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            stdall   "1.log"
            pid_file "1.pid"
          end
        end
      E
      Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:stdout=>"1.log", :stderr=>"1.log", :stdall => "1.log", :pid_file=>"1.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
    end

  end

  describe "pid_file is invalid" do
    it "pid_file in app is invalid" do
      conf = <<-E
        Eye.application("bla") do
          pid_file "11"

          process("1") do
            pid_file "12"
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "pid_file in group is invalid" do
      conf = <<-E
        Eye.application("bla") do

          group("mini") do
            pid_file "11"
            process("1"){ pid_file "12" }
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end
  end


  it "valid process with proxies" do
    conf = <<-E
      Eye.application("bla") do |app|
        app.process("1") do |p|
          p.pid_file "2.pid"
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"2.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  it "valid process with proxies" do
    conf = <<-E
      Eye.application("bla") do |app|
        app.process("1") do |p|
          p.pid_file = "2.pid"
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {"bla"=>{:name => "bla", :groups=>{"__default__"=>{:name => "__default__", :application => "bla", :processes=>{"1"=>{:pid_file=>"2.pid", :application=>"bla", :group=>"__default__", :name=>"1"}}}}}}
  end

  describe "blank envs" do

    it "empty env" do
      conf = <<-E
        Eye.application("bla") do
          env nil
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "empty env" do
      conf = <<-E
        Eye.application("bla") do
          env []
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "empty env" do
      conf = <<-E
        Eye.application("bla") do
          env 'asdfsdf'
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "should accept nil value" do
      conf = <<-E
        Eye.application("bla") do
          env "SOME" => nil
        end
      E
      Eye::Dsl.parse_apps(conf).should == {"bla" => {:name=>"bla", :environment=>{"SOME"=>nil}}}
    end

  end

  describe "stop_signals" do
    it "set" do
      conf = <<-E
        Eye.app("bla") { process('1') { pid_file '1'; stop_signals :Quit, 1 } }
      E
      r = Eye::Dsl.parse_apps(conf)
      r['bla'][:groups]['__default__'][:processes]['1'][:stop_signals].should == [:Quit, 1]

      conf = <<-E
        Eye.app("bla") { process('1') { pid_file '1'; stop_signals [:Quit, 1] } }
      E
      r = Eye::Dsl.parse_apps(conf)
      r['bla'][:groups]['__default__'][:processes]['1'][:stop_signals].should == [:Quit, 1]
    end

    it "get" do
      conf = <<-E
        Eye.app("bla") { pp = process('1') { pid_file '1'; stop_signals :Quit, 1 }
          process('2') { pid_file '2'; stop_signals pp.stop_signals }
        }
      E
      r = Eye::Dsl.parse_apps(conf)
      r['bla'][:groups]['__default__'][:processes]['2'][:stop_signals].should == [:Quit, 1]
    end
  end

  describe "validation" do
    it "bad string" do
      conf = "Eye.app('bla'){ self.working_dir = {} }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.working_dir = [] }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.working_dir = 5.6 }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.working_dir = false }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "good string" do
      conf = "Eye.app('bla'){ self.working_dir = nil }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

      conf = "Eye.app('bla'){ self.working_dir = 'bla' }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
    end

    it "bad bool" do
      conf = "Eye.app('bla'){ self.clear_pid = {} }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.clear_pid = [] }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.clear_pid = 5.6 }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.clear_pid = 'false' }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "good bool" do
      conf = "Eye.app('bla'){ self.clear_pid = nil }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

      conf = "Eye.app('bla'){ self.clear_pid = true }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

      conf = "Eye.app('bla'){ self.clear_pid = false }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
    end

    it "bad interval" do
      conf = "Eye.app('bla'){ self.clear_pid = {} }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.start_timeout = [] }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.start_timeout = false }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

      conf = "Eye.app('bla'){ self.start_timeout = 'false' }"
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)
    end

    it "good interval" do
      conf = "Eye.app('bla'){ self.start_timeout = nil }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

      conf = "Eye.app('bla'){ self.start_timeout = 10.seconds }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

      conf = "Eye.app('bla'){ self.start_timeout = 1.5.seconds }"
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
    end

  end

  describe "process validations" do
    it "validate daemonize command" do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            daemonize true
            start_command "sh -c 'echo some; ruby 1.rb'"
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Process::Validate::Error)

      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            daemonize true
            start_command "echo some && ruby 1.rb"
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Process::Validate::Error)

      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            daemonize true
            start_command "ruby 1.rb"
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
    end

    it "not validate non-daemonize command" do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            start_command "sh -c 'echo some && ruby 1.rb'"
          end
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
    end
  end

  it "validate stop_signals" do
    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals [:QUIT, :KILL] } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.to raise_error(Eye::Dsl::Error)

    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals [:QUIT] } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals [:QUIT, 10] } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals :QUIT, 10 } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals [9, 15] } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error

    conf = <<-E
      Eye.application("bla"){ process("1") { pid_file "1.pid"; stop_signals ['kill', 15] } }
    E
    expect{Eye::Dsl.parse_apps(conf)}.not_to raise_error
  end

  it "skip_group_action" do
    conf = <<-E
      Eye.application("bla") do
        skip_group_action :restart
      end
    E
    Eye::Dsl.parse_apps(conf)['bla'][:skip_group_actions].should == {:restart => true}
  end

  describe "load_env" do
    it "from file" do
      conf = <<-E
        Eye.application("bla") do
          load_env "#{fixture('dsl/env1')}"
        end
      E
      Eye::Dsl.parse_apps(conf)['bla'][:environment].should == {"A"=>"11", "B" => "12=13", "E" => "55", "F" => "stuff", "G" => "more"}
    end

    it "file not found" do
      conf = <<-E
        Eye.application("bla") do
          load_env "#{fixture('dsl/env2')}"
        end
      E
      expect{Eye::Dsl.parse_apps(conf)}.to raise_error
    end

    it "file not found, but ignore option" do
      conf = <<-E
        Eye.application("bla") do
          load_env "#{fixture('dsl/env2')}", false
        end
      E
      Eye::Dsl.parse_apps(conf)['bla'][:environment].should == nil
    end

    it "expand path from working_dir" do
      conf = <<-E
        Eye.application("bla") do
          working_dir "#{File.dirname(fixture('dsl/env1'))}"
          load_env "env1"
        end
      E
      Eye::Dsl.parse_apps(conf)['bla'][:environment].should == {"A"=>"11", "B" => "12=13", "E" => "55", "F" => "stuff", "G" => "more"}
    end
  end

end
