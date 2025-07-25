
module Faraday
  Middleware = RackBuilder unless const_defined?('Middleware')
end