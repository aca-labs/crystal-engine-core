require "option_parser"

require "./config"

# Server defaults
port = 3000
host = "127.0.0.1"
cluster = false
process_count = 1

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{PlaceOS::Core::APP_NAME} [arguments]"

  parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| host = h }
  parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| port = p.to_i }

  parser.on("-w COUNT", "--workers=COUNT", "Specifies the number of processes to handle requests") do |w|
    cluster = true
    process_count = w.to_i
  end

  parser.on("-r", "--routes", "List the application routes") do
    ActionController::Server.print_routes
    exit 0
  end

  parser.on("-v", "--version", "Display the application version") do
    puts "#{PlaceOS::Core::APP_NAME} v#{PlaceOS::Core::VERSION}"
    exit 0
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

# Load the routes
puts "Launching #{PlaceOS::Core::APP_NAME} v#{PlaceOS::Core::VERSION}"
server = ActionController::Server.new(port, host)

# Start clustering
server.cluster(process_count, "-w", "--workers") if cluster

terminate = Proc(Signal, Nil).new do |signal|
  puts " > terminating gracefully"
  spawn(same_thread: true) { server.close }
  signal.ignore
end

# Detect ctr-c to shutdown gracefully
Signal::INT.trap &terminate
# Docker containers use the term signal
Signal::TERM.trap &terminate

# Allow signals to change the log level at run-time
logging = Proc(Signal, Nil).new do |signal|
  level = signal.usr1? ? Logger::DEBUG : Logger::INFO
  puts " > Log level changed to #{level}"
  ActionController::Base.settings.logger.level = level
  signal.ignore
end

# Turn on DEBUG level logging `kill -s USR1 %PID`
# Default production log levels (INFO and above) `kill -s USR2 %PID`
Signal::USR1.trap &logging
Signal::USR2.trap &logging

logger = ActionController::Logger::TaggedLogger.new(ActionController::Base.settings.logger)

PlaceOS::Core::ResourceManager.logger = logger
PlaceOS::Core::ModuleManager.logger = logger

PlaceOS::Core.start_managers

# Start the server
server.run do
  puts "Listening on #{server.print_addresses}"
end

# Shutdown message
puts "#{PlaceOS::Core::APP_NAME} leaps through the veldt\n"
