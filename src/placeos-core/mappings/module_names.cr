require "placeos-driver/storage"
require "placeos-driver/subscriptions"
require "placeos-models/control_system"
require "placeos-models/module"

require "../module_manager"
require "./control_system_modules"

module PlaceOS::Core
  class Mappings::ModuleNames < Resource(Model::Module)
    protected getter module_manager : ModuleManager

    def initialize(
      @module_manager : ModuleManager = ModuleManager.instance
    )
      super()
    end

    def process_resource(action : RethinkORM::Changefeed::Event, resource : PlaceOS::Model::Module) : Resource::Result
      if action.updated?
        ModuleNames.update_module_mapping(resource, module_manager)
      else
        Resource::Result::Skipped
      end
    rescue exception
      Log.error(exception: exception) { {message: "while updating mapping for module", name: resource.name, custom_name: resource.custom_name} }
      raise Resource::ProcessingError.new(resource.name, "#{exception} #{exception.message}", cause: exception)
    end

    def self.update_module_mapping(
      mod : Model::Module,
      module_manager : ModuleManager = ModuleManager.instance
    ) : Resource::Result
      module_id = mod.id.as(String)
      # Only consider name change events
      return Resource::Result::Skipped unless mod.custom_name_changed?
      # Only one core updates the mappings
      return Resource::Result::Skipped unless module_manager.discovery.own_node?(module_id)

      # Update mappings for ControlSystems containing the Module
      Model::ControlSystem.using_module(module_id).each do |control_system|
        ControlSystemModules.set_mappings(control_system, mod)
      end

      Resource::Result::Success
    end
  end
end
