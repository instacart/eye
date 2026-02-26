# load submodules, here just for example
Eye.load('./eye/*.rb')

# Eye self-configuration section
Eye.config do
  logger '/tmp/eye.log'
end

# Adding application
Eye.application 'test' do
  # All options inherits down to the config leafs.
  # except `env`, which merging down

  # uid "user_name" # run app as a user_name (optional) - available only on ruby >= 2.0
  # gid "group_name" # run app as a group_name (optional) - available only on ruby >= 2.0

  working_dir File.expand_path(File.join(File.dirname(__FILE__), %w[processes]))
  stdall 'trash.log' # stdout,err logs for processes by default
  env 'APP_ENV' => 'production' # global env for each processes
  trigger :flapping, times: 10, within: 1.minute, retry_in: 10.minutes

  group 'samples' do
    chain grace: 5.seconds # chained start-restart with 5s interval, one by one.

    # eye daemonized process
    process :sample1 do
      pid_file '1.pid' # pid_path will be expanded with the working_dir
      start_command 'ruby ./sample.rb'

      # when no stop_command or stop_signals, default stop is [:TERM, 0.5, :KILL]
      # default `restart` command is `stop; start`

      daemonize true
      stdall 'sample1.log'

      check :memory, every: 20.seconds, below: 300.megabytes, times: [3, 5]
    end

    # self daemonized process
    process :sample2 do
      pid_file '2.pid'
      start_command 'ruby ./sample.rb -d --pid 2.pid --log sample2.log'
      stop_command 'kill -9 {PID}'

      # ensure the memory is below 300Mb the last 3 times checked
      check :memory, every: 20.seconds, below: 300.megabytes, times: 3
    end
  end

  # daemon with 3 children
  process :forking do
    pid_file 'forking.pid'
    start_command 'ruby ./forking.rb start'
    stop_command 'ruby forking.rb stop'
    stdall 'forking.log'

    start_timeout 10.seconds
    stop_timeout 5.seconds

    monitor_children do
      restart_command 'kill -2 {PID}' # for this child process
      check :memory, below: 300.megabytes, times: 3
    end
  end

end
