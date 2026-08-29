require 'rubocop/bloom_jewel'
require 'rubocop/bloom_jewel/config_compatibility'

module RuboCop
  module BloomJewel
    # RuboCop configuration combiner and patcher for two-way compatibility.
    #
    # @note This is a hacky solution to allow configuration merge
    # and patch on-the-go without triggering any validation errors from
    # RuboCop side. A load_file with check: false "can" solve this,
    # however if there are any inherit_from/inherit_gem found, there is
    # no way to disable checks recursively.
    class ConfigCombiner
      RUBOCOP_VERSION = Gem::Version.new(RuboCop::Version::STRING)

      attr_reader :base_file, :result

      # @param name [String] configuration name to lookup
      # @note as this configuration patcher applies for this specific
      # gem/module, the consideration of "adjustable" directory is
      # not considered.
      def initialize(name)
        @base_name = name
        @base_file = CONFIG_DIR / "#{name}.yml"
        @patch_files = CONFIG_DIR.glob("#{name}_*.yml")
        @result = {}

        @inherit_from_files = []

        reorder_patch_files
      end

      # processes the RuboCop config combiner
      #
      # @return [void]
      def process!
        merge_with_patch_files
        validate_config_inheritance_resolution!
        resolve_inheritance_from_files
        perform_compatiblity_fixes

        nil
      end

      private
      # Sort patches based on specified version.
      # Format is <prefix>_<version>.yml
      #
      # @return [void]
      def reorder_patch_files
        @patch_files.map do |path| [path.basename('.yml').to_path.delete_prefix("#{@base_name}_"), path] end
          .select do |(target_version_str, _path)| target_version_str.match?(/^\d+([.]\d+)+$/) end
          .map do |(target_version_str, path)| [Gem::Version.new(target_version_str), path] end
          .select do |(target_version, _path)| RUBOCOP_VERSION >= target_version end
          .sort_by(&:first)
          .map(&:last)
          .tap(&@patch_files.method(:replace))
      end

      # Combine all configuration from base to all patches in specified order.
      #
      # @return [void]
      def merge_with_patch_files
        @result = [@base_file, *@patch_files].select(&:exist?)
          .inject({}) do |obj, path|
            partial = ConfigLoader.load_yaml_configuration(path.to_path)
            @inherit_from_files.concat(Array(partial.delete('inherit_from'))) if partial.key?('inherit_from')
            ConfigLoader.merge(obj, partial)
          end.compact
      end

      # Find all non-relative, non-local file pointing inherit_from.
      # This tweaks a bit from the intended `inherit_from` because
      # this `inherit_from` is specficially for injection rather than
      # configuration itself.
      #
      # @raise [ConfigNotFoundError] upon failing to satisfy the local-relative gem only files requirement
      # @return [void]
      def validate_config_inheritance_resolution!
        invalid_files = @inherit_from_files.reject do |fn|
          uri, path = URI(fn), CONFIG_DIR / fn

          uri.scheme.nil? && uri.host.nil? && !uri.path.nil? &&
          uri.query.nil? && uri.fragment.nil? && uri.opaque.nil? &&
          path.relative? && path.exist? && path.extname.to_s == '.yml'
        end

        fail ConfigNotFoundError, <<~EOS unless invalid_files.empty?
          Configuration file cannot be loaded: #{invalid_files.join(', ')}.
          Provided file can only be a relative path from the gem and must exists.
        EOS
      end

      # resolve configuration inheritance.
      #
      # @return [void]
      def resolve_inheritance_from_files
        @inherit_from_files.map do |fn| File.basename(fn, File.extname(fn)) end
          .map(&self.class.method(:new))
          .each(&:process!)
          .map(&:result)
          .inject(@result, &ConfigLoader.method(:merge))
          .tap(&@result.method(:replace))
      end

      # adjusts configuration based on current version of RuboCop
      #
      # @return [void]
      def perform_compatiblity_fixes
        ConfigCompatibility.handle_compatibility(@result, @base_file)
      end
    end
  end
end
