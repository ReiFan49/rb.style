module RuboCop
  module BloomJewel
    # @api private
    class ConfigCompatibility
      VALID_TOP_KEYS = [
        'AllCops',
        'inherit_mode',
        *Cop::Registry.global.departments,
        *Cop::Registry.global.names,
      ].map(&:to_s).freeze

      attr_reader :config

      # @param config [Hash] RuboCop configuration info
      # @param path [#to_path] Filepath.
      def initialize(config, path)
        @data = config
        @config = Config.new(config, path.to_path)
        @obsoletion = ConfigObsoletion.new(@config)

        @renamed_cops = {}
        @removed_cops = []
      end

      # Check current obsoletion rules and adjust the combined configuration cops accordingly.
      #
      # @return [void]
      def retrieve_updated_cops
        @obsoletion.rules.each do |rule|
          next unless ConfigObsoletion::CopRule === rule
          next unless @data.key?(rule.old_name)

          case rule # rubocop:disable Style/MissingElse
          when ConfigObsoletion::RenamedCop
            @renamed_cops[rule.old_name] = rule.new_name
          when ConfigObsoletion::RemovedCop, ConfigObsoletion::SplitCop
            @removed_cops << rule.old_name
          end
        end
      end

      # Rename all "renamed" cop configurations
      #
      # @return [void]
      def migrate_renamed_cops_in_config
        @data.transform_keys! do |k| @renamed_cops.fetch(k, k) end
      end

      # Remove all "removed/split" cop configurations
      # For split's case, the addition must be referred with extra file version.
      #
      # @return [void]
      def migrate_removed_cops_from_config
        @data.reject! do |k| @removed_cops.include?(k) end
      end

      # Ensure all cop configurations are top-level valid.
      #
      # @return [void]
      def cleanup_invalid_top_keys!
        @data.select! do |k| VALID_TOP_KEYS.include?(k) end
      end

      # Remove extra cop parameters to follow "currently installed" definitions.
      #
      # @return [void]
      def cleanup_future_cop_parameters!
        @data.each do |cop, cop_config|
          default_config = ConfigLoader.default_configuration[cop]
          next if default_config.nil?
          next unless Hash === default_config

          supported_params = (default_config.keys | ConfigValidator::COMMON_PARAMS) - ConfigValidator::INTERNAL_PARAMS
          unsupported_params = cop_config.keys - supported_params
          cop_config.reject! do |key| unsupported_params.include?(key) end
        end
      end

      # @see #initialize
      def self.handle_compatibility(config, path)
        process = new(config, path)
        process.retrieve_updated_cops
        process.migrate_renamed_cops_in_config
        process.migrate_removed_cops_from_config
        process.cleanup_invalid_top_keys!
        process.cleanup_future_cop_parameters!
        process.config.make_excludes_absolute

        config
      end
    end
  end
end
