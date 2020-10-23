require "retriable"
require "uri"
require "rwlock"

require "./constants"
require "./protocol"
require "./transport"

module PlaceOS::Edge
  class Client
    WEBSOCKET_API_PATH = "/edge"

    private getter transport : Transport?
    private getter! uri : URI

    def initialize(
      uri : URI = PLACE_URI,
      secret : String = CLIENT_SECRET,
      @sequence_id : UInt64 = 0
    )
      # Mutate a copy as secret is embedded in uri
      uri = uri.dup
      uri.path = WEBSOCKET_API_PATH
      uri.query = "secret=#{secret}"
      @uri = uri
    end

    # Initialize the WebSocket API
    #
    # Optionally accepts a block called after connection has been established.
    def start
      Retriable.retry do
        # Open a websocket
        socket = HTTP::WebSocket.new(uri)

        close_channel = Channel(Nil).new

        socket.on_close do
          Log.info { "websocket to #{PLACE_URI} closed" }
          close_channel.close
        end

        id = if existing_transport = transport
               existing_transport.sequence_id
             else
               0_u64
             end

        Transport.new(socket, id) do |request|
          handle_request(request)
        end

        spawn { socket.run }

        while socket.closed?
          Fiber.yield
        end

        yield

        close_channel.receive?
      end
    end

    def handle_request(request : Protocol::Request)
    end

    # :ditto:
    def start
      start { }
    end

    def handshake
    end
  end
end
