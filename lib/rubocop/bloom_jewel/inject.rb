require 'rubocop/bloom_jewel'

module RuboCop
  module BloomJewel
    module Inject; end
    class << Inject
      def load_defaults!
        combine_settings('general')
      end

      private
      def combine_settings(name)
        # Prepare files to load
        base_file = CONFIG_DIR / "#{name}.yml"
        patch_files = CONFIG_DIR.glob("#{name}_*.yml")
        rubocop_version = Gem::Version.new(RuboCop::Version::STRING)

        # Sort patches based on specified version.
        # Format is <prefix>_<version>.yml
        patch_files.map do |path| [path.basename('.yml').to_path.delete_prefix("#{name}_"), path] end
          .select do |(target_ver, _path)| target_ver.match?(/^\d+([.]\d+)+$/) end
          .map do |(target_ver, path)| [Gem::Version.new(target_ver), path] end
          .select do |(target_ver, path)| rubocop_version >= target_ver end
          .sort_by(&:first)
          .map(&:last)
          .tap(&patch_files.method(:replace))

        # Combine all configuration from base to all patches in specified order.
        combined = [base_file, *patch_files].select(&:exist?)
          .inject({}) do |obj, path| ConfigLoader.merge(obj, ConfigLoader.load_yaml_configuration(path.to_path)) end
          .compact
        config = Config.new(combined, base_file.to_path)
        obsoletion = ConfigObsoletion.new(config)
        to_rename_cops = {}
        to_remove_cops = []

        # Check current obsoletion rules and adjust the combined configuration cops accordingly.
        obsoletion.rules.each do |rule|
          next unless ConfigObsoletion::CopRule === rule
          next unless combined.key?(rule.old_name)

          case rule # rubocop:disable Style/MissingElse
          when ConfigObsoletion::RenamedCop
            to_rename_cops[rule.old_name] = rule.new_name
          when ConfigObsoletion::RemovedCop, ConfigObsoletion::SplitCop
            to_remove_cops << rule.old_name
          end # rubocop:enable Style/MissingElse
        end
        combined.transform_keys! do |k|
          to_rename_cops.fetch(k, k)
        end
        combined.reject! do |k| to_remove_cops.include?(k) end
        combined.each do |cop, cop_config|
          default_config = ConfigLoader.default_configuration[cop]
          next if default_config.nil?
          next unless Hash === default_config

          supported_params = (default_config.keys | ConfigValidator::COMMON_PARAMS) - ConfigValidator::INTERNAL_PARAMS
          unsupported_params = cop_config.keys - supported_params
          cop_config.reject! do |key| unsupported_params.include?(key) end
        end

        config.make_excludes_absolute
        config = ConfigLoader.merge_with_default(config, base_file.to_path, unset_nil: false)
        ConfigLoader.instance_variable_set(:@default_configuration, config)
      end
    end
  end
end
