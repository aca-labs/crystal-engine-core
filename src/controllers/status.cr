require "hardware"
require "placeos-compiler/helper"

require "../placeos-core/module_manager"
require "../placeos-core/resource_manager"
require "./application"

module PlaceOS::Core::Api
  class Status < Application
    base "/api/core/v1/status/"
    id_param :commit_hash

    getter module_manager : ModuleManager { ModuleManager.instance }
    getter resource_manager : ResourceManager { ResourceManager.instance }

    # General statistics related to the process
    def index
      render json: {
        compiled_drivers:         PlaceOS::Compiler::Helper.compiled_drivers,
        available_repositories:   PlaceOS::Compiler::Helper.repositories,
        running_drivers:          module_manager.running_drivers,
        module_instances:         module_manager.running_modules,
        unavailable_repositories: resource_manager.cloning.errors,
        unavailable_drivers:      resource_manager.compilation.errors,
      }
    end

    # details related to a process (+ anything else we can think of)
    # /api/core/v1/status/driver?path=/path/to/compiled_driver
    get "/driver", :driver do
      driver_path = params["path"]?
      head :unprocessable_entity unless driver_path

      manager = module_manager.proc_manager_by_driver?(driver_path)
      head :not_found unless manager

      response = {
        running:          manager.running?,
        module_instances: manager.module_instances,
        last_exit_code:   manager.last_exit_code,
        launch_count:     manager.launch_count,
        launch_time:      manager.launch_time,
      }

      # Obtain process statistics - anything that might be useful for debugging
      if manager.running?
        process = Hardware::PID.new(manager.pid)
        memory = Hardware::Memory.new

        percentage_cpu = process.stat.cpu_usage!
        # 0 utilization for NaNs
        percentage_cpu = 0_f64 if percentage_cpu.nan?
        percentage_cpu = 100_f64 if percentage_cpu.infinite?

        response = response.merge({
          # CPU in % and memory in KB
          percentage_cpu: percentage_cpu,
          memory_total:   memory.total,
          memory_usage:   process.memory,
        })
      end

      render json: response
    end

    # details about the overall machine load
    get "/load", :load do
      process = Hardware::PID.new
      memory = Hardware::Memory.new
      cpu = Hardware::CPU.new

      core_cpu = process.stat.cpu_usage!
      total_cpu = cpu.usage!

      # 0 utilization for NaNs
      core_cpu = 0_f64 if core_cpu.nan?
      total_cpu = 0_f64 if total_cpu.nan?
      core_cpu = 100_f64 if core_cpu.infinite?
      total_cpu = 100_f64 if total_cpu.infinite?

      render json: {
        # These will be the values in the container but that's all good
        hostname:  System.hostname,
        cpu_count: System.cpu_count,

        # these are as a percent of the total available
        core_cpu:  core_cpu,
        total_cpu: total_cpu,

        # Memory in KB
        memory_total: memory.total,
        memory_usage: memory.used,
        core_memory:  memory.used,
      }
    end

    # Returns the lists of modules the drivers report to have loaded
    get "/loaded", :loaded do
      render json: module_manager.loaded_modules
    end

    # Overriding initializers for dependency injection
    ###########################################################################

    def initialize(@context, @action_name = :index, @__head_request__ = false)
      super(@context, @action_name, @__head_request__)
    end

    def initialize(
      context : HTTP::Server::Context,
      action_name = :index,
      @module_manager : ModuleManager = ModuleManager.instance,
      @resource_manager : ResourceManager = ResourceManager.instance
    )
      super(context, action_name)
    end
  end
end
