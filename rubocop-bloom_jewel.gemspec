require_relative 'lib/rubocop/bloom_jewel/version'

Gem::Specification.new do |s|
  s.name        = "rubocop-bloom_jewel"
  s.version     = RuboCop::BloomJewel::VERSION
  s.authors     = [
    %(Rei Hakurei),
  ]
  s.email       = %w(contact@bloom-juery.net)

  s.summary     = "Personalized RuboCop style preference"
  s.homepage    = "https://bloom-juery.net"
  s.license     = "BSD-3-Clause-Clear"

  s.metadata['homepage_uri']    = s.homepage
  s.metadata['source_code_uri'] = s.homepage

  begin
    s.files = Dir.chdir(File.expand_path('..', __FILE__)) do
      `git ls-files -z -- config lib LICENSE README.md`.split(0.chr).select do |fn|
        fn.start_with?('lib/') ? fn.end_with?('.rb') : true
      end
    end

    fail if s.files.empty?
  rescue RuntimeError, Errno::ENOENT
    s.files = Dir.glob(
      [
        'config/*.yml',
        'lib/**/*.rb',
        'LICENSE',
        'README.md',
      ],
      base: File.expand_path('..', __FILE__),
    )
  end
  s.require_paths = %w(lib)

  s.add_development_dependency 'rake'

  s.add_dependency 'rubocop', '~> 1.17'
end
