require 'rubocop/bloom_jewel'

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

      # TODO: Despite this hacky work for combining and automatically adjust
      # the configuration. This was supposed to work like how inherit_from or
      # inherit_gem was parsed from the specified configuration file
      # rather than injecting the defaults instead.
      # Once that done, does plugin worth the try rather than just loading it?
      # The point of plugin is to extend (or override) the defaults
      # from what I skimmed at the point of writing.
      #
      # @param name [String] configuration name to lookup
      # @return [{String => String, Array, Hash}]
      def load_configuration_for(name)
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

        to_rename_cops = {}
        to_remove_cops = []
        to_inherit_files = []

        # Combine all configuration from base to all patches in specified order.
        combined = [base_file, *patch_files].select(&:exist?)
          .inject({}) do |obj, path|
            partial = ConfigLoader.load_yaml_configuration(path.to_path)
            to_inherit_files.concat(Array(partial.delete('inherit_from'))) if partial.key?('inherit_from')
            ConfigLoader.merge(obj, partial)
          end.compact

        # Find all non-relative, non-local file pointing inherit_from.
        # This tweaks a bit from the intended `inherit_from` because
        # this `inherit_from` is specficially for injection rather than
        # configuration itself.
        invalid_inherit_files = to_inherit_files.reject do |fn|
          uri, path = URI(fn), CONFIG_DIR / fn

          uri.scheme.nil? && uri.host.nil? && !uri.path.nil? &&
          uri.query.nil? && uri.fragment.nil? && uri.opaque.nil? &&
          path.relative? && path.exist? && path.extname.to_s == '.yml'
        end

        fail ConfigNotFoundError, <<~EOS unless invalid_inherit_files.empty?
          Configuration file cannot be loaded: #{invalid_inherit_files.join(', ')}.
          Provided file can only be a relative path from the gem and must exists.
        EOS

        to_inherit_files.map do |fn| File.basename(fn, File.extname(fn)) end
          .map(&method(:load_configuration_for))
          .inject(combined, &ConfigLoader.method(:merge))
          .tap(&combined.method(:replace))

        config = Config.new(combined, base_file.to_path)
        obsoletion = ConfigObsoletion.new(config)

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
        combined
      end

      private
      # Injects provided configuration after combined and adjusted to the defaults.
      # @param name [String] configuration name to lookup
      # @return [void]
      def combine_settings(name)
        base_file = CONFIG_DIR / "#{name}.yml"
        combined = load_configuration_for(name)
        config = Config.new(combined, base_file.to_path)
        config = ConfigLoader.merge_with_default(config, base_file.to_path, unset_nil: false)

        ConfigLoader.instance_variable_set(:@default_configuration, config)
      end
    end
  end
end
