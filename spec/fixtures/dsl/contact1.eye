class TestNotify1 < Eye::Notify::Custom

  param :host, [String]
  param :port, [Integer, String]

end

Eye.config do
  test_notify1 host: 'host', port: 22
  contact :contact1, :test_notify1, 'aaa@mail'
end
