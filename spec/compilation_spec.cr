require "placeos-compiler/compiler"
require "placeos-compiler/helper"

require "./helper"

module PlaceOS::Core
  describe Compilation, tags: "resource" do
    it "compiles drivers" do
      # Set up a temporary directory
      _, repository, driver, _ = setup

      repository_name = repository.folder_name.as(String)
      repository_uri = repository.uri.as(String)
      driver_file = driver.file_name.as(String)

      # Clone driver repository
      PlaceOS::Compiler.clone_and_install(
        repository: repository_name,
        repository_uri: repository_uri,
      )

      # Commence compilation
      compiler = Compilation.new.start
      compiler.processed.size.should eq 1
      compiler.processed.first[:resource].id.should eq driver.id

      driver.reload!

      PlaceOS::Compiler::Helper.compiled?(driver_file, driver.commit.not_nil!, driver.id.not_nil!).should be_true

      compiler.stop
    end
  end
end
