VERSION = '1.3.2'.freeze

Gem::Specification.new do |s|
  s.name        = 'framework-generate'
  s.version     = VERSION
  s.summary     = 'Tool to generate an Xcode framework project'
  s.description = 'Simple tool to help generate a multiplatform, single-scheme Xcode project'
  s.authors     = ['Pierre-Marc Airoldi']
  s.email       = ['pierremarcairoldi@gmail.com']
  s.homepage    = 'https://pierremarcairoldi.com'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 2.0.0'

  s.files         = %w(README.md LICENSE) + Dir['lib/**/*.rb'] + Dir['lib/**/*.sh'] + Dir['lib/SampleFrameworkSpec']
  s.executables   = %w(framework-generate)
  s.require_paths = %w(lib)

  s.add_dependency 'xcodeproj', '>= 1.5.0', '< 2.0.0'
end
