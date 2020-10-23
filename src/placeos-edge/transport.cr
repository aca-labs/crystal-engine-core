require "http"
require "mutex"

require "./protocol"

module PlaceOS::Edge
  # WebSocket Transport
  #
  class Transport
    private getter socket : HTTP::WebSocket

    private getter socket_channel = Channel(Protocol::Message).new

    private getter response_lock = RWLock.new

    private getter responses = {} of String => Channel(Protocol::Response)

    private getter sequence_lock = Mutex.new

    private getter on_request : Protocol::Request ->

    def initialize(@socket, @sequence_id : UInt64 = 0, &@on_request : Protocol::Request ->)
      @socket.on_message &->on_message(String)
      @socket.on_binary &->on_binary(Bytes)
      spawn { write_websocket }
    end

    def sequence_id : UInt64
      sequence_lock.synchronize { @sequence_id += 1 }
    end

    # Serialize messages down the websocket
    #
    protected def write_websocket
      while message = socket_channel.receive?
        case message
        in Protocol::Binary
          socket.stream(binary: true) do |io|
            message.as(Protocol::Binary).to_io(io)
          end
        in Protocol::Text
          socket.send(message.as(Protocol::Text).to_json)
        end
      end
    end

    def close
      responses.write &.each(&.close)
      @socket.close
    end

    def send_response(message : Protocol::Response)
      socket_channel.send(message)
    end

    def send_request(message : Protocol::Request) : Protocol::Response?
      id = sequence_id

      response_channel = Channel(Protocol::Message)
      response_lock.write do
        responses[id] = response_channel
      end

      socket_channel.send(message)

      response = response_channel.receive?

      response_lock.write do
        responses.delete(id)
      end

      response
    end

    private def on_message(message)
      handle_message(Protocol::Text.from_json(message))
    rescue e : JSON::ParseException
      Log.error(exception: e) { "failed to parse incoming message: #{message}" }
    end

    private def on_binary(bytes : Slice)
      # TODO: change BinData supports serialisation from a slice
      io = IO::Memory.new(bytes, writeable: false)
      handle_message(io.read_bytes(Protocol::Binary))
    rescue e : BinData::ParseError
      Log.error(exception: e) { "failed to parse incoming binary message" }
    end

    private def handle_message(message : Protocol::Message)
      case message
      in Protocol::Response
        response_lock.read do
          if channel = responses[message.sequence_id]?
            channel.send(message)
          else
            Log.error { "unrequested response received: #{message.sequence_id}" }
          end
        end
      in Protocol::Request
        spawn do
          # TODO: remove casts once crystal correctly trims union here
          begin
            on_request.call(message.as(Protocol::Request))
          rescue e
            Log.error(exception: e) { {
              message:           e.message,
              transport_message: message.as(Protocol::Request).to_json,
            } }
          end
        end
      end
    end
  end
end
