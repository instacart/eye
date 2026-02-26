class Eye::Dsl::ProcessOpts < Eye::Dsl::Opts

  def monitor_children(&block)
    opts = Eye::Dsl::ChildProcessOpts.new
    opts.instance_eval(&block) if block
    @config[:monitor_children] ||= {}
    Eye::Utils.deep_merge!(@config[:monitor_children], opts.config)
  end

  alias xmonitor_children nop

  def application
    parent.try(:parent)
  end
  alias app application
  alias group parent

end
