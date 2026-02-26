require File.dirname(__FILE__) + '/../spec_helper'

describe "Eye::Dsl notify" do
  it "raise on unknown contact type" do
    conf = <<-E
      Eye.config do
        contact :vasya, :dddd, "vasya@mail.ru", :host => "localhost", :port => 12
      end
    E
    expect{ Eye::Dsl.parse(conf) }.to raise_error(Eye::Dsl::Error)
  end

  it "set notify inherited" do
    conf = <<-E
      Eye.app :bla do
        notify :vasya

        group :bla do
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {
      "bla" => {:name=>"bla",
        :notify=>{"vasya"=>:warn},
        :groups=>{"bla"=>{:name=>"bla",
          :notify=>{"vasya"=>:warn}, :application=>"bla"}}}}
  end

  it "raise on unknown level" do
    conf = <<-E
      Eye.app :bla do
        notify :vasya, :petya
      end
    E
    expect{ Eye::Dsl.parse(conf) }.to raise_error(Eye::Dsl::Error)
  end

  it "clear notify with nonotify" do
    conf = <<-E
      Eye.app :bla do
        notify :vasya, :warn

        group :bla do
          nonotify :vasya
        end
      end
    E
    Eye::Dsl.parse_apps(conf).should == {
      "bla" => {:name=>"bla",
        :notify=>{"vasya"=>:warn},
        :groups=>{"bla"=>{:name=>"bla", :notify=>{}, :application=>"bla"}}}}
  end

  it "add custom notify" do
    conf = <<-E
      class Cnot < Eye::Notify::Custom
        param :bla, String
      end

      Eye.config do
        cnot :bla => "some"
        contact :vasya, :cnot, "some"
      end

      Eye.application :bla do
        notify :vasya
      end
    E
    res = Eye::Dsl.parse(conf).to_h

    res.should == {:applications => {"bla"=>{:name=>"bla", :notify=>{"vasya"=>:warn}}},
      :defaults => {},
      :settings => {:cnot=>{:bla=>"some", :type=>:cnot}, :contacts=>{"vasya"=>{:name=>"vasya", :type=>:cnot, :contact=>"some", :opts=>{}}}}}
  end
end
