require "action-controller/logger"

require "./cloning"
require "./compilation"

# Sequences the acquisition and production of resources
module ACAEngine::Core
  class ResourceManager
    getter logger : Logger
    getter cloning : Cloning
    getter compilation : Compilation

    @@instance : ResourceManager?

    def self.instance(testing = false) : ResourceManager
      (@@instance ||= ResourceManager.new(testing: testing)).as(ResourceManager)
    end

    def initialize(
      cloning : Cloning? = nil,
      compilation : Compilation? = nil,
      @logger = ActionController::Logger.new,
      testing = false
    )
      logger.info("cloning repositories")
      @cloning = cloning || Cloning.new(testing: testing)

      logger.info("compiling drivers")
      @compilation = compilation || Compilation.new
    end
  end
end
