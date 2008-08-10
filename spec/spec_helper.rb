require 'spec'

# Load custom matchers
Dir[File.expand_path("#{File.dirname(__FILE__)}/matchers/*.rb")].uniq.each do |file|
  require file
end

Spec::Runner.configure do |config|
end