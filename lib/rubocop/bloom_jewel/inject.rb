require 'rubocop/bloom_jewel/config_combiner'

module RuboCop
  module BloomJewel
    # @api private
    module Inject; end
    class << Inject
      # Loads gem-specified cop configuration
      # @return [void]
      def load_defaults!
        combine_settings('general')
      end

      private
      # Injects provided configuration after combined and adjusted to the defaults.
      # @param name [String] configuration name to lookup
      # @return [void]
      def combine_settings(name)
        base_file = CONFIG_DIR / "#{name}.yml"
        combiner = ConfigCombiner.new(name)
        combiner.process!
        config = Config.new(combiner.result, base_file.to_path)
        config = ConfigLoader.merge_with_default(config, base_file.to_path, unset_nil: false)

        ConfigLoader.instance_variable_set(:@default_configuration, config)
        self
      end
    end
  end
end
