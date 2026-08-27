require 'rubocop'

module RuboCop
  module BloomJewel
    old_consts = constants

    PROJECT_ROOT = Pathname(__dir__).parent.parent.expand_path
    CONFIG_DIR   = PROJECT_ROOT / 'config'

    (constants - old_consts).map(&method(:const_get))
      .select do |c| Pathname === c end
      .each(&:freeze)
  end
end
