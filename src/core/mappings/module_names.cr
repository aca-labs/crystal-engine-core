require "action-controller/logger"
require "driver/storage"
require "driver/subscriptions"
require "models/control_system"
require "models/module"

require "../module_manager"
require "./control_system_modules"

module PlaceOS::Core
  class Mappings::ModuleNames < Resource(Model::Module)
    def process_resource(event) : Resource::Result
      if event[:action] == Action::Updated
        ModuleNames.update_module_mapping(event[:resource], logger)
      else
        Resource::Result::Skipped
      end
    rescue e
      message = e.try(&.message) || ""
      mod = event[:resource]
      logger.tag_error("while updating mapping for module", name: mod.name, custom_name: mod.custom_name, error: message)
      errors << {name: mod.name.as(String), reason: message}

      Resource::Result::Error
    end

    def self.update_module_mapping(
      mod : Model::Module,
      logger : TaggedLogger = TaggedLogger.new(Logger.new(STDOUT))
    ) : Resource::Result
      module_id = mod.id.as(String)
      # Only consider name change events
      return Resource::Result::Skipped unless mod.custom_name_changed?
      # Only one core updates the mappings
      return Resource::Result::Skipped unless ModuleManager.instance.discovery.own_node?(module_id)

      # Update mappings for ControlSystems containing the Module
      Model::ControlSystem.using_module(module_id).each do |control_system|
        ControlSystemModules.set_mappings(control_system, mod)
      end

      Resource::Result::Success
    end
  end
end
