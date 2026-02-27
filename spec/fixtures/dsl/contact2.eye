class TestNotify2 < Eye::Notify::Custom

  param :host, [String]
  param :port, [Integer, String]
  param :user, [String]

end

Eye.config do
  test_notify2 host: 'host', port: 22, user: 'asdf'
  contact :contact2, :test_notify2, 'asdf2'
end
